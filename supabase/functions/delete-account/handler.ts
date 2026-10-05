import { corsHeaders, HttpBodyTimeout, json, limitedJson } from "../_shared/http.ts";

type User = { id: string; email?: string; email_confirmed_at?: string };
type Challenge = {
  ok: boolean;
  code?: string;
  challenge_id?: string;
  expires_at?: string;
  retry_after?: number;
};
export interface DeletionDependencies {
  getUser(authorization: string): Promise<User | null>;
  begin(user: User): Promise<Challenge>;
  sendCode(email: string): Promise<void>;
  finishSend(user: User, challenge: string, sent: boolean): Promise<boolean>;
  claim(user: User, challenge: string): Promise<Challenge>;
  verifyCode(email: string, code: string): Promise<string | null>;
  consume(user: User, challenge: string): Promise<boolean>;
  deleteUser(user: User): Promise<void>;
  failChallenge(user: User, challenge: string): Promise<void>;
}
export class DeletionFailure extends Error {
  code: string;
  status: number;
  retryAfter?: number;
  constructor(code: string, status = 500, retryAfter?: number) {
    super(code);
    this.code = code;
    this.status = status;
    this.retryAfter = retryAfter;
  }
}
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function rejected(result: Challenge) {
  const status = result.code === "rate_limited"
    ? 429
    : result.code === "staff_account"
    ? 403
    : ["active_orders", "deletion_in_progress"].includes(result.code ?? "")
    ? 409
    : 400;
  return json({
    code: result.code ?? "invalid_request",
    retry_after: result.retry_after,
  }, status, result.retry_after ? { "Retry-After": String(result.retry_after) } : {});
}
export function createDeletionHandler(deps: DeletionDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return json({ code: "method_not_allowed" }, 405);
    }
    try {
      const authorization = request.headers.get("Authorization");
      if (!authorization?.startsWith("Bearer ")) {
        return json({ code: "authentication_required" }, 401);
      }
      const payload = await limitedJson(request, 1024);
      if (
        // The legacy endpoint accepted DELETE and ignored action/OTP fields.
        // A distinct marker makes a new client fail closed against that server.
        payload.confirmation !== "DELETE_WITH_OTP" ||
        !["request_otp", "confirm_delete"].includes(String(payload.action))
      ) {
        return json({ code: "confirmation_required" }, 400);
      }
      // Identity/email always come from validated Auth, never the request body.
      const user = await deps.getUser(authorization);
      if (!user) return json({ code: "invalid_session" }, 401);
      if (!user.email || !user.email_confirmed_at) {
        return json({ code: "verified_email_required" }, 400);
      }
      if (payload.action === "request_otp") {
        const challenge = await deps.begin(user);
        if (!challenge.ok) return rejected(challenge);
        const id = challenge.challenge_id!;
        try {
          await deps.sendCode(user.email);
          if (!await deps.finishSend(user, id, true)) {
            throw new DeletionFailure("otp_expired", 400);
          }
        } catch (error) {
          await deps.finishSend(user, id, false).catch(() => false);
          throw error;
        }
        const [local, domain] = user.email.split("@");
        return json({
          sent: true,
          challenge_id: id,
          expires_at: challenge.expires_at,
          retry_after: challenge.retry_after,
          email_hint: `${local[0]}***@${domain}`,
        });
      }
      if (
        typeof payload.challenge_id !== "string" ||
        !uuid.test(payload.challenge_id) ||
        typeof payload.otp !== "string" || !/^\d{6,8}$/.test(payload.otp)
      ) {
        return json({ code: "invalid_code" }, 400);
      }
      const claim = await deps.claim(user, payload.challenge_id);
      if (!claim.ok) return rejected(claim);
      const verifiedUser = await deps.verifyCode(user.email, payload.otp);
      if (verifiedUser !== user.id) return json({ code: "invalid_code" }, 400);
      if (!await deps.consume(user, payload.challenge_id)) {
        return json({ code: "otp_expired" }, 400);
      }
      try {
        await deps.deleteUser(user);
      } catch (error) {
        await deps.failChallenge(user, payload.challenge_id).catch(() => {});
        throw error;
      }
      return json({ deleted: true });
    } catch (error) {
      if (error instanceof DeletionFailure) {
        return json(
          { code: error.code, retry_after: error.retryAfter },
          error.status,
          error.retryAfter ? { "Retry-After": String(error.retryAfter) } : {},
        );
      }
      if (error instanceof RangeError) {
        return json({ code: "payload_too_large" }, 413);
      }
      if (error instanceof HttpBodyTimeout) {
        return json({ code: "request_timeout" }, 408);
      }
      if (error instanceof SyntaxError || error instanceof TypeError) {
        return json({ code: "invalid_request" }, 400);
      }
      // Never log codes, addresses, bearer tokens or SDK errors containing them.
      return json({ code: "deletion_unavailable" }, 503);
    }
  };
}
