# Focus Link

![Focus Link：PCの頑張りを、スマホ時間に。](docs/images/focus-link-hero.png)

## 製品概要

### 背景(製品開発のきっかけ、課題等）

### 製品説明（具体的な製品の説明）

### 特長

#### 1. 特長1

#### 2. 特長2

#### 3. 特長3

### 解決出来ること

### 今後の展望

- ユーザーの集中しているかどうかを，ユーザーの自己評価を使って，学習の材料に使い，最適化を行うプロセスに組み込む．
- 習慣化に合わせて報酬の難易度を自動で調整するようにする．理由としては，条件が固定のままだと，慣れて効果が薄れる可能性がある．
- 実際の作業のデータと紐づけられるようにする．理由としては，いくら手を動かしていても実際に作業が進んでいるかの評価には伝わらないので，実際の作業との照らし合わせにより，よりユーザーの集中度合いを測定することができる．

### 注力したこと（こだわり等）

#### アイデア面

- 報酬設計の部分をスマホ内の生き物を育てるという設定にするのではなく，スマホの利用時間にすることで，物理的にユーザーの行動を制限することを可能にした．（人はこれからもスマホに依存してしまう傾向が続いていく）

#### 技術面

- バックエンド側を**モジューラーモノリス×クリーンアーキテクチャーを採用することで，将来のマイクロサービス化まで視野に入れた構成**
- バックエンドで型安全なProtocol Bufferを使用
- インフラでは，デスクトップやモバイルアプリから直で，アプリケーションサーバーにつなげずにProxy経由で，WAFやレートリミッターなどを設定して，セキュリティ面の対策を実施
- デスクトップアプリでは，UIを軽量かつモダンなUIにするために，React×Wails　v2を用いた．

## 開発技術
(アーキテクチャー図)[./docs/graph/tkb_architecture.png]

### 活用した技術

#### API・データ

- Supabase Auth／Supabase PostgreSQL
- Connect RPC（Protocol Buffers / Bufで定義したAPI）
- Apple Screen Time API（FamilyControls・ManagedSettings・DeviceActivity）による娯楽アプリの制限・一時解除
- Apple Push Notification service（APNs）によるグループの作業開始通知
- Google Cloud Run／Artifact Registry／Secret Manager，Cloudflare Workers，Terraform，GitHub Actions

#### フレームワーク・ライブラリ・モジュール

- バックエンド：Go，connect-go，pgx，sqlc，goose，golang-jwt
- デスクトップ：Wails v2，React 19，TypeScript，Vite，99designs/keyring（macOS Keychain／Windows資格情報ストア）
- iPhone：Swift / SwiftUI，Supabase Swift SDK，WidgetKit

#### デバイス

- macOS・Windows（デスクトップアプリ：作業の設定・計測・結果表示）
- iPhone（報酬時間の利用・娯楽アプリの利用制限・ウィジェット）

### 独自技術

#### ハッカソンで開発した独自機能・技術

- 独自で開発したものの内容をこちらに記載してください
- 特に力を入れた部分をファイルリンク、またはcommit_idを記載してください。
