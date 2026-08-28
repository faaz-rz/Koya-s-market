import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json, limitedJson, requiredEnv } from "../_shared/http.ts";

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
    const keySecret = requiredEnv("RAZORPAY_KEY_SECRET");
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const adminClient = createClient(url, serviceKey);
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

    const payload = await limitedJson(request);
    const internalOrderId = payload.order_id as string | undefined;
    if (!internalOrderId) return json({ error: "order_id is required" }, 400);

    const { data: order, error: orderError } = await adminClient
      .from("orders")
      .select("id,user_id,total_paise,payment_method,payment_status,order_status,order_number,payment_expires_at")
      .eq("id", internalOrderId)
      .eq("user_id", userData.user.id)
      .single();
    if (orderError || !order) return json({ error: "Order not found" }, 404);
    if (order.payment_method !== "online") return json({ error: "Order is not online-payment eligible" }, 409);
    if (order.order_status !== "placed") return json({ error: "Order can no longer be paid" }, 409);
    if (order.payment_status === "paid") return json({ error: "Order is already paid" }, 409);
    if (!["pending", "failed"].includes(order.payment_status)) {
      return json({ error: "Order can no longer be paid" }, 409);
    }
    if (!order.payment_expires_at || Date.parse(order.payment_expires_at) <= Date.now()) {
      return json({ error: "Payment window expired" }, 409);
    }

    const { data: existing } = await adminClient
      .from("payment_events")
      .select("provider_order_id")
      .eq("order_id", order.id)
      .eq("event_type", "order_created")
      .maybeSingle();
    if (existing?.provider_order_id) {
      return json({
        razorpay_order_id: existing.provider_order_id,
        key_id: keyId,
        amount: order.total_paise,
        currency: "INR",
        merchant_name: "Koya Stores",
      });
    }

    const basic = btoa(`${keyId}:${keySecret}`);
    const razorpayResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount: order.total_paise,
        currency: "INR",
        receipt: String(order.order_number),
        notes: { internal_order_id: order.id, user_id: order.user_id },
      }),
    });
    const providerOrder = await razorpayResponse.json();
    if (!razorpayResponse.ok || !providerOrder.id) {
      console.error("Razorpay order failure", providerOrder);
      return json({ error: "Payment provider is unavailable" }, 502);
    }
    if (providerOrder.amount !== order.total_paise || providerOrder.currency !== "INR") {
      return json({ error: "Payment provider returned an invalid order" }, 502);
    }

    const { error: eventError } = await adminClient.from("payment_events").insert({
      order_id: order.id,
      provider_order_id: providerOrder.id,
      event_type: "order_created",
      payload: { amount: providerOrder.amount, currency: providerOrder.currency },
    });
    if (eventError && eventError.code !== "23505") throw eventError;

    // A concurrent request may have created and recorded a different provider
    // order first. Always return the one that the database recognizes.
    let recordedProviderOrderId = providerOrder.id as string;
    if (eventError?.code === "23505") {
      const { data: winner, error: winnerError } = await adminClient
        .from("payment_events")
        .select("provider_order_id")
        .eq("order_id", order.id)
        .eq("event_type", "order_created")
        .single();
      if (winnerError || !winner?.provider_order_id) {
        throw winnerError ?? new Error("Recorded payment order was not found");
      }
      recordedProviderOrderId = winner.provider_order_id;
    }

    return json({
      razorpay_order_id: recordedProviderOrderId,
      key_id: keyId,
      amount: order.total_paise,
      currency: "INR",
      merchant_name: "Koya Stores",
    });
  } catch (error) {
    if (error instanceof RangeError) return json({ error: "Payload too large" }, 413);
    if (error instanceof SyntaxError || error instanceof TypeError) {
      return json({ error: "Invalid request body" }, 400);
    }
    console.error(error);
    return json({ error: "Unable to create payment order" }, 500);
  }
});
