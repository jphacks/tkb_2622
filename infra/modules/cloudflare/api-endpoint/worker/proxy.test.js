// proxy.js のユニットテスト．実行: node --test infra/modules/cloudflare/api-endpoint/worker/
import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";

import worker from "./proxy.js";

const BASE = "https://tkb-dev-api-proxy.example.workers.dev";
const TOKEN = "a".repeat(48);
const RPC = `${BASE}/identity.v1.IdentityService/GetMe`;

let forwarded;
let allowRate;
let env;
const originalFetch = globalThis.fetch;
const originalLog = console.log;

beforeEach(() => {
  forwarded = null;
  allowRate = true;
  env = {
    ORIGIN_URL: "https://tkb-dev-api-xxxx.a.run.app",
    ORIGIN_AUTH_TOKEN: TOKEN,
    RATE_LIMIT_PERIOD: "60",
    RATE_LIMITER: { limit: async () => ({ success: allowRate }) },
  };
  globalThis.fetch = async (url, init) => {
    forwarded = { url: String(url), init };
    return new Response("{}", { status: 200 });
  };
  console.log = () => {};
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  console.log = originalLog;
});

function rpc(overrides = {}) {
  const body = overrides.body ?? "{}";
  return new Request(overrides.url ?? RPC, {
    method: overrides.method ?? "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": String(body.length),
      Authorization: "Bearer header.payload.signature",
      "CF-Connecting-IP": "203.0.113.1",
      ...overrides.headers,
    },
    body,
  });
}

async function errorCode(response) {
  return (await response.json()).code;
}

test("正しい RPC は共有シークレットを付けて Cloud Run へ転送する", async () => {
  const response = await worker.fetch(rpc({ headers: { "X-Origin-Auth": "forged" } }), env);
  assert.equal(response.status, 200);
  assert.equal(forwarded.url, "https://tkb-dev-api-xxxx.a.run.app/identity.v1.IdentityService/GetMe");
  const headers = forwarded.init.headers;
  assert.equal(headers.get("X-Origin-Auth"), TOKEN, "クライアントが送った値は上書きする");
  assert.equal(headers.get("X-Forwarded-For"), "203.0.113.1");
  assert.equal(headers.get("X-Forwarded-Host"), "tkb-dev-api-proxy.example.workers.dev");
  assert.equal(forwarded.init.redirect, "manual");
});

test("GET /healthz は認証なしで Cloud Run の /health へ転送する（Cloud Run は末尾 z のパスを予約しているため）", async () => {
  const response = await worker.fetch(new Request(`${BASE}/healthz`), env);
  assert.equal(response.status, 200);
  assert.equal(forwarded.url, "https://tkb-dev-api-xxxx.a.run.app/health");
  assert.equal(forwarded.init.headers.get("X-Origin-Auth"), TOKEN);
});

test("GET /health もそのまま転送する", async () => {
  const response = await worker.fetch(new Request(`${BASE}/health`), env);
  assert.equal(response.status, 200);
  assert.equal(forwarded.url, "https://tkb-dev-api-xxxx.a.run.app/health");
});

test("GET /v1/group/work-starts は Bearer があればクエリ付きで転送する", async () => {
  const request = new Request(`${BASE}/v1/group/work-starts?page_size=20`, {
    headers: { Authorization: "Bearer t" },
  });
  const response = await worker.fetch(request, env);
  assert.equal(response.status, 200);
  assert.equal(forwarded.url, "https://tkb-dev-api-xxxx.a.run.app/v1/group/work-starts?page_size=20");
});

test("許可リストにないパス・メソッドは 404", async () => {
  const cases = [
    new Request(`${BASE}/docs`),
    new Request(`${BASE}/`),
    new Request(`${BASE}/grpc.health.v1.Health/Check`, { method: "POST" }),
    new Request(`${BASE}/admin.v1.AdminService/Delete`, { method: "POST" }),
    new Request(`${BASE}/identity.v1.IdentityService/GetMe`),
    new Request(`${BASE}/healthz`, { method: "POST" }),
    new Request(`${BASE}/identity.v1.IdentityService/../../etc/passwd`, { method: "POST" }),
  ];
  for (const request of cases) {
    const response = await worker.fetch(request, env);
    assert.equal(response.status, 404, `${request.method} ${request.url}`);
    assert.equal(await errorCode(response), "not_found");
  }
  assert.equal(forwarded, null);
});

test("Bearer がない・形式が不正・長すぎる場合は 401", async () => {
  const cases = [
    { Authorization: "" },
    { Authorization: "Basic dXNlcjpwYXNz" },
    { Authorization: "Bearer <script>" },
    { Authorization: `Bearer ${"a".repeat(16 * 1024)}` },
  ];
  for (const headers of cases) {
    const response = await worker.fetch(rpc({ headers }), env);
    assert.equal(response.status, 401, headers.Authorization.slice(0, 20));
    assert.equal(await errorCode(response), "unauthenticated");
  }
  assert.equal(forwarded, null);
});

test("Content-Type が JSON でなければ 415", async () => {
  const response = await worker.fetch(rpc({ headers: { "Content-Type": "application/proto" } }), env);
  assert.equal(response.status, 415);
  assert.equal(forwarded, null);
});

test("charset 付きの JSON は許可する", async () => {
  const response = await worker.fetch(rpc({ headers: { "Content-Type": "application/json; charset=utf-8" } }), env);
  assert.equal(response.status, 200);
});

test("Content-Length がなければ 411，1 MiB を超えれば 413", async () => {
  const missing = rpc();
  missing.headers.delete("Content-Length");
  assert.equal((await worker.fetch(missing, env)).status, 411);

  const tooLarge = rpc({ headers: { "Content-Length": String(1024 * 1024 + 1) } });
  const response = await worker.fetch(tooLarge, env);
  assert.equal(response.status, 413);
  assert.equal(await errorCode(response), "resource_exhausted");
  assert.equal(forwarded, null);
});

test("レート制限を超えたら許可リストより先に 429", async () => {
  allowRate = false;
  const response = await worker.fetch(rpc(), env);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.equal(await errorCode(response), "resource_exhausted");
  assert.equal(forwarded, null);
});

test("レート制限のキーは接続元 IP", async () => {
  let key;
  env.RATE_LIMITER = { limit: async (options) => ((key = options.key), { success: true }) };
  await worker.fetch(rpc(), env);
  assert.equal(key, "203.0.113.1");
});

test("共有シークレットが未設定なら転送しない（設定漏れで素通しにしない）", async () => {
  delete env.ORIGIN_AUTH_TOKEN;
  const response = await worker.fetch(rpc(), env);
  assert.equal(response.status, 500);
  assert.equal(forwarded, null);
});
