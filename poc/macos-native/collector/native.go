// Package collector はmacOS補助プログラムを呼び出す取得Adapterを提供する。
package collector

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"focuspocket/macos-native/model"
)

type Native struct {
	Helper  string
	Timeout time.Duration
}

func New(helper string, timeout time.Duration) (*Native, error) {
	if timeout <= 0 {
		return nil, errors.New("timeoutは正の値を指定してください")
	}
	path, err := filepath.Abs(helper)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("native/build.shで補助プログラムをビルドしてください: %w", err)
	}
	if info.IsDir() || info.Mode()&0111 == 0 {
		return nil, errors.New("helperに実行可能なファイルを指定してください")
	}
	return &Native{Helper: path, Timeout: timeout}, nil
}

type boundedBuffer struct{ bytes.Buffer }

func (b *boundedBuffer) Write(data []byte) (int, error) {
	if b.Len()+len(data) > 65536 {
		return 0, errors.New("helper_output_too_large")
	}
	return b.Buffer.Write(data)
}

func (n *Native) Snapshot(ctx context.Context) (model.Snapshot, error) {
	requestCtx, cancel := context.WithTimeout(ctx, n.Timeout)
	defer cancel()
	command := exec.CommandContext(requestCtx, n.Helper, "--once")
	var output boundedBuffer
	command.Stdout = &output
	// エラー本文にはURL等が含まれる可能性があるため、外部プロセスの標準エラーは公開しない。
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		if requestCtx.Err() != nil {
			return model.Snapshot{}, fmt.Errorf("native_helper_timeout_or_cancelled: %w", requestCtx.Err())
		}
		return model.Snapshot{}, fmt.Errorf("native_helper_failed: %w", err)
	}
	received := time.Now().UTC()
	decoder := json.NewDecoder(bytes.NewReader(output.Bytes()))
	decoder.DisallowUnknownFields()
	var snapshot model.Snapshot
	if err := decoder.Decode(&snapshot); err != nil {
		return model.Snapshot{}, errors.New("native_helper_invalid_json")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return model.Snapshot{}, errors.New("native_helper_multiple_or_trailing_json")
	}
	if snapshot.SchemaVersion != model.SchemaVersion || snapshot.Source != "macos-native" {
		return model.Snapshot{}, errors.New("native_helper_unsupported_schema_or_source")
	}
	if snapshot.ObservedAt.IsZero() || snapshot.SampleStartedAt.IsZero() {
		return model.Snapshot{}, errors.New("native_helper_missing_timestamp")
	}
	snapshot.ReceivedAt = received
	return snapshot, nil
}
