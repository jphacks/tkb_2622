package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"focuspocket/macos-native/analysis"
	"focuspocket/macos-native/collector"
	"focuspocket/macos-native/model"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "エラー:", err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		return errors.New("check / snapshot / record / replay を指定してください（各コマンド -h）")
	}
	name := args[0]
	if name != "check" && name != "snapshot" && name != "record" && name != "replay" {
		return errors.New("未対応のコマンドです")
	}
	flags := flag.NewFlagSet(name, flag.ContinueOnError)
	helper := flags.String("helper", "bin/native-collector", "macOS補助プログラムのパス")
	timeout := flags.Duration("timeout", 8*time.Second, "補助プログラムの呼出し上限（権限ダイアログ待機を含む）")
	duration := flags.Duration("duration", time.Minute, "recordの計測時間")
	poll := flags.Duration("poll", time.Second, "recordの取得間隔")
	out := flags.String("out", "", "新規保存ディレクトリ。省略すると標準出力へ分析JSON")
	input := flags.String("input", "testdata/sample.json", "replay入力Capture JSON")
	if err := flags.Parse(args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("位置引数は指定できません")
	}
	if *timeout <= 0 || *duration <= 0 || *poll <= 0 {
		return errors.New("timeout/duration/pollは正の値を指定してください")
	}
	if *out != "" {
		if _, err := os.Stat(*out); err == nil {
			return errors.New("出力先は既に存在します。別の--outを指定してください")
		} else if !os.IsNotExist(err) {
			return err
		}
	}
	var capture model.Capture
	if name == "replay" {
		file, err := os.Open(*input)
		if err != nil {
			return err
		}
		defer file.Close()
		data, readErr := io.ReadAll(io.LimitReader(file, 32*1024*1024+1))
		if readErr != nil {
			return readErr
		}
		if len(data) > 32*1024*1024 {
			return errors.New("Captureは32MiB以下にしてください")
		}
		decoder := json.NewDecoder(bytes.NewReader(data))
		decoder.DisallowUnknownFields()
		if err = decoder.Decode(&capture); err != nil {
			return errors.New("Capture JSONを読めません（schemaと容量32MiBを確認）")
		}
		var trailing any
		if err = decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
			return errors.New("Captureに余分なJSONがあります")
		}
	} else {
		native, err := collector.New(*helper, *timeout)
		if err != nil {
			return err
		}
		if name == "record" {
			capture = record(native, *duration, *poll)
		} else {
			capture = model.Capture{SchemaVersion: model.SchemaVersion, Source: "macos-native", StartAt: time.Now().UTC(), PollSeconds: poll.Seconds(), Snapshots: []model.Snapshot{}, Errors: []model.Failure{}}
			snapshot, err := native.Snapshot(context.Background())
			capture.EndAt = time.Now().UTC()
			if err != nil {
				capture.Errors = append(capture.Errors, model.Failure{ReceivedAt: capture.EndAt, Reason: err.Error()})
			} else {
				capture.Snapshots = append(capture.Snapshots, snapshot)
			}
			if name == "check" {
				if err != nil {
					return err
				}
				safe := analysis.Sanitize(capture)
				return printJSON(safe.Snapshots[0])
			}
		}
	}
	if capture.SchemaVersion != model.SchemaVersion || capture.Source != "macos-native" {
		return errors.New("schema_versionまたはsourceが未対応です")
	}
	if capture.StartAt.IsZero() || !capture.StartAt.Before(capture.EndAt) {
		return errors.New("計測区間が不正です")
	}
	capture = analysis.Sanitize(capture)
	result := analysis.Analyze(capture)
	for _, failure := range capture.Errors {
		fmt.Fprintln(os.Stderr, "取得失敗:", failure.Reason)
	}
	var acquisitionError error
	if len(capture.Snapshots) == 0 && (len(capture.Errors) > 0 || name != "replay") {
		acquisitionError = errors.New("観測を取得できませんでした。失敗情報は保存します")
	}
	if *out == "" {
		return errors.Join(printJSON(result), acquisitionError)
	}
	if err := os.MkdirAll(filepath.Dir(*out), 0700); err != nil {
		return err
	}
	if err := os.Mkdir(*out, 0700); err != nil {
		return err
	}
	for _, item := range []struct {
		name  string
		value any
	}{{"capture.json", capture}, {"events.json", result.Events}, {"analysis.json", result}} {
		if err := saveJSON(filepath.Join(*out, item.name), item.value); err != nil {
			return err
		}
	}
	fmt.Fprintln(os.Stderr, "保存先:", *out, "（サンプリングによる推定。集中スコアではありません）")
	return errors.Join(printJSON(result.Report), acquisitionError)
}
func printJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}
func saveJSON(path string, value any) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	writeErr := encoder.Encode(value)
	return errors.Join(writeErr, file.Close())
}
func record(native *collector.Native, duration, poll time.Duration) model.Capture {
	start := time.Now().UTC()
	end := start.Add(duration)
	capture := model.Capture{SchemaVersion: model.SchemaVersion, Source: "macos-native", StartAt: start, PollSeconds: poll.Seconds(), Snapshots: []model.Snapshot{}, Errors: []model.Failure{}}
	signalCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	deadlineCtx, cancel := context.WithDeadline(signalCtx, end)
	defer cancel()
	collect := func(ctx context.Context) {
		snapshot, err := native.Snapshot(ctx)
		if err != nil {
			// 通常終了やCtrl-Cによる進行中観測の中断は取得障害と混同しない。
			if ctx.Err() != nil {
				return
			}
			capture.Errors = append(capture.Errors, model.Failure{ReceivedAt: time.Now().UTC(), Reason: err.Error()})
			return
		}
		capture.Snapshots = append(capture.Snapshots, snapshot)
	}
	fmt.Fprintln(os.Stderr, "計測中。Ctrl-Cで終了して保存します。オートメーション許可が必要な場合はmacOSで許可してください。")
	ticker := time.NewTicker(poll)
	defer ticker.Stop()
	collect(deadlineCtx)
	for deadlineCtx.Err() == nil {
		select {
		case <-deadlineCtx.Done():
		case <-ticker.C:
			collect(deadlineCtx)
		}
	}
	capture.EndAt = time.Now().UTC()
	if capture.EndAt.After(end) {
		capture.EndAt = end
	}
	// 自前観測は過去の状態を再取得できない。終了後の値を過去へ補完しない。
	return capture
}
