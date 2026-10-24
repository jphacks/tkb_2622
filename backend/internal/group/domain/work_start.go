package domain

import "time"

// WorkStart is intentionally limited to the fact and time of a new work start.
type WorkStart struct {
	ID        string
	StartedAt time.Time
}
