package persistence

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
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

func (r *Repository) CreateGroup(ctx context.Context, userID, operationID, name string) (out domain.Group, err error) {
	userIDValue := uuid.MustParse(userID)
	operationIDValue := uuid.MustParse(operationID)
	requestBytes, err := json.Marshal(struct{ Name string }{Name: name})
	if err != nil {
		return domain.Group{}, err
	}
	requestHashBytes := sha256.Sum256(requestBytes)
	requestHash := hex.EncodeToString(requestHashBytes[:])

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Group{}, err
	}
	defer tx.Rollback()

	var status string
	err = tx.QueryRowContext(ctx, `SELECT status FROM app.users WHERE id = $1 FOR UPDATE`, userIDValue).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Group{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.Group{}, err
	}
	if status != "ACTIVE" {
		return domain.Group{}, apperr.ErrForbidden
	}

	var savedHash string
	var savedResponse []byte
	err = tx.QueryRowContext(ctx, `
		SELECT request_hash, response
		FROM app.group_operations
		WHERE user_id = $1 AND operation_id = $2`, userIDValue, operationIDValue).Scan(&savedHash, &savedResponse)
	if err == nil {
		if savedHash != requestHash {
			return domain.Group{}, apperr.ErrConflict
		}
		if err = json.Unmarshal(savedResponse, &out); err != nil {
			return domain.Group{}, err
		}
		if err = tx.Commit(); err != nil {
			return domain.Group{}, err
		}
		return out, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.Group{}, err
	}

	groupID := uuid.New()
	var joinedAt sql.NullTime
	err = tx.QueryRowContext(ctx, `
		INSERT INTO app.groups (id, name, created_by)
		VALUES ($1, $2, $3)
		RETURNING created_at`, groupID, name, userIDValue).Scan(&out.CreatedAt)
	if err != nil {
		return domain.Group{}, err
	}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO app.group_memberships (id, group_id, user_id, status, joined_at)
		VALUES ($1, $2, $3, 'ACTIVE', now())
		RETURNING joined_at`, uuid.New(), groupID, userIDValue).Scan(&joinedAt)
	if err != nil {
		return domain.Group{}, err
	}
	out.ID = groupID.String()
	out.Name = name
	out.CreatedAt = out.CreatedAt.UTC()
	out.Members = []domain.Member{{IsCurrentUser: true, JoinedAt: joinedAt.Time.UTC()}}
	response, err := json.Marshal(out)
	if err != nil {
		return domain.Group{}, err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO app.group_operations (user_id, operation_id, request_hash, response)
		VALUES ($1, $2, $3, $4)`, userIDValue, operationIDValue, requestHash, response)
	if err != nil {
		return domain.Group{}, err
	}
	if err = tx.Commit(); err != nil {
		return domain.Group{}, err
	}
	return out, nil
}
