// Package auth verifies Supabase access tokens against a fixed JWKS endpoint.
package auth

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
)

type Config struct {
	Issuer, Audience string
	AllowLocalHTTP   bool
}
type key struct {
	public any
	alg    string
}
type Verifier struct {
	issuer, audience, jwks string
	client                 *http.Client
	mu                     sync.Mutex
	keys                   map[string]key
	expires, lastAttempt   time.Time
}
type claims struct {
	jwt.RegisteredClaims
	Role      string `json:"role"`
	SessionID string `json:"session_id"`
	Anonymous bool   `json:"is_anonymous"`
}

func New(cfg Config) (*Verifier, error) {
	u, err := url.Parse(cfg.Issuer)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || strings.TrimSuffix(u.Path, "/") != "/auth/v1" {
		return nil, errors.New("invalid Supabase issuer")
	}
	local := u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1" || u.Hostname() == "::1" || u.Hostname() == "host.docker.internal"
	if u.Scheme != "https" && !(cfg.AllowLocalHTTP && local && u.Scheme == "http") {
		return nil, errors.New("Supabase issuer must use HTTPS")
	}
	if cfg.Audience == "" {
		return nil, errors.New("JWT audience is required")
	}
	issuer := strings.TrimRight(cfg.Issuer, "/")
	return &Verifier{issuer: issuer, audience: cfg.Audience, jwks: issuer + "/.well-known/jwks.json", keys: map[string]key{}, client: &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}
func (v *Verifier) Verify(ctx context.Context, authorization string) (application.Principal, error) {
	fail := application.ErrUnauthenticated
	parts := strings.Fields(authorization)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || len(parts[1]) > 16384 {
		return application.Principal{}, fail
	}
	c := &claims{}
	token, err := jwt.ParseWithClaims(parts[1], c, func(t *jwt.Token) (any, error) {
		kid, ok := t.Header["kid"].(string)
		if !ok || kid == "" || len(kid) > 256 {
			return nil, fail
		}
		k, e := v.getKey(ctx, kid)
		if e != nil || k.alg != t.Method.Alg() {
			return nil, fail
		}
		return k.public, nil
	}, jwt.WithValidMethods([]string{"ES256", "RS256"}), jwt.WithIssuer(v.issuer), jwt.WithAudience(v.audience), jwt.WithExpirationRequired(), jwt.WithIssuedAt())
	if err != nil || !token.Valid || c.Role != "authenticated" || c.Anonymous || !application.ValidID(c.Subject) || !application.ValidID(c.SessionID) {
		return application.Principal{}, fail
	}
	return application.Principal{Subject: c.Subject, SessionID: c.SessionID}, nil
}
func (v *Verifier) getKey(ctx context.Context, kid string) (key, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	now := time.Now()
	if k, ok := v.keys[kid]; ok && now.Before(v.expires) {
		return k, nil
	}
	// Bound unknown-kid requests and failures to one fetch per 30 seconds.
	if now.Sub(v.lastAttempt) < 30*time.Second {
		return key{}, application.ErrUnauthenticated
	}
	v.lastAttempt = now
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.jwks, nil)
	if err != nil {
		return key{}, err
	}
	res, err := v.client.Do(req)
	if err != nil {
		return key{}, application.ErrUnauthenticated
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return key{}, application.ErrUnauthenticated
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, 1<<20+1))
	if err != nil || len(data) > 1<<20 {
		return key{}, application.ErrUnauthenticated
	}
	var set struct {
		Keys []struct{ Kty, Kid, Alg, Use, Crv, X, Y, N, E string }
	}
	if json.Unmarshal(data, &set) != nil || len(set.Keys) > 100 {
		return key{}, application.ErrUnauthenticated
	}
	keys := map[string]key{}
	for _, j := range set.Keys {
		if j.Kid == "" || (j.Use != "" && j.Use != "sig") {
			continue
		}
		if _, duplicate := keys[j.Kid]; duplicate {
			return key{}, application.ErrUnauthenticated
		}
		switch {
		case j.Kty == "EC" && j.Crv == "P-256" && (j.Alg == "" || j.Alg == "ES256"):
			x, ex := base64.RawURLEncoding.DecodeString(j.X)
			y, ey := base64.RawURLEncoding.DecodeString(j.Y)
			if ex != nil || ey != nil || len(x) != 32 || len(y) != 32 {
				continue
			}
			pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(x), Y: new(big.Int).SetBytes(y)}
			if !pub.Curve.IsOnCurve(pub.X, pub.Y) {
				continue
			}
			keys[j.Kid] = key{public: pub, alg: "ES256"}
		case j.Kty == "RSA" && (j.Alg == "" || j.Alg == "RS256"):
			n, en := base64.RawURLEncoding.DecodeString(j.N)
			e, ee := base64.RawURLEncoding.DecodeString(j.E)
			if en != nil || ee != nil || len(n) < 256 || len(n) > 1024 || len(e) == 0 || len(e) > 4 {
				continue
			}
			exponent := new(big.Int).SetBytes(e).Int64()
			if exponent < 3 || exponent > 2147483647 || exponent%2 == 0 {
				continue
			}
			keys[j.Kid] = key{public: &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(exponent)}, alg: "RS256"}
		}
	}
	if len(keys) == 0 {
		return key{}, application.ErrUnauthenticated
	}
	v.keys = keys
	v.expires = now.Add(5 * time.Minute)
	if k, ok := keys[kid]; ok {
		return k, nil
	}
	return key{}, application.ErrUnauthenticated
}
