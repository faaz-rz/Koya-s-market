// No network: exercise the actual Edge HTTP handler with injected services.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createDeletionHandler, DeletionFailure } from '../supabase/functions/delete-account/handler.ts';

const challenge = '12345678-1234-4123-8123-123456789012';
const user = { id: 'customer', email: 'alice@example.test', email_confirmed_at: '2026-09-23T00:00:00Z' };
function fixture(overrides = {}) {
  const calls = [];
  const record = (name, value) => async (...args) => { calls.push([name, ...args]); return value; };
  const deps = {
    getUser: record('getUser', user),
    begin: record('begin', { ok: true, challenge_id: challenge, expires_at: '2026-09-23T12:10:00Z', retry_after: 60 }),
    sendCode: record('sendCode'), finishSend: record('finishSend', true),
    claim: record('claim', { ok: true }), verifyCode: record('verifyCode', user.id),
    consume: record('consume', true), deleteUser: record('deleteUser'), failChallenge: record('failChallenge'),
    ...overrides,
  };
  return { calls, handler: createDeletionHandler(deps) };
}
async function post(handler, payload, authorization = 'Bearer session') {
  const response = await handler(new Request('https://edge.test/delete-account', {
    method: 'POST', headers: authorization ? { Authorization: authorization } : {}, body: JSON.stringify(payload),
  }));
  return { status: response.status, body: await response.json() };
}
const request = { action: 'request_otp', confirmation: 'DELETE_WITH_OTP' };
const confirm = { action: 'confirm_delete', confirmation: 'DELETE_WITH_OTP', challenge_id: challenge, otp: '123456' };

test('unauthenticated, expired-session and unverified-email requests never send or delete', async () => {
  for (const [override, token, expected] of [ [{}, null, 401], [{ getUser: async () => null }, 'Bearer invalid', 401],
    [{ getUser: async () => ({ ...user, email_confirmed_at: null }) }, 'Bearer valid', 400] ]) {
    const { handler, calls } = fixture(override);
    assert.equal((await post(handler, request, token)).status, expected);
    assert.ok(!calls.some(([name]) => ['begin','sendCode','deleteUser'].includes(name)));
  }
});
test('old one-step deletion, bad confirmation and malformed codes are rejected', async () => {
  for (const payload of [{ confirmation: 'DELETE' }, { ...request, confirmation: 'DELETE' },
    { ...confirm, confirmation: 'DELETE' }, { ...confirm, confirmation: 'YES' },
    { ...confirm, otp: '123' }, { ...confirm, otp: '12345x' }, { ...confirm, challenge_id: 'forged' }]) {
    const { handler, calls } = fixture();
    assert.equal((await post(handler, payload)).status, 400);
    assert.ok(!calls.some(([name]) => ['verifyCode','deleteUser'].includes(name)));
  }
});
test('code request uses validated identity, masks email and never deletes', async () => {
  const { handler, calls } = fixture();
  const result = await post(handler, { ...request, email: 'attacker@test.invalid', user_id: 'attacker' });
  assert.deepEqual(result, { status: 200, body: { sent: true, challenge_id: challenge,
    expires_at: '2026-09-23T12:10:00Z', retry_after: 60, email_hint: 'a***@example.test' } });
  assert.deepEqual(calls.find(([name]) => name === 'sendCode'), ['sendCode', user.email]);
  assert.ok(!calls.some(([name]) => name === 'deleteUser'));
});
test('staff, active orders and send throttles fail closed before email', async () => {
  for (const [code, status] of [['staff_account',403],['active_orders',409],['rate_limited',429]]) {
    const { handler, calls } = fixture({ begin: async () => ({ ok: false, code, retry_after: 60 }) });
    assert.equal((await post(handler, request)).status, status);
    assert.ok(!calls.some(([name]) => ['sendCode','deleteUser'].includes(name)));
  }
});
test('email failures mark the challenge failed and expose no SDK details', async () => {
  const { handler, calls } = fixture({ sendCode: async () => { throw new Error('secret@example.test token=123456'); } });
  assert.deepEqual(await post(handler, request), { status: 503, body: { code: 'deletion_unavailable' } });
  assert.deepEqual(calls.at(-1), ['finishSend', user, challenge, false]);
});
test('expired and exhausted challenges never reach Auth verification', async () => {
  for (const code of ['otp_expired', 'attempts_exhausted']) {
    const { handler, calls } = fixture({ claim: async () => ({ ok: false, code }) });
    assert.equal((await post(handler, confirm)).body.code, code);
    assert.ok(!calls.some(([name]) => ['verifyCode','consume','deleteUser'].includes(name)));
  }
});
test('wrong code or another verified identity never consumes or deletes', async () => {
  for (const identity of [null, 'another-user']) {
    const { handler, calls } = fixture({ verifyCode: async () => identity });
    assert.equal((await post(handler, confirm)).body.code, 'invalid_code');
    assert.ok(!calls.some(([name]) => ['consume','deleteUser'].includes(name)));
  }
});
test('verified proof is consumed before deletion; replay fails closed', async () => {
  const { handler, calls } = fixture();
  assert.deepEqual(await post(handler, confirm), { status: 200, body: { deleted: true } });
  assert.deepEqual(calls.map(([name]) => name), ['getUser','claim','verifyCode','consume','deleteUser']);
  const replay = fixture({ consume: async () => false });
  assert.equal((await post(replay.handler, confirm)).body.code, 'otp_expired');
  assert.ok(!replay.calls.some(([name]) => name === 'deleteUser'));
});
test('concurrent confirmations can authorize deletion only once', async () => {
  let consumed = false, deletions = 0;
  const { handler } = fixture({ consume: async () => { if (consumed) return false; consumed = true; return true; },
    deleteUser: async () => { deletions++; } });
  const results = await Promise.all(Array.from({ length: 12 }, () => post(handler, confirm)));
  assert.equal(deletions, 1); assert.equal(results.filter(r => r.body.deleted).length, 1);
});
test('a deletion failure invalidates the consumed proof and returns an actionable error', async () => {
  const { handler, calls } = fixture({ deleteUser: async () => { throw new DeletionFailure('active_orders',409); } });
  assert.deepEqual(await post(handler, confirm), { status: 409, body: { code: 'active_orders' } });
  assert.deepEqual(calls.at(-1), ['failChallenge', user, challenge]);
});
test('body limit, invalid JSON and HTTP methods are enforced', async () => {
  const { handler, calls } = fixture();
  assert.equal((await post(handler, { ...request, padding: 'x'.repeat(2048) })).status, 413);
  assert.equal((await handler(new Request('https://edge.test', { method: 'GET' }))).status, 405);
  assert.equal((await handler(new Request('https://edge.test', { method: 'OPTIONS' }))).status, 200);
  assert.equal((await handler(new Request('https://edge.test', { method: 'POST', headers: { Authorization: 'Bearer x' }, body: '{' }))).status, 400);
  assert.equal(calls.length, 0);
});
