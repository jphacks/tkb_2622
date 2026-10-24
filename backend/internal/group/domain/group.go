package domain

import "time"

type Member struct {
	IsCurrentUser bool
	DisplayName   string
	JoinedAt      time.Time
}

type Group struct {
	ID        string
	Name      string
	CreatedAt time.Time
	Members   []Member
}

type Invitation struct {
	ID        string
	Token     string
	ExpiresAt time.Time
}

type LeaveResult struct {
	GroupDeleted bool
}
