package persistence

import (
	"context"
	"database/sql"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/group/domain"
)

type Repository struct{ db *sql.DB }

func New(db *sql.DB) *Repository { return &Repository{db: db} }

func (r *Repository) ListGroups(ctx context.Context, userID string) ([]domain.Group, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT g.id, g.name, g.created_at, m.user_id = $1 AS is_current_user, m.joined_at
		FROM app.groups AS g
		JOIN app.group_memberships AS mine
		  ON mine.group_id = g.id AND mine.user_id = $1 AND mine.status = 'ACTIVE'
		JOIN app.group_memberships AS m
		  ON m.group_id = g.id AND m.status = 'ACTIVE'
		ORDER BY g.created_at DESC, g.id, m.joined_at, m.id`, uuid.MustParse(userID))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	groups := make([]domain.Group, 0)
	var currentID uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		var group domain.Group
		var member domain.Member
		if err := rows.Scan(&id, &group.Name, &group.CreatedAt, &member.IsCurrentUser, &member.JoinedAt); err != nil {
			return nil, err
		}
		if len(groups) == 0 || id != currentID {
			currentID = id
			group.ID = id.String()
			group.CreatedAt = group.CreatedAt.UTC()
			group.Members = make([]domain.Member, 0, 4)
			groups = append(groups, group)
		}
		last := &groups[len(groups)-1]
		member.JoinedAt = member.JoinedAt.UTC()
		last.Members = append(last.Members, member)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return groups, nil
}
