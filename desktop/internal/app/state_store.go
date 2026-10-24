package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

const maxStateSize = 8 * 1024 * 1024

type stateStore struct{ path string }

func newStateStore() (*stateStore, error) {
	configDirectory, err := os.UserConfigDir()
	if err != nil {
		return nil, fmt.Errorf("user config directory unavailable: %w", err)
	}
	directory := filepath.Join(configDirectory, "Focus Link")
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return nil, fmt.Errorf("application state directory unavailable: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return nil, fmt.Errorf("application state directory permissions unavailable: %w", err)
	}
	return &stateStore{path: filepath.Join(directory, "desktop-state.json")}, nil
}

func (s *stateStore) Load() (session.Snapshot, bool, error) {
	file, err := os.Open(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return session.Snapshot{}, false, nil
	}
	if err != nil {
		return session.Snapshot{}, false, fmt.Errorf("application state could not be opened: %w", err)
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxStateSize+1))
	if err != nil {
		return session.Snapshot{}, false, fmt.Errorf("application state could not be read: %w", err)
	}
	if len(data) > maxStateSize {
		return session.Snapshot{}, false, errors.New("application state exceeds size limit")
	}
	var snapshot session.Snapshot
	if err := json.Unmarshal(data, &snapshot); err != nil {
		return session.Snapshot{}, false, fmt.Errorf("application state is invalid: %w", err)
	}
	return snapshot, true, nil
}

func (s *stateStore) Save(snapshot session.Snapshot) error {
	data, err := json.Marshal(snapshot)
	if err != nil {
		return fmt.Errorf("application state could not be encoded: %w", err)
	}
	if len(data) > maxStateSize {
		return errors.New("application state exceeds size limit")
	}
	temporaryPath := s.path + ".tmp"
	file, err := os.OpenFile(temporaryPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("temporary application state could not be created: %w", err)
	}
	writeErr := file.Chmod(0o600)
	if writeErr == nil {
		_, writeErr = file.Write(data)
	}
	if writeErr == nil {
		writeErr = file.Sync()
	}
	closeErr := file.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("application state could not be saved: %w", err)
	}
	if err := os.Rename(temporaryPath, s.path); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("application state could not be committed: %w", err)
	}
	return nil
}
