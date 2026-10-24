package persistence

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"

	"github.com/google/uuid"
	q "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/persistence/sqlc"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
	"github.com/jphacks/tkb_2622/backend/internal/identity/domain"
)

type Repository struct{ db *sql.DB }

func New(db *sql.DB) *Repository { return &Repository{db: db} }
func uid(s string) uuid.UUID     { return uuid.MustParse(s) }
func asUser(u q.AppUser) domain.User {
	return domain.User{ID: u.ID.String(), Status: u.Status, CreatedAt: u.CreatedAt}
}
func asDevice(d q.AppDevice) domain.Device {
	return domain.Device{ID: d.ID.String(), Platform: d.Platform, Name: d.Name, Status: d.Status, Version: d.Version, CreatedAt: d.CreatedAt}
}
func hash(v any) string {
	b, _ := json.Marshal(v)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
func translate(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return application.ErrNotFound
	}
	return err
}
func checkSession(ctx context.Context, queries *q.Queries, p application.Principal, userID uuid.UUID) error {
	d, err := queries.SessionDevice(ctx, uid(p.SessionID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if d.UserID != userID || d.Status != "ACTIVE" {
		return application.ErrForbidden
	}
	return nil
}

// All identity mutations serialize on the user row, including their replay record.
func (r *Repository) transaction(ctx context.Context, p application.Principal, ensure bool, fn func(*sql.Tx, *q.Queries, q.AppUser) error) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	queries := q.New(tx)
	var u q.AppUser
	if ensure {
		u, err = queries.EnsureUser(ctx, q.EnsureUserParams{ID: uuid.New(), AuthSubject: uid(p.Subject)})
	} else {
		u, err = queries.GetUser(ctx, uid(p.Subject))
	}
	if err != nil {
		return translate(err)
	}
	u, err = queries.LockUser(ctx, u.ID)
	if err != nil {
		return err
	}
	if u.Status != "ACTIVE" {
		return application.ErrForbidden
	}
	if err = fn(tx, queries, u); err != nil {
		return err
	}
	return tx.Commit()
}
func replay(ctx context.Context, queries *q.Queries, u q.AppUser, kind, op, h string, out any) (bool, error) {
	saved, err := queries.GetOperation(ctx, q.GetOperationParams{UserID: u.ID, Kind: kind, OperationID: uid(op)})
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if saved.RequestHash != h {
		return false, application.ErrConflict
	}
	if err = json.Unmarshal(saved.Response, out); err != nil {
		return false, err
	}
	return true, nil
}
func save(ctx context.Context, queries *q.Queries, u q.AppUser, kind, op, h string, out any) error {
	b, err := json.Marshal(out)
	if err != nil {
		return err
	}
	return queries.SaveOperation(ctx, q.SaveOperationParams{UserID: u.ID, Kind: kind, OperationID: uid(op), RequestHash: h, Response: b})
}
func (r *Repository) EnsureUser(ctx context.Context, p application.Principal, op string) (out domain.User, err error) {
	err = r.transaction(ctx, p, true, func(_ *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		h := hash(p.Subject)
		ok, e := replay(ctx, queries, u, "ensure", op, h, &out)
		if e != nil || ok {
			return e
		}
		out = asUser(u)
		return save(ctx, queries, u, "ensure", op, h, out)
	})
	if err == nil {
		err = r.loadProfile(ctx, &out)
	}
	return
}
func (r *Repository) GetMe(ctx context.Context, p application.Principal) (out domain.User, err error) {
	err = r.transaction(ctx, p, false, func(_ *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		out = asUser(u)
		return nil
	})
	if err == nil {
		err = r.loadProfile(ctx, &out)
	}
	return
}
func (r *Repository) UpdateDisplayName(ctx context.Context, p application.Principal, displayName string) (out domain.User, err error) {
	err = r.transaction(ctx, p, false, func(tx *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		_, e := tx.ExecContext(ctx, `UPDATE app.users SET display_name = $1 WHERE id = $2`, displayName, u.ID)
		return e
	})
	if err != nil {
		return domain.User{}, err
	}
	return r.GetMe(ctx, p)
}
func (r *Repository) UpdateAvatar(ctx context.Context, p application.Principal, avatarID string) (out domain.User, err error) {
	err = r.transaction(ctx, p, false, func(tx *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		_, e := tx.ExecContext(ctx, `UPDATE app.users SET avatar_id = $1 WHERE id = $2`, avatarID, u.ID)
		return e
	})
	if err != nil {
		return domain.User{}, err
	}
	return r.GetMe(ctx, p)
}
func (r *Repository) loadProfile(ctx context.Context, user *domain.User) error {
	return r.db.QueryRowContext(ctx, `SELECT display_name, avatar_id FROM app.users WHERE id = $1`, uid(user.ID)).Scan(&user.DisplayName, &user.AvatarID)
}
func (r *Repository) RegisterDevice(ctx context.Context, p application.Principal, in application.RegisterInput) (out domain.Device, err error) {
	err = r.transaction(ctx, p, false, func(_ *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		h := hash(struct {
			Input   application.RegisterInput
			Session string
		}{in, p.SessionID})
		ok, e := replay(ctx, queries, u, "register", in.OperationID, h, &out)
		if e != nil || ok {
			return e
		}
		existing, e := queries.RegistrationDevice(ctx, q.RegistrationDeviceParams{UserID: u.ID, RegistrationID: uid(in.RegistrationID)})
		if e == nil {
			if existing.AuthSessionID != uid(p.SessionID) || existing.Platform != in.Platform || existing.Name != in.Name || existing.Status != "ACTIVE" {
				return application.ErrConflict
			}
			out = asDevice(existing)
			return save(ctx, queries, u, "register", in.OperationID, h, out)
		}
		if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		if _, e = queries.SessionDevice(ctx, uid(p.SessionID)); e == nil {
			return application.ErrConflict
		} else if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		if in.Platform == "IOS" {
			n, e := queries.ActiveIPhoneCount(ctx, u.ID)
			if e != nil {
				return e
			}
			if n != 0 {
				return application.ErrPrecondition
			}
		}
		d, e := queries.CreateDevice(ctx, q.CreateDeviceParams{ID: uuid.New(), UserID: u.ID, RegistrationID: uid(in.RegistrationID), AuthSessionID: uid(p.SessionID), Platform: in.Platform, Name: in.Name})
		if e != nil {
			return e
		}
		out = asDevice(d)
		return save(ctx, queries, u, "register", in.OperationID, h, out)
	})
	return
}
func (r *Repository) ListDevices(ctx context.Context, p application.Principal, after string, size int) (out application.DevicePage, err error) {
	err = r.transaction(ctx, p, false, func(_ *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if e := checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		cursor := uuid.Nil
		if after != "" {
			cursor = uid(after)
		}
		rows, e := queries.ListDevices(ctx, q.ListDevicesParams{UserID: u.ID, ID: cursor, Limit: int32(size + 1)})
		if e != nil {
			return e
		}
		out.Devices = []domain.Device{}
		if len(rows) > size {
			rows = rows[:size]
			out.Next = rows[size-1].ID.String()
		}
		for _, d := range rows {
			out.Devices = append(out.Devices, asDevice(d))
		}
		return nil
	})
	return
}
func (r *Repository) RevokeDevice(ctx context.Context, p application.Principal, in application.RevokeInput) (out domain.Device, err error) {
	err = r.transaction(ctx, p, false, func(_ *sql.Tx, queries *q.Queries, u q.AppUser) error {
		h := hash(struct {
			Input   application.RevokeInput
			Session string
		}{in, p.SessionID})
		ok, e := replay(ctx, queries, u, "revoke", in.OperationID, h, &out)
		if e != nil {
			return e
		}
		// A session may replay its own successful revocation, but perform no new work.
		if ok {
			return nil
		}
		if e = checkSession(ctx, queries, p, u.ID); e != nil {
			return e
		}
		d, e := queries.GetDevice(ctx, q.GetDeviceParams{UserID: u.ID, ID: uid(in.DeviceID)})
		if e != nil {
			return translate(e)
		}
		if d.Version != in.ExpectedVersion || d.Status != "ACTIVE" {
			return application.ErrConflict
		}
		d, e = queries.RevokeDevice(ctx, q.RevokeDeviceParams{UserID: u.ID, ID: d.ID, Version: in.ExpectedVersion})
		if e != nil {
			return translate(e)
		}
		out = asDevice(d)
		return save(ctx, queries, u, "revoke", in.OperationID, h, out)
	})
	return
}

func (r *Repository) RegisterNotificationEndpoint(ctx context.Context, p application.Principal, in application.NotificationEndpointInput) error {
	return r.transaction(ctx, p, false, func(tx *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if err := checkSession(ctx, queries, p, u.ID); err != nil {
			return err
		}
		var deviceID uuid.UUID
		var platform, status string
		if err := tx.QueryRowContext(ctx, `SELECT id, platform, status FROM app.devices WHERE auth_session_id = $1 AND user_id = $2`, uid(p.SessionID), u.ID).Scan(&deviceID, &platform, &status); err != nil {
			return translate(err)
		}
		if platform != "IOS" || status != "ACTIVE" {
			return application.ErrForbidden
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO app.notification_endpoints (device_id, user_id, apns_environment, apns_token)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (device_id) DO UPDATE SET
				user_id = EXCLUDED.user_id,
				apns_environment = EXCLUDED.apns_environment,
				apns_token = EXCLUDED.apns_token,
				updated_at = now()`, deviceID, u.ID, in.Environment, strings.ToLower(in.APNsToken))
		return err
	})
}

func (r *Repository) DeleteNotificationEndpoint(ctx context.Context, p application.Principal) error {
	return r.transaction(ctx, p, false, func(tx *sql.Tx, queries *q.Queries, u q.AppUser) error {
		if err := checkSession(ctx, queries, p, u.ID); err != nil {
			return err
		}
		var platform, status string
		if err := tx.QueryRowContext(ctx, `SELECT platform, status FROM app.devices WHERE auth_session_id = $1 AND user_id = $2`, uid(p.SessionID), u.ID).Scan(&platform, &status); err != nil {
			return translate(err)
		}
		if platform != "IOS" || status != "ACTIVE" {
			return application.ErrForbidden
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM app.notification_endpoints WHERE device_id = (SELECT id FROM app.devices WHERE auth_session_id = $1 AND user_id = $2)`, uid(p.SessionID), u.ID)
		return err
	})
}
func (r *Repository) Actor(ctx context.Context, p application.Principal) (application.Actor, error) {
	queries := q.New(r.db)
	u, err := queries.GetUser(ctx, uid(p.Subject))
	if err != nil {
		return application.Actor{}, translate(err)
	}
	if u.Status != "ACTIVE" {
		return application.Actor{}, application.ErrForbidden
	}
	out := application.Actor{UserID: u.ID.String()}
	d, err := queries.SessionDevice(ctx, uid(p.SessionID))
	if errors.Is(err, sql.ErrNoRows) {
		return out, nil
	}
	if err != nil {
		return application.Actor{}, err
	}
	if d.UserID != u.ID || d.Status != "ACTIVE" {
		return application.Actor{}, application.ErrForbidden
	}
	out.DeviceID, out.DevicePlatform = d.ID.String(), d.Platform
	return out, nil
}
func (r *Repository) ActiveIPhone(ctx context.Context, userID string) (string, error) {
	d, err := q.New(r.db).ActiveIPhone(ctx, uid(userID))
	if err != nil {
		return "", translate(err)
	}
	return d.ID.String(), nil
}
