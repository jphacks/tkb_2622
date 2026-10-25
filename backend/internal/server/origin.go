package server

import (
	"crypto/subtle"
	"net/http"
)

// OriginAuthHeader carries the shared secret that the Cloudflare Worker adds when proxying.
const OriginAuthHeader = "X-Origin-Auth"

// RequireOriginToken rejects requests that did not pass through the Cloudflare Worker,
// such as direct access to the public Cloud Run URL. The header is removed before next runs.
func RequireOriginToken(token string, next http.Handler) http.Handler {
	expected := []byte(token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get(OriginAuthHeader)), expected) != 1 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"code":"permission_denied","message":"direct access is not allowed"}`))
			return
		}
		r.Header.Del(OriginAuthHeader)
		next.ServeHTTP(w, r)
	})
}
