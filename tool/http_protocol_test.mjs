import assert from 'node:assert/strict';
import { test } from 'node:test';
import { limitedJson, HttpBodyTimeout } from '../supabase/functions/_shared/http.ts';
import { createDeletionHandler } from '../supabase/functions/delete-account/handler.ts';

test('JSON bodies are bounded even without a content-length header', async () => {
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(33)); },
    cancel() { cancelled = true; },
  });
  await assert.rejects(limitedJson(new Request('https://edge.test', { method: 'POST', body, duplex: 'half' }), 32), RangeError);
  assert.equal(cancelled, true);
});
test('stalled and slow-drip bodies have one total deadline and are cancelled', async () => {
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('{')); },
    cancel() { cancelled = true; },
  });
  await assert.rejects(limitedJson(new Request('https://edge.test', { method: 'POST', body, duplex: 'half' }), 32, 15), HttpBodyTimeout);
  assert.equal(cancelled, true);
});
test('malformed, array and scalar JSON payloads are rejected', async () => {
  for (const body of ['{', '[]', 'null', '3']) {
    await assert.rejects(limitedJson(new Request('https://edge.test', { method: 'POST', body })));
  }
  assert.deepEqual(await limitedJson(new Request('https://edge.test', { method: 'POST', body: '{"ok":true}' })), { ok: true });
});
test('deletion rate limits return Retry-After and explicit POST CORS methods', async () => {
  const handler = createDeletionHandler({
    getUser: async () => ({ id: 'test', email: 'test@example.invalid', email_confirmed_at: '2026-10-05' }),
    begin: async () => ({ ok: false, code: 'rate_limited', retry_after: 60 }),
  });
  const response = await handler(new Request('https://edge.test', {
    method: 'POST', headers: { Authorization: 'Bearer test' },
    body: JSON.stringify({ action: 'request_otp', confirmation: 'DELETE_WITH_OTP' }),
  }));
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('Retry-After'), '60');
  const preflight = await handler(new Request('https://edge.test', { method: 'OPTIONS' }));
  assert.equal(preflight.headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS');
});
