package persistence

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/group/domain"
)

type Repository struct{ db *sql.DB }

func New(db *sql.DB) *Repository { return &Repository{db: db} }

func (r *Repository) ListGroups(ctx context.Context, userID string) ([]domain.Group, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT g.id, g.name, g.created_at, m.user_id = $1 AS is_current_user, u.display_name, u.avatar_id, m.joined_at
		FROM app.groups AS g
		JOIN app.group_memberships AS mine
		  ON mine.group_id = g.id AND mine.user_id = $1 AND mine.status = 'ACTIVE'
		JOIN app.group_memberships AS m
		  ON m.group_id = g.id AND m.status = 'ACTIVE'
		JOIN app.users AS u ON u.id = m.user_id
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
		if err := rows.Scan(&id, &group.Name, &group.CreatedAt, &member.IsCurrentUser, &member.DisplayName, &member.AvatarID, &member.JoinedAt); err != nil {
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

func (r *Repository) ListWorkStarts(ctx context.Context, userID string, after time.Time, afterID string, limit int) ([]domain.WorkStart, error) {
	var cursorID uuid.UUID
	if afterID != "" {
		cursorID = uuid.MustParse(afterID)
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT e.session_id, e.started_at
		FROM app.group_work_start_events AS e
		WHERE (e.started_at, e.session_id) > ($2, $3)
		  AND EXISTS (
		    SELECT 1
		    FROM app.group_memberships AS recipient
		    JOIN app.group_memberships AS sender
		      ON sender.group_id = recipient.group_id
		    WHERE recipient.user_id = $1
		      AND recipient.user_id <> e.user_id
		      AND recipient.status = 'ACTIVE'
		      AND recipient.joined_at <= e.started_at
		      AND sender.user_id = e.user_id
		      AND sender.joined_at <= e.started_at
		      AND (sender.left_at IS NULL OR sender.left_at > e.started_at)
		  )
		ORDER BY e.started_at, e.session_id
		LIMIT $4`, uuid.MustParse(userID), after, cursorID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]domain.WorkStart, 0, limit)
	for rows.Next() {
		var event domain.WorkStart
		var id uuid.UUID
		if err := rows.Scan(&id, &event.StartedAt); err != nil {
			return nil, err
		}
		event.ID = id.String()
		event.StartedAt = event.StartedAt.UTC()
		out = append(out, event)
	}
	return out, rows.Err()
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
	var displayName string
	err = tx.QueryRowContext(ctx, `SELECT status, display_name FROM app.users WHERE id = $1 FOR UPDATE`, userIDValue).Scan(&status, &displayName)
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
		WHERE user_id = $1 AND kind = 'create' AND operation_id = $2`, userIDValue, operationIDValue).Scan(&savedHash, &savedResponse)
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
	out.Members = []domain.Member{{IsCurrentUser: true, DisplayName: displayName, JoinedAt: joinedAt.Time.UTC()}}
	response, err := json.Marshal(out)
	if err != nil {
		return domain.Group{}, err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO app.group_operations (user_id, kind, operation_id, request_hash, response)
		VALUES ($1, 'create', $2, $3, $4)`, userIDValue, operationIDValue, requestHash, string(response))
	if err != nil {
		return domain.Group{}, err
	}
	if err = tx.Commit(); err != nil {
		return domain.Group{}, err
	}
	return out, nil
}

func (r *Repository) CreateInvitation(ctx context.Context, userID, operationID, groupID string) (out domain.Invitation, err error) {
	userIDValue, operationIDValue, groupIDValue := uuid.MustParse(userID), uuid.MustParse(operationID), uuid.MustParse(groupID)
	requestHash := hashRequest(struct{ GroupID string }{GroupID: groupID})
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Invitation{}, err
	}
	defer tx.Rollback()
	if err = lockActiveUser(ctx, tx, userIDValue); err != nil {
		return domain.Invitation{}, err
	}
	if replayed, replayErr := replayOperation(ctx, tx, userIDValue, "create_invitation", operationIDValue, requestHash, &out); replayErr != nil {
		return domain.Invitation{}, replayErr
	} else if replayed {
		if err = tx.Commit(); err != nil {
			return domain.Invitation{}, err
		}
		return out, nil
	}

	var memberGroupID uuid.UUID
	err = tx.QueryRowContext(ctx, `
		SELECT g.id
		FROM app.groups AS g
		JOIN app.group_memberships AS m
		  ON m.group_id = g.id AND m.user_id = $2 AND m.status = 'ACTIVE'
		WHERE g.id = $1
		FOR UPDATE OF g`, groupIDValue, userIDValue).Scan(&memberGroupID)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Invitation{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.Invitation{}, err
	}

	rawToken := make([]byte, 32)
	if _, err = rand.Read(rawToken); err != nil {
		return domain.Invitation{}, err
	}
	out.Token = base64.RawURLEncoding.EncodeToString(rawToken)
	out.ID = uuid.NewString()
	var expiresAt sql.NullTime
	err = tx.QueryRowContext(ctx, `
		INSERT INTO app.group_invitations (id, group_id, invited_by, token_hash, status, expires_at)
		VALUES ($1, $2, $3, $4, 'PENDING', now() + interval '7 days')
		RETURNING expires_at`, uuid.MustParse(out.ID), groupIDValue, userIDValue, hashToken(out.Token)).Scan(&expiresAt)
	if err != nil {
		return domain.Invitation{}, err
	}
	out.ExpiresAt = expiresAt.Time.UTC()
	if err = saveOperation(ctx, tx, userIDValue, "create_invitation", operationIDValue, requestHash, out); err != nil {
		return domain.Invitation{}, err
	}
	if err = tx.Commit(); err != nil {
		return domain.Invitation{}, err
	}
	return out, nil
}

func (r *Repository) AcceptInvitation(ctx context.Context, userID, operationID, token string) (out domain.Group, err error) {
	userIDValue, operationIDValue := uuid.MustParse(userID), uuid.MustParse(operationID)
	tokenHash := hashToken(token)
	requestHash := hashRequest(struct{ TokenHash string }{TokenHash: tokenHash})
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Group{}, err
	}
	defer tx.Rollback()
	if err = lockActiveUser(ctx, tx, userIDValue); err != nil {
		return domain.Group{}, err
	}
	if replayed, replayErr := replayOperation(ctx, tx, userIDValue, "accept_invitation", operationIDValue, requestHash, &out); replayErr != nil {
		return domain.Group{}, replayErr
	} else if replayed {
		if err = tx.Commit(); err != nil {
			return domain.Group{}, err
		}
		return out, nil
	}

	var invitationID, groupID uuid.UUID
	err = tx.QueryRowContext(ctx, `
		SELECT id, group_id FROM app.group_invitations WHERE token_hash = $1`, tokenHash).Scan(&invitationID, &groupID)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Group{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.Group{}, err
	}
	var lockedGroupID uuid.UUID
	err = tx.QueryRowContext(ctx, `SELECT id FROM app.groups WHERE id = $1 FOR UPDATE`, groupID).Scan(&lockedGroupID)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Group{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.Group{}, err
	}

	var status string
	var isUnexpired bool
	err = tx.QueryRowContext(ctx, `
		SELECT status, expires_at > now()
		FROM app.group_invitations WHERE id = $1 FOR UPDATE`, invitationID).Scan(&status, &isUnexpired)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Group{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.Group{}, err
	}
	if status != "PENDING" {
		return domain.Group{}, apperr.ErrPrecondition
	}
	if !isUnexpired {
		if _, err = tx.ExecContext(ctx, `UPDATE app.group_invitations SET status = 'EXPIRED' WHERE id = $1`, invitationID); err != nil {
			return domain.Group{}, err
		}
		if err = tx.Commit(); err != nil {
			return domain.Group{}, err
		}
		return domain.Group{}, apperr.ErrPrecondition
	}

	var alreadyActive bool
	err = tx.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM app.group_memberships
			WHERE group_id = $1 AND user_id = $2 AND status = 'ACTIVE'
		)`, groupID, userIDValue).Scan(&alreadyActive)
	if err != nil {
		return domain.Group{}, err
	}
	if !alreadyActive {
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO app.group_memberships (id, group_id, user_id, status, joined_at)
			VALUES ($1, $2, $3, 'ACTIVE', now())`, uuid.New(), groupID, userIDValue); err != nil {
			return domain.Group{}, err
		}
	}
	_, err = tx.ExecContext(ctx, `
		UPDATE app.group_invitations
		SET status = 'ACCEPTED', accepted_by = $2, accepted_at = now()
		WHERE id = $1`, invitationID, userIDValue)
	if err != nil {
		return domain.Group{}, err
	}
	out, err = groupSnapshot(ctx, tx, groupID, userIDValue)
	if err != nil {
		return domain.Group{}, err
	}
	if err = saveOperation(ctx, tx, userIDValue, "accept_invitation", operationIDValue, requestHash, out); err != nil {
		return domain.Group{}, err
	}
	if err = tx.Commit(); err != nil {
		return domain.Group{}, err
	}
	return out, nil
}

func (r *Repository) LeaveGroup(ctx context.Context, userID, operationID, groupID string) (out domain.LeaveResult, err error) {
	userIDValue, operationIDValue, groupIDValue := uuid.MustParse(userID), uuid.MustParse(operationID), uuid.MustParse(groupID)
	requestHash := hashRequest(struct{ GroupID string }{GroupID: groupID})
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.LeaveResult{}, err
	}
	defer tx.Rollback()
	if err = lockActiveUser(ctx, tx, userIDValue); err != nil {
		return domain.LeaveResult{}, err
	}
	if replayed, replayErr := replayOperation(ctx, tx, userIDValue, "leave_group", operationIDValue, requestHash, &out); replayErr != nil {
		return domain.LeaveResult{}, replayErr
	} else if replayed {
		if err = tx.Commit(); err != nil {
			return domain.LeaveResult{}, err
		}
		return out, nil
	}

	var lockedGroupID uuid.UUID
	err = tx.QueryRowContext(ctx, `
		SELECT g.id FROM app.groups AS g
		JOIN app.group_memberships AS m
		  ON m.group_id = g.id AND m.user_id = $2 AND m.status = 'ACTIVE'
		WHERE g.id = $1
		FOR UPDATE OF g`, groupIDValue, userIDValue).Scan(&lockedGroupID)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.LeaveResult{}, apperr.ErrNotFound
	}
	if err != nil {
		return domain.LeaveResult{}, err
	}
	_, err = tx.ExecContext(ctx, `
		UPDATE app.group_memberships SET status = 'LEFT', left_at = now()
		WHERE group_id = $1 AND user_id = $2 AND status = 'ACTIVE'`, groupIDValue, userIDValue)
	if err != nil {
		return domain.LeaveResult{}, err
	}
	var activeMembers int
	err = tx.QueryRowContext(ctx, `
		SELECT count(*) FROM app.group_memberships
		WHERE group_id = $1 AND status = 'ACTIVE'`, groupIDValue).Scan(&activeMembers)
	if err != nil {
		return domain.LeaveResult{}, err
	}
	if activeMembers == 0 {
		if _, err = tx.ExecContext(ctx, `DELETE FROM app.groups WHERE id = $1`, groupIDValue); err != nil {
			return domain.LeaveResult{}, err
		}
		out.GroupDeleted = true
	}
	if err = saveOperation(ctx, tx, userIDValue, "leave_group", operationIDValue, requestHash, out); err != nil {
		return domain.LeaveResult{}, err
	}
	if err = tx.Commit(); err != nil {
		return domain.LeaveResult{}, err
	}
	return out, nil
}

func groupSnapshot(ctx context.Context, tx *sql.Tx, groupID, currentUserID uuid.UUID) (domain.Group, error) {
	rows, err := tx.QueryContext(ctx, `
		SELECT g.id, g.name, g.created_at, m.user_id = $2 AS is_current_user, u.display_name, u.avatar_id, m.joined_at
		FROM app.groups AS g
		JOIN app.group_memberships AS m
		  ON m.group_id = g.id AND m.status = 'ACTIVE'
		JOIN app.users AS u ON u.id = m.user_id
		WHERE g.id = $1
		ORDER BY m.joined_at, m.id`, groupID, currentUserID)
	if err != nil {
		return domain.Group{}, err
	}
	defer rows.Close()
	var out domain.Group
	for rows.Next() {
		var id uuid.UUID
		var member domain.Member
		if err = rows.Scan(&id, &out.Name, &out.CreatedAt, &member.IsCurrentUser, &member.DisplayName, &member.AvatarID, &member.JoinedAt); err != nil {
			return domain.Group{}, err
		}
		out.ID = id.String()
		out.CreatedAt = out.CreatedAt.UTC()
		member.JoinedAt = member.JoinedAt.UTC()
		out.Members = append(out.Members, member)
	}
	if err = rows.Err(); err != nil {
		return domain.Group{}, err
	}
	if out.ID == "" {
		return domain.Group{}, apperr.ErrNotFound
	}
	return out, nil
}

func lockActiveUser(ctx context.Context, tx *sql.Tx, userID uuid.UUID) error {
	var status string
	err := tx.QueryRowContext(ctx, `SELECT status FROM app.users WHERE id = $1 FOR UPDATE`, userID).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) {
		return apperr.ErrNotFound
	}
	if err != nil {
		return err
	}
	if status != "ACTIVE" {
		return apperr.ErrForbidden
	}
	return nil
}

func replayOperation(ctx context.Context, tx *sql.Tx, userID uuid.UUID, kind string, operationID uuid.UUID, requestHash string, out any) (bool, error) {
	var savedHash string
	var response []byte
	err := tx.QueryRowContext(ctx, `
		SELECT request_hash, response FROM app.group_operations
		WHERE user_id = $1 AND kind = $2 AND operation_id = $3`, userID, kind, operationID).Scan(&savedHash, &response)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if savedHash != requestHash {
		return false, apperr.ErrConflict
	}
	if err = json.Unmarshal(response, out); err != nil {
		return false, err
	}
	return true, nil
}

func saveOperation(ctx context.Context, tx *sql.Tx, userID uuid.UUID, kind string, operationID uuid.UUID, requestHash string, responseValue any) error {
	response, err := json.Marshal(responseValue)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO app.group_operations (user_id, kind, operation_id, request_hash, response)
		VALUES ($1, $2, $3, $4, $5)`, userID, kind, operationID, requestHash, string(response))
	return err
}

func hashRequest(value any) string {
	data, _ := json.Marshal(value)
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}
