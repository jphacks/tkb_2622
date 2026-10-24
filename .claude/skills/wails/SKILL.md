---
name: wails
description: >-
    Wails は、Web フロントエンドを使ってデスクトップアプリケーションを構築する Go フレームワークです。
    バックエンドは Go、UI は任意の Web フレームワーク（React、Vue、Svelte）で実装し、
    OS の WebView で描画します。Go メソッドは、自動生成された TypeScript バインディングを通じて
    JavaScript から呼び出します。Go でのデスクトップアプリ開発、Wails プロジェクトの雛形作成、
    Go メソッドとフロントエンドの接続、ネイティブメニュー・ダイアログ・イベントの追加、
    Windows 向けクロスコンパイル、Wails v2 と v3 ベータ版の選択を依頼されたときに使用します。
    安定版の Wails v2 を対象とします。
license: Apache-2.0
compatibility: "Wails v2.16、Go 1.25 以上、Node.js 15 以上。Linux: gcc、GTK 3、WebKit2GTK。Windows: WebView2 ランタイム。macOS: Xcode コマンドラインツール"
metadata:
    author: terminal-skills
    version: 1.1.0
    category: development
    tags: ["desktop", "go", "golang", "cross-platform", "native"]
    repository: https://github.com/wailsapp/wails
---

# Wails — Go と Web フロントエンドによるデスクトップアプリ

## 概要

Wails は、バックエンドを Go、フロントエンドを任意の Web フレームワーク（React、Vue、Svelte、Preact、Lit）で実装する軽量なデスクトップアプリを構築します。ブラウザーを同梱せず、システムの WebView で表示します。エクスポートされた Go メソッドは、生成された TypeScript 型を持つ、Promise を返す JavaScript 関数になります。

**このスキルは安定版の Wails v2 を説明します**（v2.16.0、2026 年 9 月）。Wails v3 はベータ版（v3.0.0-beta.27）で、CLI、インポートパス、API が異なる再実装です。「手順」の最後に概要を記載しています。

## 手順

### プロジェクトのセットアップ

```bash
# 前提条件: Go と npm。v2.16.0 の go.mod は Go 1.25 を要求します（インストールページの記載はまだ 1.21 以上です）
go install github.com/wailsapp/wails/v2/cmd/wails@latest
export PATH="$PATH:$(go env GOPATH)/bin"
wails doctor                           # プラットフォームごとに不足しているシステム依存関係を表示
wails init -n fieldnotes -t react-ts   # テンプレート一覧: wails init -l（svelte、vue、preact、lit、vanilla。それぞれ -ts 版あり）
cd fieldnotes
wails dev                              # ライブリロード対応のアプリウィンドウ。http://localhost:34115 でも配信
wails build                            # 本番用バイナリを build/bin/ に出力
wails build -platform windows/amd64    # その他のターゲット: darwin/universal、linux/arm64 など
wails build -platform windows/amd64 -nsis   # Windows インストーラー（ビルドマシンに makensis が必要）
```

プラットフォームの依存関係: macOS では `xcode-select --install`、Windows では WebView2 ランタイム（`wails doctor` で確認）、Linux では gcc、GTK 3、WebKit2GTK が必要です。WebKit2GTK 4.0 を提供しないディストリビューション（Ubuntu 24.04 など）では、`libwebkit2gtk-4.1-dev` が必要で、`wails dev` と `wails build` の実行時に毎回ビルドタグ `-tags webkit2_41` を指定します（例 2）。

### Go バックエンド

```go
// app.go — バインドされた構造体のエクスポート済みメソッドは JavaScript から呼び出せます
package main

import (
	"context"
	"database/sql"
	"log"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite" // 純粋な Go ドライバー: 追加の CGO が不要で、クロスコンパイルが容易
)

type App struct {
	ctx context.Context
	db  *sql.DB
}

func NewApp() *App { return &App{} }

// startup はすべてのランタイム呼び出しに必要なコンテキストを受け取ります（ランタイム呼び出しは OnDomReady 以降で動作）
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	dir, _ := os.UserConfigDir() // ~/.config, ~/Library/Application Support, %AppData%
	dbPath := filepath.Join(dir, "fieldnotes", "notes.db")
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
		log.Fatal(err)
	}
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	if _, err = db.Exec(`CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT,
		title TEXT NOT NULL, content TEXT NOT NULL DEFAULT '', updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)`); err != nil {
		log.Fatal(err)
	}
	a.db = db
}

// Note は frontend/wailsjs/go/models.ts に TypeScript クラスとして生成されます
type Note struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	UpdatedAt string `json:"updatedAt"`
}

// 最後の戻り値が error でエラーを返すと、JavaScript の Promise が拒否されます
func (a *App) GetNotes() ([]Note, error) {
	rows, err := a.db.Query("SELECT id, title, content, updated_at FROM notes ORDER BY updated_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	notes := []Note{} // nil ではないため、フロントエンドは null ではなく [] を受け取ります
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.Title, &n.Content, &n.UpdatedAt); err != nil {
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

func (a *App) CreateNote(title string) (*Note, error) {
	res, err := a.db.Exec("INSERT INTO notes (title) VALUES (?)", title)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &Note{ID: id, Title: title}, nil
}

func (a *App) UpdateNote(id int64, title, content string) error {
	_, err := a.db.Exec("UPDATE notes SET title = ?, content = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", title, content, id)
	return err
}
```

### フロントエンド（React + TypeScript）

```tsx
// frontend/src/App.tsx — frontend/wailsjs/ は `wails dev` と `wails build` によって再生成されます
import { useEffect, useState } from "react";
import { CreateNote, GetNotes, UpdateNote } from "../wailsjs/go/main/App";
import { main } from "../wailsjs/go/models";
import { EventsOn } from "../wailsjs/runtime/runtime";

export default function App() {
    const [notes, setNotes] = useState<main.Note[]>([]);
    const [selected, setSelected] = useState<main.Note | null>(null);
    const load = () => GetNotes().then(setNotes); // Go の []Note は main.Note[] として届きます
    async function create() {
        setSelected(await CreateNote("Untitled")); // Go の *Note は main.Note として届きます
        load();
    }

    useEffect(() => {
        load();
        return EventsOn("menu:new-note", create); // EventsOn は自身の購読解除関数を返します
    }, []);
    async function save(note: main.Note, content: string) {
        await UpdateNote(note.id, note.title, content); // Go のエラーによって Promise が拒否されます
        load();
    }

    return (
        <div className="app">
            <aside>
                <button onClick={create}>+ New Note</button>
                {notes.map((note) => (
                    <div key={note.id} onClick={() => setSelected(note)}>
                        <strong>{note.title}</strong>{" "}
                        <small>{note.updatedAt}</small>
                    </div>
                ))}
            </aside>
            {selected && (
                <textarea
                    defaultValue={selected.content}
                    onBlur={(e) => save(selected, e.target.value)}
                />
            )}
        </div>
    );
}
```

### システムトレイとメニュー

Wails v2 にはアプリケーションメニューがありますが、**システムトレイ API はありません**。トレイアイコンには Wails v3 またはサードパーティーの Go パッケージが必要です。

```go
// main.go — ウィンドウ設定、アプリケーションメニュー、バインディング
package main

import (
	"embed"
	"log"
	goruntime "runtime"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/menu/keys"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/runtime"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()

	appMenu := menu.NewMenu()
	if goruntime.GOOS == "darwin" {
		appMenu.Append(menu.AppMenu()) // macOS では最初に追加する必要があります
	}
	fileMenu := appMenu.AddSubmenu("File")
	fileMenu.AddText("New Note", keys.CmdOrCtrl("n"), func(_ *menu.CallbackData) {
		runtime.EventsEmit(app.ctx, "menu:new-note") // Go → フロントエンド
	})
	fileMenu.AddSeparator()
	fileMenu.AddText("Quit", keys.CmdOrCtrl("q"), func(_ *menu.CallbackData) { runtime.Quit(app.ctx) })
	if goruntime.GOOS == "darwin" {
		appMenu.Append(menu.EditMenu()) // macOS で Cmd+C、Cmd+V、Cmd+Z を有効にします
	}

	err := wails.Run(&options.App{
		Title:       "Field Notes",
		Width:       1024,
		Height:      768,
		AssetServer: &assetserver.Options{Assets: assets},
		Menu:        appMenu,
		OnStartup:   app.startup,
		Bind:        []interface{}{app},
	})
	if err != nil {
		log.Fatal(err)
	}
}
```

### Wails v3（ベータ版）

`go install github.com/wailsapp/wails/v3/cmd/wails3@latest` でインストールします。コマンドは `wails3 init -n fieldnotes`、`wails3 dev`、`wails3 build` で、`Taskfile.yml` によって実行されます。`wails.Run(&options.App{Bind: ...})` は `application.New(application.Options{Services: ...})` と明示的なウィンドウ作成に変わります。バインディングは `frontend/bindings/` に生成され、JavaScript ランタイムは `@wailsio/runtime` パッケージとなり、複数ウィンドウとシステムトレイが組み込まれています。上記の v2 コードは、どれも変更せずに v3 でコンパイルすることはできません。移行ガイドは `https://v3.wails.io` にあります。現時点で出荷するものには v2 を使用し、v3 の機能が必要でベータ版の修正に対応できるリリースでは v3 を使用します。

## 例

### 例 1: ネイティブの保存ダイアログからノートをエクスポートする

**ユーザーの依頼:** 「選択したノートを Markdown ファイルとして保存し、保存先を表示するエクスポートボタンを追加してください。」

```go
// app.go — "github.com/wailsapp/wails/v2/pkg/runtime" をインポートに追加してから、以下を追加:
func (a *App) ExportNote(id int64) (string, error) {
	var n Note
	if err := a.db.QueryRow("SELECT title, content FROM notes WHERE id = ?", id).Scan(&n.Title, &n.Content); err != nil {
		return "", err
	}
	path, err := runtime.SaveFileDialog(a.ctx, runtime.SaveDialogOptions{
		Title:           "Export note",
		DefaultFilename: n.Title + ".md",
		Filters:         []runtime.FileFilter{{DisplayName: "Markdown (*.md)", Pattern: "*.md"}},
	})
	if err != nil || path == "" {
		return "", err
	}
	if err := os.WriteFile(path, []byte("# "+n.Title+"\n\n"+n.Content+"\n"), 0o644); err != nil {
		return "", err
	}
	runtime.EventsEmit(a.ctx, "note:exported", path)
	return path, nil
}
```

```tsx
// App.tsx — "../wailsjs/go/main/App" から ExportNote をインポートし、コンポーネント内に以下を追加:
const [status, setStatus] = useState("");
useEffect(
    () =>
        EventsOn("note:exported", (path: string) => setStatus(`Saved ${path}`)),
    [],
);
// JSX 内の textarea の隣に以下を追加:
{
    selected && (
        <button onClick={() => ExportNote(selected.id)}>Export…</button>
    );
}
<footer>{status}</footer>;
```

**結果:** 次回の `wails dev` または `wails build` でバインディングが再生成され、`frontend/wailsjs/go/main/App.d.ts` に `export function ExportNote(arg1:number):Promise<string>;` が追加されます。Export をクリックするとシステムの保存ダイアログが開き、保存後にフッターに保存先のパスが表示されます。

### 例 2: Ubuntu 24.04 でのビルドと Windows 向けクロスコンパイル

**ユーザーの依頼:** 「Ubuntu 24.04 で wails doctor が libwebkit の不足を報告します。このマシンで Windows 用の .exe も作成する必要があります。」

```bash
sudo apt install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
wails build -tags webkit2_41              # build/bin/fieldnotes
wails build -platform windows/amd64       # build/bin/fieldnotes.exe、Windows マシンは不要
```

**結果:** Windows 向けビルドは `Built '.../fieldnotes/build/bin/fieldnotes.exe' in 11.265s.` で完了します（SQLite ドライバー込みで約 15 MB）。24.04 上の `wails doctor` は、そのリリースでは提供されていない `libwebkit2gtk-4.0-dev` を依然として提案します。Linux 上で `wails build -platform darwin/arm64` を実行すると、`Crosscompiling to Mac not currently supported.` で停止します。macOS 向けビルドには Mac または macOS の CI ランナーが必要です。

## ガイドライン

1. **バックエンドは Go、UI は Web** — ビジネスロジック、ファイル入出力、データベースアクセスは Go に置き、描画はフロントエンドで行います
2. **自動生成バインディング** — `frontend/wailsjs/` は編集しないでください。`wails dev` と `wails build` のたびに書き換えられます
3. **アセットの埋め込み** — `//go:embed all:frontend/dist` はフロントエンドをバイナリに組み込み、単一ファイルで配布できるようにします
4. **非同期処理にはイベントを使用** — `runtime.EventsEmit` は進捗やバックグラウンド処理の結果をフロントエンドへ送信します。`EventsOn` が返す関数を保持し、アンマウント時に呼び出してください
5. **ネイティブダイアログ** — HTML モーダルではなく、ランタイムのダイアログ（`OpenFileDialog`、`SaveFileDialog`、`MessageDialog`）を使用します
6. **ローカルデータには SQLite** — データベースは実行ファイルの隣ではなく、`os.UserConfigDir()` の配下に保存します。純粋な Go ドライバーを使用すると、クロスコンパイルを維持できます
7. **コンテキストは `OnStartup` から取得** — そこで保存しますが、ウィンドウ、ダイアログ、イベントの関数は `OnDomReady` 以降でのみ呼び出してください。ドキュメントでは `OnStartup` 内のランタイム動作は保証されていません
8. **クロスコンパイルの対応は限定的** — Windows 向けは Linux と macOS からビルドでき、macOS 向けは macOS 上でのみビルドできます。Linux 向けには GTK と WebKit のヘッダーを備えた Linux が必要です。OS ごとに CI ランナーを用意してください
9. **バインドされたメソッドは API として公開される** — WebView 内のあらゆるものから呼び出せるため、引数を検証し、信頼できないリモートページをアプリウィンドウに読み込まないでください
