package migrations

import (
	"embed"
	"io/fs"
)

// PostgreSQL has a separate migration history. Legacy SQLite files are retained
// for existing databases and are never executed against PostgreSQL.
//
//go:embed postgres/*.sql
var embedded embed.FS

var Files fs.FS = postgresFiles()

func postgresFiles() fs.FS {
	f, err := fs.Sub(embedded, "postgres")
	if err != nil {
		panic(err)
	}
	return f
}
