import { createClient } from "npm:@supabase/supabase-js@2";
import {
  corsHeaders,
  hmacHex,
  json,
  limitedJson,
  requiredEnv,
  timingSafeEqual,
} from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return json({ error: "Authentication required" }, 401);
    const url = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const keyId = requiredEnv("RAZORPAY_KEY_ID");
    const secret = requiredEnv("RAZORPAY_KEY_SECRET");
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const adminClient = createClient(url, serviceKey);
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

    const payload = await limitedJson(request);
    const internalOrderId = payload.order_id as string | undefined;
    const providerOrderId = payload.razorpay_order_id as string | undefined;
    const paymentId = payload.razorpay_payment_id as string | undefined;
    const suppliedSignature = payload.razorpay_signature as string | undefined;
    if (!internalOrderId || !providerOrderId || !paymentId || !suppliedSignature) {
      return json({ error: "Incomplete payment result" }, 400);
    }

    const { data: order } = await adminClient
      .from("orders")
      .select("id,user_id,total_paise,payment_method,payment_status")
      .eq("id", internalOrderId)
      .eq("user_id", userData.user.id)
      .single();
    if (!order || order.payment_method !== "online") return json({ error: "Order not found" }, 404);

    const { data: providerEvent } = await adminClient
      .from("payment_events")
      .select("id")
      .eq("order_id", internalOrderId)
      .eq("provider_order_id", providerOrderId)
      .eq("event_type", "order_created")
      .single();
    if (!providerEvent) return json({ error: "Unknown payment order" }, 409);

    const expected = await hmacHex(secret, `${providerOrderId}|${paymentId}`);
    if (!timingSafeEqual(expected, suppliedSignature)) {
      await adminClient.from("payment_events").insert({
        order_id: internalOrderId,
        provider_order_id: providerOrderId,
        provider_payment_id: paymentId,
        event_type: "signature_failed",
      });
      return json({ error: "Invalid payment signature" }, 400);
    }

    const paymentResponse = await fetch(
      `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
      { headers: { Authorization: `Basic ${btoa(`${keyId}:${secret}`)}` } },
    );
    const providerPayment = await paymentResponse.json();
    if (!paymentResponse.ok) {
      return json({ error: "Payment status is temporarily unavailable" }, 502);
    }
    if (
      providerPayment.order_id !== providerOrderId ||
      providerPayment.amount !== order.total_paise ||
      providerPayment.currency !== "INR"
    ) {
      await adminClient.from("payment_events").insert({
        order_id: internalOrderId,
        provider_order_id: providerOrderId,
        provider_payment_id: paymentId,
        event_type: "payment_mismatch",
        payload: {
          status: providerPayment.status,
          amount: providerPayment.amount,
          currency: providerPayment.currency,
        },
      });
      return json({ error: "Payment details did not match the order" }, 409);
    }

    const { error: eventError } = await adminClient.from("payment_events").upsert({
      order_id: internalOrderId,
      provider_order_id: providerOrderId,
      provider_payment_id: paymentId,
      event_type: "payment_verified",
      payload: {
        status: providerPayment.status,
        amount: providerPayment.amount,
        currency: providerPayment.currency,
        method: providerPayment.method,
      },
    }, { onConflict: "provider,provider_payment_id,event_type", ignoreDuplicates: true });
    if (eventError) throw eventError;
    const captured = providerPayment.status === "captured";
    if (captured) {
      const { error: updateError } = await adminClient
        .from("orders")
        .update({ payment_status: "paid" })
        .eq("id", internalOrderId)
        .eq("payment_method", "online");
      if (updateError) throw updateError;
    }
    return json({ verified: true, captured });
  } catch (error) {
    if (error instanceof RangeError) return json({ error: "Payload too large" }, 413);
    if (error instanceof SyntaxError || error instanceof TypeError) {
      return json({ error: "Invalid request body" }, 400);
    }
    console.error(error);
    return json({ error: "Payment verification failed" }, 500);
  }
});
