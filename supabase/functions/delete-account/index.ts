import { createClient } from "npm:@supabase/supabase-js@2";
import {
  corsHeaders,
  json,
  limitedJson,
  requiredEnv,
} from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) {
      return json({ error: "Authentication required" }, 401);
    }
    const payload = await limitedJson(request, 1024);
    if (payload.confirmation !== "DELETE") {
      return json({ error: "Deletion confirmation is required" }, 400);
    }

    const url = requiredEnv("SUPABASE_URL");
    const userClient = createClient(url, requiredEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authorization } },
    });
    const adminClient = createClient(
      url,
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }
    const userId = userData.user.id;

    const { data: staff } = await adminClient
      .from("admins")
      .select("user_id")
      .eq("user_id", userId)
      .maybeSingle();
    if (staff) {
      return json({ error: "Staff accounts require administrator removal" }, 403);
    }

    const { data: activeOrder, error: orderError } = await adminClient
      .from("orders")
      .select("id")
      .eq("user_id", userId)
      .not("order_status", "in", "(collected,delivered,cancelled,rejected)")
      .limit(1)
      .maybeSingle();
    if (orderError) throw orderError;
    if (activeOrder) {
      return json({
        error: "Complete or cancel active orders before deleting this account",
        code: "active_orders",
      }, 409);
    }

    // The database deletion trigger anonymizes retained order rows and blocks
    // races that create an active order after the check above. Cascading
    // foreign keys remove profile, address, token, notification, and redemption
    // data in the same Auth-user deletion transaction.
    const { error: deletionError } = await adminClient.auth.admin.deleteUser(
      userId,
      false,
    );
    if (deletionError) {
      if (deletionError.message.toLowerCase().includes("active order")) {
        return json({
          error: "Complete or cancel active orders before deleting this account",
          code: "active_orders",
        }, 409);
      }
      throw deletionError;
    }

    return json({ deleted: true });
  } catch (error) {
    if (error instanceof RangeError) {
      return json({ error: "Payload too large" }, 413);
    }
    if (error instanceof SyntaxError || error instanceof TypeError) {
      return json({ error: "Invalid request body" }, 400);
    }
    console.error(error);
    return json({ error: "Account deletion failed" }, 500);
  }
});
