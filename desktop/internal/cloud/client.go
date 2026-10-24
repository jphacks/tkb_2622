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
		Code              string `json:"code"`
		Message           string `json:"message"`
		MessageShort      string `json:"msg"`
		ErrorDescription  string `json:"error_description"`
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

func (c *Client) RegisterPCDevice(ctx context.Context, session AuthSession, platform, name string) error {
	var response struct {
		Device json.RawMessage `json:"device"`
	}
	platformName := map[string]string{"MACOS": "PLATFORM_MACOS", "WINDOWS": "PLATFORM_WINDOWS"}[platform]
	if platformName == "" {
		return errors.New("unsupported PC platform")
	}
	input := map[string]string{
		"operationId": session.RegisterOperationID, "registrationId": session.RegistrationID,
		"platform": platformName, "name": name,
	}
	return c.Connect(ctx, "identity.v1.IdentityService/RegisterDevice", session.AccessToken, input, &response)
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
