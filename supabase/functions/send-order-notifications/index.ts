import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";
import { json, requiredEnv, timingSafeEqual } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!timingSafeEqual(
    request.headers.get("x-koyas-webhook-secret") ?? "",
    requiredEnv("KOYAS_WEBHOOK_SECRET"),
  )) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const client = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );
    const credentials = JSON.parse(requiredEnv("FIREBASE_SERVICE_ACCOUNT_JSON"));
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = await auth.getAccessToken();
    const projectId = credentials.project_id as string;
    const { data: queue, error } = await client.rpc(
      "claim_notification_batch",
      { requested_limit: 50 },
    );
    if (error) throw error;

    let sent = 0;
    for (const notification of queue ?? []) {
      const { data: devices } = await client
        .from("device_tokens")
        .select("token")
        .eq("user_id", notification.user_id);
      let successful = true;
      for (const device of devices ?? []) {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: device.token,
                notification: { title: notification.title, body: notification.body },
                data: Object.fromEntries(
                  Object.entries(notification.data ?? {}).map(([key, value]) => [key, String(value)]),
                ),
                android: { priority: "high" },
                apns: { payload: { aps: { sound: "default" } } },
              },
            }),
          },
        );
        if (!response.ok) {
          let responseBody: {
            error?: { details?: Array<{ errorCode?: string }> };
          } = {};
          try {
            responseBody = await response.json();
          } catch (_) {
            // A non-JSON provider error remains retryable.
          }
          const unregistered = responseBody.error?.details?.some(
            (detail) => detail.errorCode === "UNREGISTERED",
          ) ?? false;
          if (unregistered) {
            // Do not retry or retain a token that FCM has permanently revoked.
            await client.from("device_tokens").delete().eq("token", device.token);
          } else {
            successful = false;
          }
        }
      }
      await client.from("notification_queue").update({
        processed_at: successful ? new Date().toISOString() : null,
        locked_at: null,
        attempts: notification.attempts + 1,
      }).eq("id", notification.id);
      if (successful) sent += 1;
    }
    return json({ processed: queue?.length ?? 0, sent });
  } catch (error) {
    console.error(error);
    return json({ error: "Notification dispatch failed" }, 500);
  }
});
