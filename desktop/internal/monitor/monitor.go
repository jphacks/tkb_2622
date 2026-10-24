// Package monitor captures local macOS activity observations for one session.
package monitor

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	schemaVersion   = "1"
	source          = "macos-native"
	helperTimeout   = 8 * time.Second
	maxOutputLength = 64 * 1024
)

type Observation struct {
	SchemaVersion   string     `json:"schema_version"`
	Source          string     `json:"source"`
	SampleStartedAt time.Time  `json:"sample_started_at"`
	ObservedAt      time.Time  `json:"observed_at"`
	ReceivedAt      time.Time  `json:"received_at"`
	IdleObservedAt  time.Time  `json:"idle_observed_at"`
	AppID           *string    `json:"app_id"`
	AppName         *string    `json:"app_name"`
	IdleSeconds     *float64   `json:"idle_seconds"`
	BrowserName     *string    `json:"browser_name"`
	BrowserDomain   *string    `json:"browser_domain"`
	TabID           *string    `json:"tab_id"`
	BrowserStatus   string     `json:"browser_status"`
	Audible         *bool      `json:"audible"`
	LockState       *bool      `json:"lock_state"`
	SleepState      *bool      `json:"sleep_state"`
	PowerEvent      *string    `json:"power_event,omitempty"`
	PowerObservedAt *time.Time `json:"power_observed_at,omitempty"`
	Reasons         []string   `json:"reasons"`
}

type Status struct {
	State       string `json:"state"`
	AppID       string `json:"appId"`
	AppName     string `json:"appName"`
	BrowserName string `json:"browserName"`
	Domain      string `json:"domain"`
	LastSample  string `json:"lastSample"`
	SampleCount int    `json:"sampleCount"`
	Message     string `json:"message"`
}

type Record struct {
	Kind        string       `json:"kind"`
	SessionID   string       `json:"sessionId"`
	RecordedAt  time.Time    `json:"recordedAt"`
	Observation *Observation `json:"observation,omitempty"`
	Reason      string       `json:"reason,omitempty"`
}

type ClassificationCandidate struct {
	Name        string `json:"name"`
	AppID       string `json:"appId"`
	AppName     string `json:"appName"`
	Domain      string `json:"domain"`
	SampleCount int    `json:"sampleCount"`
}

type Recorder struct {
	helperPath string
	dataDir    string
	sessionID  string
	filePath   string
	status     Status
}

func New(helperPath string) *Recorder {
	state := "unavailable"
	message := "計測ヘルパーが見つかりません。アプリ用ビルド手順を確認してください。"
	if executable(helperPath) {
		state = "ready"
		message = ""
	}
	return &Recorder{
		helperPath: helperPath,
		status:     Status{State: state, Message: message},
	}
}

func ResolveHelper() string {
	if configured := strings.TrimSpace(os.Getenv("FOCUS_LINK_COLLECTOR_PATH")); configured != "" {
		return configured
	}
	if executablePath, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(executablePath), "native-collector")
		if executable(candidate) {
			return candidate
		}
	}
	if workingDirectory, err := os.Getwd(); err == nil {
		candidate := filepath.Join(workingDirectory, "build", "bin", "native-collector")
		if executable(candidate) {
			return candidate
		}
	}
	return ""
}

func NewSessionID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", fmt.Errorf("session id generation failed: %w", err)
	}
	return hex.EncodeToString(value[:]), nil
}

func (r *Recorder) Status() Status { return r.status }

// RestoreSession attaches the recorder to a persisted session without restarting capture.
func (r *Recorder) RestoreSession(sessionID string, previous Status) error {
	if !validSessionID(sessionID) {
		return errors.New("invalid session id")
	}
	configDirectory, err := os.UserConfigDir()
	if err != nil {
		return fmt.Errorf("user config directory unavailable: %w", err)
	}
	dataDirectory := filepath.Join(configDirectory, "Focus Link", "sessions")
	filePath := filepath.Join(dataDirectory, sessionID+".jsonl")
	info, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("session capture could not be opened: %w", err)
	}
	if !info.Mode().IsRegular() {
		return errors.New("session capture is not a regular file")
	}
	r.dataDir = dataDirectory
	r.sessionID = sessionID
	r.filePath = filePath
	previous.State = "paused"
	r.status = previous
	return nil
}

func (r *Recorder) Start(ctx context.Context, sessionID string) (Status, error) {
	if !validSessionID(sessionID) {
		return r.fail(errors.New("invalid session id"))
	}
	if !executable(r.helperPath) {
		return r.fail(errors.New("native collector is unavailable"))
	}
	configDirectory, err := os.UserConfigDir()
	if err != nil {
		return r.fail(fmt.Errorf("user config directory unavailable: %w", err))
	}
	r.dataDir = filepath.Join(configDirectory, "Focus Link", "sessions")
	if err := os.MkdirAll(r.dataDir, 0o700); err != nil {
		return r.fail(fmt.Errorf("session directory unavailable: %w", err))
	}
	if err := os.Chmod(r.dataDir, 0o700); err != nil {
		return r.fail(fmt.Errorf("session directory permissions unavailable: %w", err))
	}
	r.sessionID = sessionID
	r.filePath = filepath.Join(r.dataDir, sessionID+".jsonl")
	r.status = Status{State: "running"}
	if err := r.append(Record{Kind: "started"}); err != nil {
		return r.fail(err)
	}
	return r.Sample(ctx)
}

func (r *Recorder) Sample(ctx context.Context) (Status, error) {
	if r.status.State != "running" {
		return r.status, nil
	}
	observation, err := r.capture(ctx)
	if err != nil {
		_ = r.append(Record{Kind: "sample_error", Reason: "native_sample_failed"})
		r.status.Message = "計測サンプルを取得できませんでした。必要なmacOS権限を確認してください。"
		return r.status, err
	}
	if err := r.append(Record{Kind: "sample", Observation: &observation}); err != nil {
		return r.fail(err)
	}
	r.status.SampleCount++
	r.status.LastSample = observation.ReceivedAt.UTC().Format(time.RFC3339Nano)
	r.status.Message = ""
	r.status.AppID = stringValue(observation.AppID)
	r.status.AppName = stringValue(observation.AppName)
	r.status.BrowserName = stringValue(observation.BrowserName)
	r.status.Domain = stringValue(observation.BrowserDomain)
	return r.status, nil
}

func (r *Recorder) Pause() (Status, error) {
	if r.status.State != "running" {
		return r.status, nil
	}
	if err := r.append(Record{Kind: "paused"}); err != nil {
		return r.fail(err)
	}
	r.status.State = "paused"
	return r.status, nil
}

func (r *Recorder) Resume(ctx context.Context, sessionID string, previous Status) (Status, error) {
	if !validSessionID(sessionID) {
		return r.fail(errors.New("invalid session id"))
	}
	if r.dataDir == "" {
		configDirectory, err := os.UserConfigDir()
		if err != nil {
			return r.fail(fmt.Errorf("user config directory unavailable: %w", err))
		}
		r.dataDir = filepath.Join(configDirectory, "Focus Link", "sessions")
	}
	if err := os.MkdirAll(r.dataDir, 0o700); err != nil {
		return r.fail(fmt.Errorf("session directory unavailable: %w", err))
	}
	if err := os.Chmod(r.dataDir, 0o700); err != nil {
		return r.fail(fmt.Errorf("session directory permissions unavailable: %w", err))
	}
	r.sessionID = sessionID
	r.filePath = filepath.Join(r.dataDir, sessionID+".jsonl")
	if previous.SampleCount < 0 {
		previous.SampleCount = 0
	}
	previous.State = "paused"
	r.status = previous
	r.status.State = "running"
	if err := r.append(Record{Kind: "resumed"}); err != nil {
		return r.fail(err)
	}
	return r.Sample(ctx)
}

func (r *Recorder) Finish(outcome string) (Status, error) {
	if outcome != "finished" && outcome != "aborted" {
		return r.fail(errors.New("invalid session outcome"))
	}
	if r.sessionID == "" {
		r.status.State = "ready"
		return r.status, nil
	}
	if err := r.append(Record{Kind: outcome}); err != nil {
		return r.fail(err)
	}
	r.status.State = outcome
	r.status.Message = ""
	return r.status, nil
}

func (r *Recorder) ReadRecords() ([]Record, error) {
	if r.filePath == "" || r.sessionID == "" {
		return nil, errors.New("session capture path unavailable")
	}
	file, err := os.Open(r.filePath)
	if err != nil {
		return nil, fmt.Errorf("session capture could not be opened: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), maxOutputLength*2)
	records := make([]Record, 0)
	for scanner.Scan() {
		var value Record
		if err := json.Unmarshal(scanner.Bytes(), &value); err != nil {
			return nil, fmt.Errorf("session capture record is invalid: %w", err)
		}
		if value.SessionID != r.sessionID {
			return nil, errors.New("session capture contains a different session id")
		}
		records = append(records, value)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("session capture could not be read: %w", err)
	}
	return records, nil
}

func ReadClassificationCandidates(sessionID string) ([]ClassificationCandidate, error) {
	if !validSessionID(sessionID) {
		return nil, errors.New("invalid session id")
	}
	configDirectory, err := os.UserConfigDir()
	if err != nil {
		return nil, fmt.Errorf("user config directory unavailable: %w", err)
	}
	filePath := filepath.Join(configDirectory, "Focus Link", "sessions", sessionID+".jsonl")
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("session capture could not be opened: %w", err)
	}
	defer file.Close()

	candidates := map[string]*ClassificationCandidate{}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), maxOutputLength*2)
	for scanner.Scan() {
		var record Record
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			return nil, fmt.Errorf("session capture record is invalid: %w", err)
		}
		if record.SessionID != sessionID {
			return nil, errors.New("session capture contains a different session id")
		}
		if record.Kind != "sample" || record.Observation == nil {
			continue
		}
		observation := record.Observation
		appID := stringValue(observation.AppID)
		domain := stringValue(observation.BrowserDomain)
		if appID == "" || appID == "com.wails.focus-link" {
			continue
		}
		if domain == "" && (strings.EqualFold(appID, "com.google.Chrome") || strings.EqualFold(appID, "com.apple.Safari")) {
			continue
		}
		appName := stringValue(observation.AppName)
		name := domain
		if name == "" {
			name = appName
		}
		if name == "" {
			name = appID
		}
		key := strings.ToLower(appID) + "\x00" + strings.ToLower(domain)
		candidate := candidates[key]
		if candidate == nil {
			candidate = &ClassificationCandidate{Name: name, AppID: appID, AppName: appName, Domain: domain}
			candidates[key] = candidate
		}
		candidate.SampleCount++
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("session capture could not be read: %w", err)
	}

	result := make([]ClassificationCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		result = append(result, *candidate)
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].SampleCount == result[j].SampleCount {
			return result[i].Name < result[j].Name
		}
		return result[i].SampleCount > result[j].SampleCount
	})
	return result, nil
}

func (r *Recorder) capture(ctx context.Context) (Observation, error) {
	requestContext, cancel := context.WithTimeout(ctx, helperTimeout)
	defer cancel()
	command := exec.CommandContext(requestContext, r.helperPath, "--once")
	var output boundedBuffer
	command.Stdout = &output
	// Helper output can contain local activity metadata; never surface stderr.
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		if requestContext.Err() != nil {
			return Observation{}, errors.New("native collector timed out or was cancelled")
		}
		return Observation{}, errors.New("native collector failed")
	}
	decoder := json.NewDecoder(bytes.NewReader(output.Bytes()))
	decoder.DisallowUnknownFields()
	var observation Observation
	if err := decoder.Decode(&observation); err != nil {
		return Observation{}, errors.New("native collector returned invalid data")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return Observation{}, errors.New("native collector returned extra data")
	}
	if observation.SchemaVersion != schemaVersion || observation.Source != source ||
		observation.SampleStartedAt.IsZero() || observation.ObservedAt.IsZero() {
		return Observation{}, errors.New("native collector returned unsupported data")
	}
	// Browser tab identifiers are not needed for classification and stay out of the local log.
	observation.TabID = nil
	observation.ReceivedAt = time.Now().UTC()
	return observation, nil
}

func (r *Recorder) append(value Record) error {
	if r.filePath == "" {
		return errors.New("session capture path unavailable")
	}
	value.SessionID = r.sessionID
	value.RecordedAt = time.Now().UTC()
	file, err := os.OpenFile(r.filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("session capture could not be opened: %w", err)
	}
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return fmt.Errorf("session capture permissions could not be set: %w", err)
	}
	encodeErr := json.NewEncoder(file).Encode(value)
	syncErr := file.Sync()
	closeErr := file.Close()
	if err := errors.Join(encodeErr, syncErr, closeErr); err != nil {
		return fmt.Errorf("session capture could not be saved: %w", err)
	}
	return nil
}

func (r *Recorder) fail(err error) (Status, error) {
	r.status.State = "error"
	r.status.Message = "計測を開始・保存できませんでした。macOSの権限と保存先を確認してください。"
	return r.status, err
}

type boundedBuffer struct{ bytes.Buffer }

func (b *boundedBuffer) Write(data []byte) (int, error) {
	if b.Len()+len(data) > maxOutputLength {
		return 0, errors.New("native collector output exceeded limit")
	}
	return b.Buffer.Write(data)
}

func executable(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Mode()&0o111 != 0
}

func validSessionID(value string) bool {
	if value == "" || len(value) > 64 {
		return false
	}
	for _, character := range value {
		if !(character >= 'a' && character <= 'z') &&
			!(character >= '0' && character <= '9') &&
			character != '-' {
			return false
		}
	}
	return true
}

func stringValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
