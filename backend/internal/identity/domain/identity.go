package domain

import "time"

type User struct {
	ID          string
	Status      string
	DisplayName string
	AvatarID    string
	CreatedAt   time.Time
}

func ValidAvatarID(id string) bool {
	switch id {
	case "dragon", "puppy", "cat", "hedgehog", "rabbit", "chick", "bird", "penguin_blue", "penguin_pink", "slime":
		return true
	default:
		return false
	}
}

type Device struct {
	ID        string
	Platform  string
	Name      string
	Status    string
	Version   int64
	CreatedAt time.Time
}
