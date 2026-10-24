# Focus Link（フォーカスリンク）

[![IMAGE ALT TEXT HERE](https://jphacks.com/wp-content/uploads/2026/07/IMG_5316.png)](https://www.youtube.com/watch?v=piaNsc6ilBI)

<!-- TODO: サムネイル画像とデモ動画のURLを差し替える -->

**PCでの頑張りを，スマホの自由時間に変える．**

## 製品概要
### 背景(製品開発のきっかけ、課題等）
PCでレポートや研究を進めたいのに，ついスマホを開いてしまい，作業を**始められない・続かない・休憩から戻れない**．既存のアプリブロックは「スマホを使わせない」ことが中心で，作業を始めて続ける動機にはなりにくいと考えました．そこで，娯楽の時間を先に与えるのではなく，**PCで作業して獲得する**仕組みをつくりました．

### 製品説明（具体的な製品の説明）
デスクトップアプリ（macOS / Windows）・iPhoneアプリ・APIサーバーからなるアプリです．

1. PCで作業を開始すると，iPhoneのSNS・動画アプリが制限される
2. PCで使っているアプリやサイトから，作業と脱線を自動で判定する
3. 作業時間に応じて報酬時間がたまる（現行ルールは作業3分につき1分）
4. 作業を一時停止すると，たまった時間でiPhoneの制限を一時解除できる
5. PCで作業を再開すると，iPhoneは再び制限される

### 特長
#### 1. PCの作業がスマホの利用時間になる
デスクトップでの作業行動を根拠に，iPhoneの利用権を獲得・消費する端末横断型の報酬ループです．

#### 2. 根拠のある作業判定
前面アプリ・閲覧ドメイン・入力の有無から作業時間を5つに分類し，判定できない時間は報酬に含めません．結果画面で内訳と根拠を確認できます．

#### 3. 使ったぶんだけ減り，戻ればすぐ制限
報酬は制限対象アプリを実際に使った時間だけ消費します．作業を再開すると利用枠の残りは消え，休憩が長引きません．

### 解決出来ること
スマホが制限された状態から始まり，作業すればスマホ時間が手に入るため，**作業への着手・継続・休憩からの復帰**を後押しします．作業と脱線の内訳から，自分の集中を振り返ることもできます．

### 今後の展望
- iPhoneの制限・利用時間計測の実機での安定化
- Windows版の計測とタスクトレイ常駐
- APNsによるプッシュ通知，グループの作業状態を表示するウィジェット
- クラウド（Cloud Run / Cloudflare / Supabase）へのデプロイと，報酬ルールのユーザーテスト

### 注力したこと（こだわり等）
* **プライバシーを守る計測**：macOS標準APIで計測を自作し，URL全体・ページタイトル・入力内容・画面は保存も送信もしない
* **報酬を二重に付与・消費しない設計**：操作IDによる冪等な処理と台帳で，再送や通信失敗でも残高が狂わない
* **1つのコードでMacとWindowsに対応**：Wails v2で画面・状態・API接続を共通化

## 開発技術
### 活用した技術
#### API・データ
* Supabase Auth（メールOTP） / Supabase PostgreSQL
* Apple Screen Time API（Family Controls / Managed Settings / Device Activity）
* macOS API（NSWorkspace / CGEventSource / Apple Events）

#### フレームワーク・ライブラリ・モジュール
* バックエンド：Go，Connect RPC，Protocol Buffers / Buf，sqlc，goose
* デスクトップ：Wails v2，React，TypeScript，Vite，Swift
* iPhone：Swift，SwiftUI，supabase-swift
* インフラ：Docker，Terraform，Google Cloud Run，Cloudflare Workers

#### デバイス
* Mac / Windows PC
* iPhone

### 独自技術
#### ハッカソンで開発した独自機能・技術
* **macOSネイティブの作業計測と5分類評価**：[poc/macos-native/](poc/macos-native/)，[desktop/internal/evaluation/](desktop/internal/evaluation/)（commit [cdd0f6c](https://github.com/jphacks/tkb_2622/commit/cdd0f6c)）
* **作業セッションと報酬の冪等な同期**：[backend/internal/workflow/](backend/internal/workflow/)，[backend/internal/reward/](backend/internal/reward/)（commit [5501ae6](https://github.com/jphacks/tkb_2622/commit/5501ae6)）
* **iPhoneの制限と実利用時間による消費**：[mobile/DeviceActivityMonitorExtension/](mobile/DeviceActivityMonitorExtension/)（commit [65d5d79](https://github.com/jphacks/tkb_2622/commit/65d5d79)）

設計資料は [INDEX.md](INDEX.md)，起動手順は各ディレクトリのREADMEを参照してください．
