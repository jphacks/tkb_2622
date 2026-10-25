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
### 注力したこと（こだわり等）
* 
* 

## 開発技術
### 活用した技術
#### API・データ
* Supabase Auth／Supabase PostgreSQL（料金削減目的）
* Connect RPC（Protocol Buffers / Bufで定義したAPI）
* Apple Screen Time API（FamilyControls・ManagedSettings・DeviceActivity）による娯楽アプリの制限・一時解除
* Apple Push Notification service（APNs）によるグループの作業開始通知
* Google Cloud Run／Artifact Registry／Secret Manager，Cloudflare Workers，Terraform，GitHub Actions

#### フレームワーク・ライブラリ・モジュール
* バックエンド：Go，connect-go，pgx，sqlc，goose，golang-jwt
* デスクトップ：Wails v22，React 19，TypeScript，Vite，99designs/keyring（macOS Keychain／Windows資格情報ストア）
* iPhone：Swift / SwiftUI，Supabase Swift SDK，WidgetKit

#### デバイス
* macOS・Windows（デスクトップアプリ：作業の設定・計測・結果表示）
* iPhone（報酬時間の利用・娯楽アプリの利用制限・ウィジェット）

### 独自技術
#### ハッカソンで開発した独自機能・技術
* 独自で開発したものの内容をこちらに記載してください
* 特に力を入れた部分をファイルリンク、またはcommit_idを記載してください。
