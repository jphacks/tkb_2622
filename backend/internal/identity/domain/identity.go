package domain

import "time"

type User struct {
	ID          string
	Status      string
	DisplayName string
	CreatedAt   time.Time
}

type Device struct {
	ID        string
	Platform  string
	Name      string
	Status    string
	Version   int64
	CreatedAt time.Time
}
