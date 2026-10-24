package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequireOriginToken(t *testing.T) {
	const token = "0123456789abcdef0123456789abcdef"
	cases := []struct {
		name   string
		header []string
		want   int
	}{
		{name: "missing", want: http.StatusForbidden},
		{name: "empty", header: []string{""}, want: http.StatusForbidden},
		{name: "mismatch", header: []string{"0123456789abcdef0123456789abcdeX"}, want: http.StatusForbidden},
		{name: "prefix", header: []string{token[:16]}, want: http.StatusForbidden},
		{name: "match", header: []string{token}, want: http.StatusOK},
	}
	for _, c := range cases {
		var forwarded http.Header
		h := RequireOriginToken(token, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { forwarded = r.Header.Clone() }))
		req := httptest.NewRequest(http.MethodPost, "/identity.v1.IdentityService/GetMe", nil)
		for _, v := range c.header {
			req.Header.Set(OriginAuthHeader, v)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Fatalf("%s: status = %d, want %d", c.name, rec.Code, c.want)
		}
		if c.want != http.StatusOK {
			if forwarded != nil {
				t.Fatalf("%s: request reached the next handler", c.name)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json" {
				t.Fatalf("%s: content type = %q", c.name, got)
			}
			continue
		}
		if forwarded.Get(OriginAuthHeader) != "" {
			t.Fatalf("%s: %s was forwarded to the next handler", c.name, OriginAuthHeader)
		}
	}
}
