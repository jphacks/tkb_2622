package notification

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var ErrEndpointInvalid = errors.New("APNs endpoint is no longer valid")

func NewAPNsSenderFromEnv() (Sender, bool, error) {
	config := APNsConfig{
		TeamID: os.Getenv("APNS_TEAM_ID"), KeyID: os.Getenv("APNS_KEY_ID"),
		BundleID: os.Getenv("APNS_BUNDLE_ID"), AuthKeyPath: os.Getenv("APNS_AUTH_KEY_PATH"),
	}
	configured := 0
	for _, value := range []string{config.TeamID, config.KeyID, config.BundleID, config.AuthKeyPath} {
		if strings.TrimSpace(value) != "" {
			configured++
		}
	}
	if configured == 0 {
		return nil, false, nil
	}
	if configured != 4 {
		return nil, false, errors.New("APNs configuration is incomplete")
	}
	sender, err := NewAPNsSender(config)
	if err != nil {
		return nil, false, fmt.Errorf("APNs sender configuration failed: %w", err)
	}
	return sender, true, nil
}

type Sender interface {
	Send(context.Context, string, string, string) error
}

type APNsConfig struct {
	TeamID, KeyID, BundleID, AuthKeyPath string
}

type APNsSender struct {
	teamID, keyID, bundleID string
	key                     *ecdsa.PrivateKey
	client                  *http.Client
	mu                      sync.Mutex
	providerToken           string
	providerTokenExpiry     time.Time
}

func NewAPNsSender(config APNsConfig) (*APNsSender, error) {
	config.TeamID = strings.TrimSpace(config.TeamID)
	config.KeyID = strings.TrimSpace(config.KeyID)
	config.BundleID = strings.TrimSpace(config.BundleID)
	config.AuthKeyPath = strings.TrimSpace(config.AuthKeyPath)
	if config.TeamID == "" || config.KeyID == "" || config.BundleID == "" || config.AuthKeyPath == "" {
		return nil, errors.New("APNs configuration is incomplete")
	}
	data, err := os.ReadFile(config.AuthKeyPath)
	if err != nil {
		return nil, errors.New("APNs auth key could not be read")
	}
	key, err := jwt.ParseECPrivateKeyFromPEM(data)
	if err != nil {
		return nil, errors.New("APNs auth key is invalid")
	}
	return &APNsSender{
		teamID: config.TeamID, keyID: config.KeyID, bundleID: config.BundleID, key: key,
		client: &http.Client{Timeout: 8 * time.Second},
	}, nil
}

func (s *APNsSender) Send(ctx context.Context, environment, deviceToken, eventID string) error {
	endpoint := "https://api.push.apple.com"
	if environment == "development" {
		endpoint = "https://api.sandbox.push.apple.com"
	} else if environment != "production" {
		return errors.New("APNs environment is invalid")
	}
	payload, err := json.Marshal(map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{"title": "Focus Link", "body": "グループメンバーが作業を開始しました"},
			"sound": "default",
		},
		"eventId": eventID,
	})
	if err != nil {
		return errors.New("APNs payload could not be encoded")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/3/device/"+deviceToken, strings.NewReader(string(payload)))
	if err != nil {
		return errors.New("APNs request could not be created")
	}
	providerToken, err := s.jwt()
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+providerToken)
	req.Header.Set("apns-topic", s.bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-collapse-id", eventID)
	req.Header.Set("content-type", "application/json")
	response, err := s.client.Do(req)
	if err != nil {
		return errors.New("APNs delivery request failed")
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return nil
	}
	var result struct {
		Reason string `json:"reason"`
	}
	_ = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&result)
	if response.StatusCode == http.StatusGone || result.Reason == "BadDeviceToken" || result.Reason == "Unregistered" {
		return ErrEndpointInvalid
	}
	return errors.New("APNs rejected the notification")
}

func (s *APNsSender) jwt() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if time.Until(s.providerTokenExpiry) > 5*time.Minute {
		return s.providerToken, nil
	}
	now := time.Now().UTC()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{"iss": s.teamID, "iat": now.Unix()})
	token.Header["kid"] = s.keyID
	encoded, err := token.SignedString(s.key)
	if err != nil {
		return "", errors.New("APNs provider token could not be signed")
	}
	s.providerToken = encoded
	s.providerTokenExpiry = now.Add(55 * time.Minute)
	return encoded, nil
}
