// API の入口．WAF 相当の検査（レート制限・許可リスト）を通ったリクエストだけを Cloud Run（ORIGIN_URL）へ転送する．
// 転送時に X-Origin-Auth を付与し，Cloud Run 側はこれがない直接アクセスを拒否する．
// backend に Connect サービスや HTTP ルートを追加したら CONNECT_SERVICES・ROUTES も更新する．

const CONNECT_SERVICES = ["identity", "focus", "group", "reward", "restriction"];
const CONNECT_PATH = new RegExp(`^/(?:${CONNECT_SERVICES.join("|")})\\.v1\\.[A-Za-z]+Service/[A-Za-z]+$`);

// backend の最大 WithReadMaxBytes（FocusService の 1 MiB）に合わせる
const MAX_BODY_BYTES = 1024 * 1024;
const MAX_AUTHORIZATION_LENGTH = 16 * 1024;
const BEARER = /^Bearer [A-Za-z0-9._~+/=-]+$/;
const ORIGIN_AUTH_HEADER = "X-Origin-Auth";

// 既存クライアント（iOS の ConnectJSONClient，desktop の cloud/client.go）が使う形だけを許可する
const ROUTES = [
  { method: "GET", path: (p) => p === "/healthz" },
  { method: "POST", path: (p) => CONNECT_PATH.test(p), auth: true, jsonBody: true },
  { method: "GET", path: (p) => p === "/v1/group/work-starts", auth: true },
];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (!env.ORIGIN_AUTH_TOKEN) {
      return reject(request, url, 500, "internal", "proxy is not configured");
    }

    // 不正なリクエストも数えるため最初に行う
    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const { success } = await env.RATE_LIMITER.limit({ key: ip });
    if (!success) {
      return reject(request, url, 429, "resource_exhausted", "too many requests", {
        "Retry-After": env.RATE_LIMIT_PERIOD ?? "60",
      });
    }

    const route = ROUTES.find((r) => r.method === request.method && r.path(url.pathname));
    if (!route) {
      return reject(request, url, 404, "not_found", "not found");
    }

    if (route.auth) {
      const authorization = request.headers.get("Authorization") ?? "";
      if (authorization.length > MAX_AUTHORIZATION_LENGTH || !BEARER.test(authorization)) {
        return reject(request, url, 401, "unauthenticated", "missing or malformed bearer token");
      }
    }

    if (route.jsonBody) {
      const contentType = (request.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase();
      if (contentType !== "application/json") {
        return reject(request, url, 415, "invalid_argument", "content type must be application/json");
      }
      const length = request.headers.get("Content-Length");
      if (length === null || !/^[0-9]+$/.test(length)) {
        return reject(request, url, 411, "invalid_argument", "content length is required");
      }
      if (Number(length) > MAX_BODY_BYTES) {
        return reject(request, url, 413, "resource_exhausted", "request body too large");
      }
    }

    const target = new URL(url.pathname + url.search, env.ORIGIN_URL);
    const headers = new Headers(request.headers);
    headers.set(ORIGIN_AUTH_HEADER, env.ORIGIN_AUTH_TOKEN);
    headers.set("X-Forwarded-Host", url.host);
    headers.set("X-Forwarded-Proto", url.protocol.replace(":", ""));
    const clientIP = request.headers.get("CF-Connecting-IP");
    if (clientIP) {
      headers.set("X-Forwarded-For", clientIP);
    }

    return fetch(target, {
      method: request.method,
      headers,
      body: request.body,
      redirect: "manual",
    });
  },
};

// Connect のエラー形式（{"code","message"}）で返す．クライアントは code を読む．
function reject(request, url, status, code, message, extraHeaders = {}) {
  // IP・トークンは記録しない
  console.log(
    JSON.stringify({
      blocked: code,
      status,
      method: request.method,
      path: url.pathname.slice(0, 200),
      ray: request.headers.get("CF-Ray"),
    }),
  );
  return new Response(JSON.stringify({ code, message }), {
    status,
    headers: { "Content-Type": "application/json", ...extraHeaders },
  });
}
