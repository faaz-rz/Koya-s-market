import { createClient } from "npm:@supabase/supabase-js@2";
import { hmacHex, json, requiredEnv, timingSafeEqual } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const declaredLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > 1024 * 1024) {
      return json({ error: "Payload too large" }, 413);
    }
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).length > 1024 * 1024) {
      return json({ error: "Payload too large" }, 413);
    }
    const signature = request.headers.get("x-razorpay-signature") ?? "";
    const expected = await hmacHex(requiredEnv("RAZORPAY_WEBHOOK_SECRET"), rawBody);
    if (!timingSafeEqual(expected, signature)) return json({ error: "Invalid signature" }, 401);

    const event = JSON.parse(rawBody);
    const eventType = event.event as string;
    const payment = event.payload?.payment?.entity;
    const providerOrderId = payment?.order_id as string | undefined;
    const providerPaymentId = payment?.id as string | undefined;
    if (!providerOrderId || !providerPaymentId) return json({ received: true });

    const client = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );
    const { data: creation } = await client
      .from("payment_events")
      .select("order_id")
      .eq("provider_order_id", providerOrderId)
      .eq("event_type", "order_created")
      .single();
    if (!creation) return json({ received: true });

    const { data: order } = await client
      .from("orders")
      .select("id,total_paise,payment_method,payment_status")
      .eq("id", creation.order_id)
      .single();
    if (!order || order.payment_method !== "online") {
      return json({ received: true });
    }

    const paymentMatches = payment.order_id === providerOrderId &&
      payment.amount === order.total_paise && payment.currency === "INR";

    const { error: eventError } = await client.from("payment_events").upsert({
      order_id: creation.order_id,
      provider_order_id: providerOrderId,
      provider_payment_id: providerPaymentId,
      event_type: eventType,
      payload: {
        event_id: request.headers.get("x-razorpay-event-id"),
        status: payment.status,
        amount: payment.amount,
        currency: payment.currency,
        method: payment.method,
        error_code: payment.error_code,
        error_description: payment.error_description,
      },
    }, { onConflict: "provider,provider_payment_id,event_type", ignoreDuplicates: true });
    if (eventError) throw eventError;

    if (eventType === "payment.captured" && paymentMatches) {
      await client.from("orders").update({ payment_status: "paid" })
        .eq("id", creation.order_id);
    } else if (
      eventType === "payment.failed" &&
      paymentMatches &&
      order.payment_status !== "paid"
    ) {
      // Webhooks can arrive out of order; never downgrade a captured payment.
      await client.from("orders").update({ payment_status: "failed" })
        .eq("id", creation.order_id)
        .neq("payment_status", "paid");
    }
    return json({ received: true });
  } catch (error) {
    console.error(error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
