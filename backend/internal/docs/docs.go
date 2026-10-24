// Package docs serves the OpenAPI spec generated from proto (buf generate) and a Swagger UI for local development.
package docs

import (
	_ "embed"
	"net/http"
)

//go:embed openapi.yaml
var spec []byte

const page = `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>tkb backend API</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
<script>
SwaggerUIBundle({ url: "/docs/openapi.yaml", dom_id: "#swagger-ui", persistAuthorization: true });
</script>
</body>
</html>
`

// Register adds GET /docs (Swagger UI) and GET /docs/openapi.yaml to mux.
func Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /docs", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(page))
	})
	mux.HandleFunc("GET /docs/openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		_, _ = w.Write(spec)
	})
}
