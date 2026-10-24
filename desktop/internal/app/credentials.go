package app

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"runtime"

	"github.com/99designs/keyring"
	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
)

const (
	credentialKey       = "supabase-session-v2"
	legacyCredentialKey = "supabase-session-v1"
)

type credentialStore struct{ ring keyring.Keyring }

func newCredentialStore() (*credentialStore, error) {
	var allowed []keyring.BackendType
	switch runtime.GOOS {
	case "darwin":
		allowed = []keyring.BackendType{keyring.KeychainBackend}
	case "windows":
		allowed = []keyring.BackendType{keyring.WinCredBackend}
	default:
		allowed = []keyring.BackendType{keyring.SecretServiceBackend}
	}
	ring, err := keyring.Open(keyring.Config{
		ServiceName:                    "com.jphacks.focus-link",
		AllowedBackends:                allowed,
		KeychainTrustApplication:       runtime.GOOS == "darwin",
		KeychainAccessibleWhenUnlocked: true,
	})
	if err != nil {
		return nil, fmt.Errorf("OS credential store unavailable: %w", err)
	}
	return &credentialStore{ring: ring}, nil
}

func (s *credentialStore) Load() (cloud.AuthSession, bool, error) {
	item, err := s.ring.Get(credentialKey)
	legacy := false
	if errors.Is(err, keyring.ErrKeyNotFound) {
		item, err = s.ring.Get(legacyCredentialKey)
		legacy = err == nil
	}
	if errors.Is(err, keyring.ErrKeyNotFound) {
		return cloud.AuthSession{}, false, nil
	}
	if err != nil {
		return cloud.AuthSession{}, false, err
	}
	var session cloud.AuthSession
	if err := json.Unmarshal(item.Data, &session); err != nil {
		return cloud.AuthSession{}, false, errors.New("saved authentication session is invalid")
	}
	if session.AccessToken == "" || session.RefreshToken == "" || session.Email == "" {
		return cloud.AuthSession{}, false, errors.New("saved authentication session is incomplete")
	}
	if legacy {
		if err := s.Save(session); err != nil {
			return cloud.AuthSession{}, false, fmt.Errorf("saved authentication session migration failed: %w", err)
		}
		if err := s.ring.Remove(legacyCredentialKey); err != nil && !errors.Is(err, keyring.ErrKeyNotFound) {
			log.Printf("legacy authentication session could not be removed: %v", err)
		}
	}
	return session, true, nil
}

func (s *credentialStore) Save(session cloud.AuthSession) error {
	data, err := json.Marshal(session)
	if err != nil {
		return errors.New("authentication session could not be encoded")
	}
	return s.ring.Set(keyring.Item{
		Key:         credentialKey,
		Data:        data,
		Label:       "Focus Link sign-in",
		Description: "Supabase Auth session for Focus Link",
	})
}

func (s *credentialStore) Delete() error {
	for _, key := range []string{legacyCredentialKey, credentialKey} {
		if err := s.ring.Remove(key); err != nil && !errors.Is(err, keyring.ErrKeyNotFound) {
			return err
		}
	}
	return nil
}

func newUUID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", err
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(value[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s", encoded[:8], encoded[8:12], encoded[12:16], encoded[16:20], encoded[20:]), nil
}
