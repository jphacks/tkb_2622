package cloud

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/mail"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const maxResponseBytes = 2 << 20

type Config struct {
	APIBaseURL             string
	SupabaseURL            string
	SupabasePublishableKey string
}

func ConfigFromEnv() Config {
	return Config{
		APIBaseURL:             strings.TrimSpace(os.Getenv("FOCUS_LINK_API_BASE_URL")),
		SupabaseURL:            strings.TrimSpace(os.Getenv("FOCUS_LINK_SUPABASE_URL")),
		SupabasePublishableKey: strings.TrimSpace(os.Getenv("FOCUS_LINK_SUPABASE_PUBLISHABLE_KEY")),
	}
}

type AuthSession struct {
	AccessToken         string    `json:"accessToken"`
	RefreshToken        string    `json:"refreshToken"`
	ExpiresAt           time.Time `json:"expiresAt"`
	Email               string    `json:"email"`
	PCDeviceID          string    `json:"pcDeviceId"`
	EnsureOperationID   string    `json:"ensureOperationId"`
	RegistrationID      string    `json:"registrationId"`
	RegisterOperationID string    `json:"registerOperationId"`
}

type TaskSettings struct {
	Name           string
	Category       string
	Mode           string
	PlannedSeconds int64
	MinimumSeconds int64
}

type Task struct {
	ID       string
	Settings TaskSettings
	Version  int64
}

type Session struct {
	ID                 string
	DeviceID           string
	TaskID             string
	TaskSettings       TaskSettings
	Status             string
	Version            int64
	TrackingOnly       bool
	AcceptedThroughSeq int64
	Durations          Durations
	StartedAt          time.Time
	Balance            Balance
}

type Durations struct {
	TaskMillis              int64
	RelatedTransitionMillis int64
	DistractionMillis       int64
	UnknownMillis           int64
	IdleMillis              int64
	ActiveMillis            int64
	WorkMillis              int64
}

type ActivitySegment struct {
	StartTime      time.Time `json:"startTime"`
	EndTime        time.Time `json:"endTime"`
	Classification string    `json:"classification"`
	Reasons        []string  `json:"reasons,omitempty"`
}

type ActivityBatch struct {
	SessionID        string            `json:"sessionId"`
	BatchID          string            `json:"batchId"`
	Seq              int64             `json:"seq"`
	EvaluatorVersion string            `json:"evaluatorVersion"`
	RulesVersion     string            `json:"rulesVersion"`
	Segments         []ActivitySegment `json:"segments"`
}

type ActivityReceipt struct {
	BatchID            string
	Seq                int64
	Status             string
	AcceptedThroughSeq int64
	MissingSeqs        []int64
	EarnedSeconds      int64
}

type Balance struct {
	SessionID           string
	BalanceSeconds      int64
	Version             int64
	EvaluatedThroughSeq int64
}

type SessionResult struct {
	Session   Session
	Discarded int64
	Balance   Balance
}

type RewardSummary struct {
	EarnedSeconds    int64
	SpentSeconds     int64
	DiscardedSeconds int64
}

type Client struct {
	config     Config
	base       *url.URL
	auth       *url.URL
	httpClient *http.Client
}

func NewClient(config Config) (*Client, error) {
	apiBase, err := parseBaseURL(config.APIBaseURL)
	if err != nil {
		return nil, fmt.Errorf("Connect API URL: %w", err)
	}
	supabaseBase, err := parseBaseURL(config.SupabaseURL)
	if err != nil {
		return nil, fmt.Errorf("Supabase URL: %w", err)
	}
	if config.SupabasePublishableKey == "" {
		return nil, errors.New("Supabase publishable key is not configured")
	}
	authBase := *supabaseBase
	authBase.Path = strings.TrimRight(authBase.Path, "/") + "/auth/v1"
	return &Client{
		config: config,
		base:   apiBase,
		auth:   &authBase,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}, nil
}

func parseBaseURL(raw string) (*url.URL, error) {
	if raw == "" {
		return nil, errors.New("URL is not configured")
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return nil, errors.New("URL is invalid")
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && isLoopback(u.Hostname())) {
		return nil, errors.New("HTTPS is required except for loopback development URLs")
	}
	u.Path = strings.TrimRight(u.Path, "/")
	return u, nil
}

func isLoopback(host string) bool {
	return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

func (c *Client) RequestEmailOTP(ctx context.Context, email string) error {
	parsed, err := mail.ParseAddress(strings.TrimSpace(email))
	if err != nil || parsed.Address != strings.TrimSpace(email) {
		return errors.New("メールアドレスを確認してください")
	}
	return c.authRequest(ctx, http.MethodPost, "/otp", map[string]any{"email": parsed.Address, "create_user": true}, nil, "")
}

func (c *Client) VerifyEmailOTP(ctx context.Context, email, code string) (AuthSession, error) {
	email = strings.TrimSpace(email)
	code = strings.TrimSpace(code)
	if email == "" || code == "" || len(code) > 64 {
		return AuthSession{}, errors.New("確認コードを入力してください")
	}
	var response authResponse
	if err := c.authRequest(ctx, http.MethodPost, "/verify", map[string]any{"email": email, "token": code, "type": "email"}, &response, ""); err != nil {
		return AuthSession{}, err
	}
	if response.AccessToken == "" || response.RefreshToken == "" || response.ExpiresIn <= 0 || response.User.Email == "" {
		return AuthSession{}, errors.New("Supabase Authから有効なセッションが返りませんでした")
	}
	return AuthSession{
		AccessToken:  response.AccessToken,
		RefreshToken: response.RefreshToken,
		ExpiresAt:    time.Now().Add(time.Duration(response.ExpiresIn) * time.Second),
		Email:        response.User.Email,
	}, nil
}

func (c *Client) RefreshSession(ctx context.Context, current AuthSession) (AuthSession, error) {
	var response authResponse
	if err := c.authRequest(ctx, http.MethodPost, "/token?grant_type=refresh_token", map[string]any{"refresh_token": current.RefreshToken}, &response, ""); err != nil {
		return AuthSession{}, err
	}
	if response.AccessToken == "" || response.RefreshToken == "" || response.ExpiresIn <= 0 {
		return AuthSession{}, errors.New("Supabase Authから更新済みセッションが返りませんでした")
	}
	current.AccessToken = response.AccessToken
	current.RefreshToken = response.RefreshToken
	current.ExpiresAt = time.Now().Add(time.Duration(response.ExpiresIn) * time.Second)
	if response.User.Email != "" {
		current.Email = response.User.Email
	}
	return current, nil
}

func (c *Client) SignOut(ctx context.Context, current AuthSession) error {
	return c.authRequest(ctx, http.MethodPost, "/logout", nil, nil, current.AccessToken)
}

type authResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
	User         struct {
		Email string `json:"email"`
	} `json:"user"`
}

func (c *Client) authRequest(ctx context.Context, method, path string, input, output any, accessToken string) error {
	relative, err := url.Parse(path)
	if err != nil {
		return errors.New("Supabase Auth endpoint is invalid")
	}
	endpoint := *c.auth
	endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/" + strings.TrimLeft(relative.Path, "/")
	endpoint.RawQuery = relative.RawQuery
	return c.request(ctx, method, &endpoint, input, output, true, accessToken)
}

func (c *Client) Connect(ctx context.Context, method, accessToken string, input, output any) error {
	endpoint := *c.base
	endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/" + method
	return c.request(ctx, http.MethodPost, &endpoint, input, output, false, accessToken)
}

func (c *Client) request(ctx context.Context, method string, endpoint *url.URL, input, output any, auth bool, accessToken string) error {
	var body io.Reader
	if input != nil {
		data, err := json.Marshal(input)
		if err != nil {
			return errors.New("request could not be encoded")
		}
		body = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint.String(), body)
	if err != nil {
		return errors.New("request could not be created")
	}
	req.Header.Set("Accept", "application/json")
	if input != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if auth {
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("apikey", c.config.SupabasePublishableKey)
		if accessToken != "" {
			req.Header.Set("Authorization", "Bearer "+accessToken)
		}
	} else {
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Connect-Protocol-Version", "1")
		req.Header.Set("Authorization", "Bearer "+accessToken)
	}
	response, err := c.httpClient.Do(req)
	if err != nil {
		return errors.New("サーバーに接続できませんでした。接続先とネットワークを確認してください")
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, maxResponseBytes+1))
	if err != nil || len(data) > maxResponseBytes {
		return errors.New("サーバー応答を読み取れませんでした")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return responseError(response.StatusCode, data)
	}
	if output == nil || len(bytes.TrimSpace(data)) == 0 {
		return nil
	}
	if err := json.Unmarshal(data, output); err != nil {
		return errors.New("サーバー応答を解釈できませんでした")
	}
	return nil
}

func responseError(status int, data []byte) error {
	var apiError struct {
		Code             string `json:"code"`
		Message          string `json:"message"`
		MessageShort     string `json:"msg"`
		ErrorDescription string `json:"error_description"`
	}
	_ = json.Unmarshal(data, &apiError)
	message := strings.TrimSpace(apiError.Message)
	if message == "" {
		message = strings.TrimSpace(apiError.MessageShort)
	}
	if message == "" {
		message = strings.TrimSpace(apiError.ErrorDescription)
	}
	if message == "" {
		message = http.StatusText(status)
	}
	if len(message) > 240 {
		message = message[:240]
	}
	return fmt.Errorf("API error (%s): %s", apiError.Code, message)
}

type protoInt64 int64

func (value protoInt64) MarshalJSON() ([]byte, error) {
	return json.Marshal(strconv.FormatInt(int64(value), 10))
}

func (value *protoInt64) UnmarshalJSON(data []byte) error {
	text := strings.Trim(string(data), "\"")
	parsed, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		return err
	}
	*value = protoInt64(parsed)
	return nil
}

type taskSettingsMessage struct {
	Name           string     `json:"name,omitempty"`
	Category       string     `json:"category,omitempty"`
	Mode           string     `json:"mode,omitempty"`
	PlannedSeconds protoInt64 `json:"plannedSeconds,omitempty"`
	MinimumSeconds protoInt64 `json:"minimumSeconds,omitempty"`
}

type taskMessage struct {
	ID       string              `json:"id"`
	Settings taskSettingsMessage `json:"settings"`
	Version  protoInt64          `json:"version"`
}

func taskFromMessage(message taskMessage) Task {
	return Task{
		ID: message.ID,
		Settings: TaskSettings{
			Name: message.Settings.Name, Category: strings.TrimPrefix(message.Settings.Category, "TASK_CATEGORY_"),
			Mode:           strings.TrimPrefix(message.Settings.Mode, "FOCUS_MODE_"),
			PlannedSeconds: int64(message.Settings.PlannedSeconds), MinimumSeconds: int64(message.Settings.MinimumSeconds),
		},
		Version: int64(message.Version),
	}
}

func taskSettingsToMessage(settings TaskSettings) taskSettingsMessage {
	return taskSettingsMessage{
		Name: settings.Name, Category: "TASK_CATEGORY_" + settings.Category, Mode: "FOCUS_MODE_" + settings.Mode,
		PlannedSeconds: protoInt64(settings.PlannedSeconds), MinimumSeconds: protoInt64(settings.MinimumSeconds),
	}
}

func (c *Client) EnsureUser(ctx context.Context, session AuthSession) error {
	var response struct {
		User json.RawMessage `json:"user"`
	}
	return c.Connect(ctx, "identity.v1.IdentityService/EnsureUser", session.AccessToken, map[string]string{"operationId": session.EnsureOperationID}, &response)
}

func (c *Client) RegisterPCDevice(ctx context.Context, session AuthSession, platform, name string) (string, error) {
	var response struct {
		Device struct {
			ID string `json:"id"`
		} `json:"device"`
	}
	platformName := map[string]string{"MACOS": "PLATFORM_MACOS", "WINDOWS": "PLATFORM_WINDOWS"}[platform]
	if platformName == "" {
		return "", errors.New("unsupported PC platform")
	}
	input := map[string]string{
		"operationId": session.RegisterOperationID, "registrationId": session.RegistrationID,
		"platform": platformName, "name": name,
	}
	if err := c.Connect(ctx, "identity.v1.IdentityService/RegisterDevice", session.AccessToken, input, &response); err != nil {
		return "", err
	}
	if response.Device.ID == "" {
		return "", errors.New("PC端末登録APIから端末IDが返りませんでした")
	}
	return response.Device.ID, nil
}

func (c *Client) ListTasks(ctx context.Context, session AuthSession) ([]Task, error) {
	tasks := make([]Task, 0)
	pageToken := ""
	for page := 0; page < 100; page++ {
		input := map[string]any{"pageSize": 100}
		if pageToken != "" {
			input["pageToken"] = pageToken
		}
		var response struct {
			Tasks         []taskMessage `json:"tasks"`
			NextPageToken string        `json:"nextPageToken"`
		}
		if err := c.Connect(ctx, "focus.v1.FocusService/ListTasks", session.AccessToken, input, &response); err != nil {
			return nil, err
		}
		for _, task := range response.Tasks {
			tasks = append(tasks, taskFromMessage(task))
		}
		if response.NextPageToken == "" {
			return tasks, nil
		}
		pageToken = response.NextPageToken
	}
	return nil, errors.New("タスク一覧のページ数が上限を超えました")
}

func (c *Client) CreateTask(ctx context.Context, session AuthSession, operationID string, settings TaskSettings) (Task, error) {
	var response struct {
		Task taskMessage `json:"task"`
	}
	input := map[string]any{"operationId": operationID, "settings": taskSettingsToMessage(settings)}
	if err := c.Connect(ctx, "focus.v1.FocusService/CreateTask", session.AccessToken, input, &response); err != nil {
		return Task{}, err
	}
	return taskFromMessage(response.Task), nil
}

func (c *Client) UpdateTask(ctx context.Context, session AuthSession, taskID string, version int64, operationID string, settings TaskSettings) (Task, error) {
	var response struct {
		Task taskMessage `json:"task"`
	}
	input := map[string]any{
		"operationId": operationID, "taskId": taskID, "expectedVersion": protoInt64(version),
		"settings": taskSettingsToMessage(settings),
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/UpdateTask", session.AccessToken, input, &response); err != nil {
		return Task{}, err
	}
	return taskFromMessage(response.Task), nil
}

type sessionMessage struct {
	ID                 string              `json:"id"`
	DeviceID           string              `json:"deviceId"`
	TaskID             string              `json:"taskId"`
	TaskSnapshot       taskSettingsMessage `json:"taskSnapshot"`
	Status             string              `json:"status"`
	Version            protoInt64          `json:"version"`
	TrackingOnly       bool                `json:"trackingOnly"`
	AcceptedThroughSeq protoInt64          `json:"acceptedThroughSeq"`
	Durations          durationMessage     `json:"durations"`
	StartedAt          string              `json:"startedAt"`
}

type durationMessage struct {
	TaskMillis              protoInt64 `json:"taskMillis"`
	RelatedTransitionMillis protoInt64 `json:"relatedTransitionMillis"`
	DistractionMillis       protoInt64 `json:"distractionMillis"`
	UnknownMillis           protoInt64 `json:"unknownMillis"`
	IdleMillis              protoInt64 `json:"idleMillis"`
	ActiveMillis            protoInt64 `json:"activeMillis"`
	WorkMillis              protoInt64 `json:"workMillis"`
}

func sessionFromMessage(message sessionMessage) Session {
	startedAt, _ := time.Parse(time.RFC3339Nano, message.StartedAt)
	return Session{
		ID: message.ID, DeviceID: message.DeviceID, TaskID: message.TaskID,
		TaskSettings: TaskSettings{
			Name:           message.TaskSnapshot.Name,
			Category:       strings.TrimPrefix(message.TaskSnapshot.Category, "TASK_CATEGORY_"),
			Mode:           strings.TrimPrefix(message.TaskSnapshot.Mode, "FOCUS_MODE_"),
			PlannedSeconds: int64(message.TaskSnapshot.PlannedSeconds),
			MinimumSeconds: int64(message.TaskSnapshot.MinimumSeconds),
		},
		Status: strings.TrimPrefix(message.Status, "SESSION_STATUS_"), Version: int64(message.Version),
		TrackingOnly: message.TrackingOnly, AcceptedThroughSeq: int64(message.AcceptedThroughSeq),
		Durations: Durations{
			TaskMillis: int64(message.Durations.TaskMillis), RelatedTransitionMillis: int64(message.Durations.RelatedTransitionMillis),
			DistractionMillis: int64(message.Durations.DistractionMillis), UnknownMillis: int64(message.Durations.UnknownMillis),
			IdleMillis: int64(message.Durations.IdleMillis), ActiveMillis: int64(message.Durations.ActiveMillis),
			WorkMillis: int64(message.Durations.WorkMillis),
		},
		StartedAt: startedAt,
	}
}

func (c *Client) GetCurrentSession(ctx context.Context, session AuthSession) (*Session, error) {
	var response struct {
		Session *sessionMessage `json:"session"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/GetCurrentSession", session.AccessToken, struct{}{}, &response); err != nil {
		return nil, err
	}
	if response.Session == nil {
		return nil, nil
	}
	current := sessionFromMessage(*response.Session)
	if current.ID == "" || current.DeviceID == "" || current.TaskID == "" || current.Version < 1 || (current.Status != "RUNNING" && current.Status != "PAUSED") {
		return nil, errors.New("APIから有効な未終了セッションが返りませんでした")
	}
	return &current, nil
}

func (c *Client) StartSession(ctx context.Context, session AuthSession, operationID string, task Task) (Session, error) {
	if operationID == "" || task.ID == "" || task.Version < 1 {
		return Session{}, errors.New("開始するタスクを再読み込みしてください")
	}
	var response struct {
		Session sessionMessage  `json:"session"`
		Balance *balanceMessage `json:"balance"`
	}
	input := map[string]any{
		"operationId": operationID, "taskId": task.ID, "taskVersion": protoInt64(task.Version),
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/StartSession", session.AccessToken, input, &response); err != nil {
		message := strings.ToLower(err.Error())
		if strings.Contains(message, "register an iphone as the restriction target first") {
			return Session{}, errors.New("作業を開始するには、先にiPhoneを制限対象として登録してください")
		}
		if strings.Contains(message, "enable the restriction policy on the iphone first") {
			return Session{}, errors.New("作業を開始するには、iPhoneで利用制限を有効にしてください")
		}
		return Session{}, err
	}
	started := sessionFromMessage(response.Session)
	if started.ID == "" || started.DeviceID == "" || started.TaskID != task.ID || started.Version < 1 || started.Status != "RUNNING" {
		return Session{}, errors.New("APIから有効な開始済みセッションが返りませんでした")
	}
	if response.Balance == nil || response.Balance.SessionID != started.ID {
		return Session{}, errors.New("APIの報酬残高が開始したセッションと一致しません")
	}
	started.Balance = balanceFromMessage(*response.Balance)
	return started, nil
}

func (c *Client) GetBalance(ctx context.Context, auth AuthSession) (Balance, error) {
	var response struct {
		Balance *balanceMessage `json:"balance"`
	}
	if err := c.Connect(ctx, "reward.v1.RewardService/GetBalance", auth.AccessToken, struct{}{}, &response); err != nil {
		return Balance{}, err
	}
	if response.Balance == nil {
		return Balance{}, errors.New("API omitted the reward balance")
	}
	return balanceFromMessage(*response.Balance), nil
}

type activitySegmentMessage struct {
	StartTime      string   `json:"startTime"`
	EndTime        string   `json:"endTime"`
	Classification string   `json:"classification"`
	Reasons        []string `json:"reasons,omitempty"`
}

func activitySegmentsToMessages(segments []ActivitySegment) ([]activitySegmentMessage, error) {
	converted := make([]activitySegmentMessage, 0, len(segments))
	var previousEnd time.Time
	for index, segment := range segments {
		if segment.StartTime.IsZero() || !segment.EndTime.After(segment.StartTime) ||
			(index > 0 && segment.StartTime.Before(previousEnd)) || !validActivityClassification(segment.Classification) {
			return nil, fmt.Errorf("invalid activity segment %d", index)
		}
		converted = append(converted, activitySegmentMessage{
			StartTime:      segment.StartTime.UTC().Format(time.RFC3339Nano),
			EndTime:        segment.EndTime.UTC().Format(time.RFC3339Nano),
			Classification: segment.Classification,
			Reasons:        append([]string(nil), segment.Reasons...),
		})
		previousEnd = segment.EndTime
	}
	return converted, nil
}

func validActivityClassification(value string) bool {
	switch value {
	case "ACTIVITY_CLASS_TASK", "ACTIVITY_CLASS_RELATED_TRANSITION", "ACTIVITY_CLASS_DISTRACTION", "ACTIVITY_CLASS_UNKNOWN", "ACTIVITY_CLASS_IDLE":
		return true
	default:
		return false
	}
}

type activityReceiptMessage struct {
	BatchID            string       `json:"batchId"`
	Seq                protoInt64   `json:"seq"`
	Status             string       `json:"status"`
	AcceptedThroughSeq protoInt64   `json:"acceptedThroughSeq"`
	MissingSeqs        []protoInt64 `json:"missingSeqs"`
	EarnedSeconds      protoInt64   `json:"earnedSeconds"`
}

type balanceMessage struct {
	SessionID           string     `json:"sessionId"`
	BalanceSeconds      protoInt64 `json:"balanceSeconds"`
	Version             protoInt64 `json:"version"`
	EvaluatedThroughSeq protoInt64 `json:"evaluatedThroughSeq"`
}

func balanceFromMessage(message balanceMessage) Balance {
	return Balance{
		SessionID: message.SessionID, BalanceSeconds: int64(message.BalanceSeconds),
		Version: int64(message.Version), EvaluatedThroughSeq: int64(message.EvaluatedThroughSeq),
	}
}

func (c *Client) UploadActivityBatch(ctx context.Context, auth AuthSession, batch ActivityBatch) (ActivityReceipt, Balance, error) {
	if batch.SessionID == "" || batch.BatchID == "" || batch.Seq < 1 || batch.EvaluatorVersion == "" || batch.RulesVersion == "" || len(batch.Segments) == 0 {
		return ActivityReceipt{}, Balance{}, errors.New("activity batch is incomplete")
	}
	segments, err := activitySegmentsToMessages(batch.Segments)
	if err != nil {
		return ActivityReceipt{}, Balance{}, err
	}
	input := map[string]any{
		"sessionId": batch.SessionID, "batchId": batch.BatchID, "seq": protoInt64(batch.Seq),
		"evaluatorVersion": batch.EvaluatorVersion, "rulesVersion": batch.RulesVersion, "segments": segments,
	}
	var response struct {
		Receipt *activityReceiptMessage `json:"receipt"`
		Balance *balanceMessage         `json:"balance"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/UploadActivityBatch", auth.AccessToken, input, &response); err != nil {
		return ActivityReceipt{}, Balance{}, err
	}
	if response.Receipt == nil || response.Receipt.BatchID != batch.BatchID || int64(response.Receipt.Seq) != batch.Seq {
		return ActivityReceipt{}, Balance{}, errors.New("API did not confirm the activity batch")
	}
	receipt := ActivityReceipt{
		BatchID: response.Receipt.BatchID, Seq: int64(response.Receipt.Seq),
		Status:             strings.TrimPrefix(response.Receipt.Status, "BATCH_STATUS_"),
		AcceptedThroughSeq: int64(response.Receipt.AcceptedThroughSeq), EarnedSeconds: int64(response.Receipt.EarnedSeconds),
	}
	for _, sequence := range response.Receipt.MissingSeqs {
		receipt.MissingSeqs = append(receipt.MissingSeqs, int64(sequence))
	}
	if receipt.Status != "ACCEPTED" && receipt.Status != "PENDING" && receipt.Status != "HISTORY" {
		return ActivityReceipt{}, Balance{}, errors.New("API returned an unknown activity batch status")
	}
	if response.Balance == nil {
		return ActivityReceipt{}, Balance{}, errors.New("API omitted the reward balance")
	}
	return receipt, balanceFromMessage(*response.Balance), nil
}

func (c *Client) PauseSession(ctx context.Context, auth AuthSession, operationID, sessionID string, expectedVersion int64, pausedAt time.Time, lastSeq int64) (Session, Balance, error) {
	if operationID == "" || sessionID == "" || expectedVersion < 1 || pausedAt.IsZero() || lastSeq < 0 {
		return Session{}, Balance{}, errors.New("pause operation is incomplete")
	}
	input := map[string]any{
		"operationId": operationID, "sessionId": sessionID, "expectedVersion": protoInt64(expectedVersion),
		"pausedAt": pausedAt.UTC().Format(time.RFC3339Nano), "lastSeq": protoInt64(lastSeq),
	}
	var response struct {
		Session *sessionMessage `json:"session"`
		Balance *balanceMessage `json:"balance"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/PauseSession", auth.AccessToken, input, &response); err != nil {
		return Session{}, Balance{}, err
	}
	if response.Session == nil || response.Session.ID != sessionID || strings.TrimPrefix(response.Session.Status, "SESSION_STATUS_") != "PAUSED" || response.Session.Version < 1 {
		return Session{}, Balance{}, errors.New("API did not confirm the paused session")
	}
	if response.Balance == nil {
		return Session{}, Balance{}, errors.New("API omitted the reward balance")
	}
	return sessionFromMessage(*response.Session), balanceFromMessage(*response.Balance), nil
}

func (c *Client) ResumeSession(ctx context.Context, auth AuthSession, operationID, sessionID string, expectedVersion int64) (Session, Balance, error) {
	if operationID == "" || sessionID == "" || expectedVersion < 1 {
		return Session{}, Balance{}, errors.New("resume operation is incomplete")
	}
	input := map[string]any{
		"operationId": operationID, "sessionId": sessionID, "expectedVersion": protoInt64(expectedVersion),
	}
	var response struct {
		Session *sessionMessage `json:"session"`
		Balance *balanceMessage `json:"balance"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/ResumeSession", auth.AccessToken, input, &response); err != nil {
		return Session{}, Balance{}, err
	}
	if response.Session == nil || response.Session.ID != sessionID || strings.TrimPrefix(response.Session.Status, "SESSION_STATUS_") != "RUNNING" || response.Session.Version < 1 {
		return Session{}, Balance{}, errors.New("API did not confirm the resumed session")
	}
	if response.Balance == nil {
		return Session{}, Balance{}, errors.New("API omitted the reward balance")
	}
	return sessionFromMessage(*response.Session), balanceFromMessage(*response.Balance), nil
}

func (c *Client) FinishSession(ctx context.Context, auth AuthSession, operationID, sessionID string, expectedVersion int64, endedAt time.Time, lastSeq int64, remaining []ActivitySegment) (SessionResult, error) {
	return c.endSession(ctx, auth, "FinishSession", "FINALIZED", operationID, sessionID, expectedVersion, endedAt, lastSeq, remaining)
}

func (c *Client) AbortSessionWithActivity(ctx context.Context, auth AuthSession, operationID, sessionID string, expectedVersion int64, endedAt time.Time, lastSeq int64, remaining []ActivitySegment) (SessionResult, error) {
	return c.endSession(ctx, auth, "AbortSession", "ABORTED", operationID, sessionID, expectedVersion, endedAt, lastSeq, remaining)
}

func (c *Client) endSession(ctx context.Context, auth AuthSession, rpc, expectedStatus, operationID, sessionID string, expectedVersion int64, endedAt time.Time, lastSeq int64, remaining []ActivitySegment) (SessionResult, error) {
	if operationID == "" || sessionID == "" || expectedVersion < 1 || endedAt.IsZero() || lastSeq < 0 {
		return SessionResult{}, errors.New("end operation is incomplete")
	}
	segments, err := activitySegmentsToMessages(remaining)
	if err != nil {
		return SessionResult{}, err
	}
	input := map[string]any{
		"operationId": operationID, "sessionId": sessionID, "expectedVersion": protoInt64(expectedVersion),
		"endedAt": endedAt.UTC().Format(time.RFC3339Nano), "lastSeq": protoInt64(lastSeq), "remainingSegments": segments,
	}
	var response struct {
		Session          *sessionMessage `json:"session"`
		DiscardedSeconds protoInt64      `json:"discardedSeconds"`
		Balance          *balanceMessage `json:"balance"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/"+rpc, auth.AccessToken, input, &response); err != nil {
		return SessionResult{}, err
	}
	if response.Session == nil || response.Session.ID != sessionID || strings.TrimPrefix(response.Session.Status, "SESSION_STATUS_") != expectedStatus || response.Session.Version < 1 {
		return SessionResult{}, errors.New("API did not confirm the ended session")
	}
	if response.Balance == nil {
		return SessionResult{}, errors.New("API omitted the reward balance")
	}
	return SessionResult{
		Session: sessionFromMessage(*response.Session), Discarded: int64(response.DiscardedSeconds),
		Balance: balanceFromMessage(*response.Balance),
	}, nil
}

func (c *Client) GetSession(ctx context.Context, auth AuthSession, sessionID string) (Session, RewardSummary, error) {
	if sessionID == "" {
		return Session{}, RewardSummary{}, errors.New("session ID is required")
	}
	var response struct {
		Session *sessionMessage `json:"session"`
		Reward  *struct {
			EarnedSeconds    protoInt64 `json:"earnedSeconds"`
			SpentSeconds     protoInt64 `json:"spentSeconds"`
			DiscardedSeconds protoInt64 `json:"discardedSeconds"`
		} `json:"reward"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/GetSession", auth.AccessToken, map[string]string{"sessionId": sessionID}, &response); err != nil {
		return Session{}, RewardSummary{}, err
	}
	if response.Session == nil || response.Session.ID != sessionID || response.Reward == nil {
		return Session{}, RewardSummary{}, errors.New("API omitted the completed session result")
	}
	return sessionFromMessage(*response.Session), RewardSummary{
		EarnedSeconds: int64(response.Reward.EarnedSeconds), SpentSeconds: int64(response.Reward.SpentSeconds),
		DiscardedSeconds: int64(response.Reward.DiscardedSeconds),
	}, nil
}

func (c *Client) AbortSession(ctx context.Context, session AuthSession, operationID, sessionID string, expectedVersion int64, endedAt time.Time) error {
	if operationID == "" || sessionID == "" || expectedVersion < 1 {
		return errors.New("中止するセッションを確認できません")
	}
	input := map[string]any{
		"operationId": operationID, "sessionId": sessionID,
		"expectedVersion": protoInt64(expectedVersion), "endedAt": endedAt.UTC().Format(time.RFC3339Nano),
		"lastSeq": protoInt64(0),
	}
	var response struct {
		Session sessionMessage `json:"session"`
	}
	if err := c.Connect(ctx, "focus.v1.FocusService/AbortSession", session.AccessToken, input, &response); err != nil {
		return err
	}
	if response.Session.ID != sessionID || strings.TrimPrefix(response.Session.Status, "SESSION_STATUS_") != "ABORTED" {
		return errors.New("APIでセッション中止を確認できませんでした")
	}
	return nil
}
