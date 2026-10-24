// API ホスト名へのリクエストを Cloud Run（ORIGIN_URL）へそのまま転送する．
// WAF などのゾーン設定は Worker の実行前に適用される．
export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);
    const target = new URL(incoming.pathname + incoming.search, env.ORIGIN_URL);

    const headers = new Headers(request.headers);
    headers.set("X-Forwarded-Host", incoming.host);
    headers.set("X-Forwarded-Proto", incoming.protocol.replace(":", ""));
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
