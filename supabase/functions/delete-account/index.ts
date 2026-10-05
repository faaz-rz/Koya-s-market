import { createClient } from "npm:@supabase/supabase-js@2";
import { requiredEnv } from "../_shared/http.ts";
import { createDeletionHandler, DeletionFailure } from "./handler.ts";

const url = requiredEnv("SUPABASE_URL");
const anonKey = requiredEnv("SUPABASE_ANON_KEY");
const options = {
  global: {
    fetch: (input: RequestInfo | URL, init?: RequestInit) => fetch(input, {
      ...init,
      signal: init?.signal
        ? AbortSignal.any([init.signal, AbortSignal.timeout(10_000)])
        : AbortSignal.timeout(10_000),
    }),
  },
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
};
const adminClient = createClient(
  url,
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  options,
);

Deno.serve(createDeletionHandler({
  async getUser(authorization) {
    const userClient = createClient(url, anonKey, {
      ...options,
      global: { ...options.global, headers: { Authorization: authorization } },
    });
    const { data, error } = await userClient.auth.getUser();
    return error ? null : data.user;
  },
  async begin(user) {
    const { data, error } = await adminClient.rpc(
      "begin_account_deletion_otp",
      {
        target_user: user.id,
        account_email: user.email,
      },
    );
    if (error) throw error;
    return data;
  },
  async sendCode(email) {
    // An isolated Auth client prevents sessions leaking between requests.
    const { error } = await createClient(url, anonKey, options).auth
      .signInWithOtp({
        email,
        options: { shouldCreateUser: false },
      });
    if (error) {
      throw new DeletionFailure(
        error.status === 429 ? "rate_limited" : "email_unavailable",
        error.status === 429 ? 429 : 503,
        60,
      );
    }
  },
  async finishSend(user, challenge, sent) {
    const { data, error } = await adminClient.from(
      "account_deletion_challenges",
    )
      .update({ status: sent ? "pending" : "failed" }).eq("user_id", user.id)
      .eq("challenge_id", challenge).eq("status", "sending").select("user_id");
    if (error) throw error;
    return data.length === 1;
  },
  async claim(user, challenge) {
    const { data, error } = await adminClient.rpc(
      "claim_account_deletion_attempt",
      {
        target_user: user.id,
        requested_challenge: challenge,
        account_email: user.email,
      },
    );
    if (error) throw error;
    return data;
  },
  async verifyCode(email, code) {
    const { data, error } = await createClient(url, anonKey, options).auth
      .verifyOtp({
        email,
        token: code,
        type: "email",
      });
    if (error?.status === 429) {
      throw new DeletionFailure("rate_limited", 429, 60);
    }
    if (error && (!error.status || error.status >= 500)) {
      throw new DeletionFailure("verification_unavailable", 503);
    }
    return error ? null : data.user?.id ?? null;
  },
  async consume(user, challenge) {
    const { data, error } = await adminClient.rpc(
      "consume_account_deletion_otp",
      {
        target_user: user.id,
        requested_challenge: challenge,
        account_email: user.email,
      },
    );
    if (error) throw error;
    return data === true;
  },
  async deleteUser(user) {
    // The database trigger rechecks active orders and anonymizes retained
    // transactions atomically with removal of the Auth user and private data.
    const { error } = await adminClient.auth.admin.deleteUser(user.id, false);
    if (error) {
      throw new DeletionFailure(
        error.message.toLowerCase().includes("active order")
          ? "active_orders"
          : "deletion_unavailable",
        error.message.toLowerCase().includes("active order") ? 409 : 503,
      );
    }
  },
  async failChallenge(user, challenge) {
    const { error } = await adminClient.from("account_deletion_challenges")
      .update({ status: "failed" }).eq("user_id", user.id)
      .eq("challenge_id", challenge).eq("status", "consumed");
    if (error) throw error;
  },
}));
