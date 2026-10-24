package domain

import "time"

type Member struct {
	IsCurrentUser bool
	JoinedAt      time.Time
}

type Group struct {
	ID        string
	Name      string
	CreatedAt time.Time
	Members   []Member
}
