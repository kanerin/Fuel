# Fuel — 書くだけPFC管理

食べたものを文章で書く（または写真を撮る）だけで、Gemini AIが品目ごとのカロリーと
PFC（たんぱく質・脂質・炭水化物）を推定し、そのままその日の記録に追加できる
ダイエット用のAndroidアプリ。年齢・身長・体重・運動の頻度から1日の消費カロリーと
目標摂取カロリー・PFCの目標を計算し、「今日あと何をどれくらい食べてよいか」を見せる。

要件・計算式・データモデルは [`docs/requirements.md`](docs/requirements.md)、
開発ルールは [`CLAUDE.md`](CLAUDE.md)、残課題は [`docs/open-issues.md`](docs/open-issues.md)。

## 主な機能

| 画面 | できること |
|---|---|
| きょう | 摂取カロリーのリング・PFCのバー・食事区分（朝食/昼食/夕食/間食）ごとの記録。下部の入力欄に食べたものを書くとAIがPFCを推定し、確認・修正して追加。写真からの推定も可。日付の切り替え・スワイプで削除（元に戻せる） |
| 追加シート | お気に入り・最近食べたものから1タップで記録（AIを使わない）・手入力（PFCからkcalを計算・量の倍率） |
| 履歴 | 直近7日／30日の摂取カロリーの棒グラフ（目標線付き）・1日あたりの平均・PFCバランスの実際と目標の比較・日ごとの一覧 |
| 体重 | 日ごとの体重の記録・推移グラフ（目標体重の線付き）・BMI・前回比。最新の体重がプロフィールに反映され、消費カロリーの計算に使われる |
| 設定 | 1日の目安（基礎代謝量・消費カロリー・目標）・プロフィールと目標の変更・お気に入りの管理・今日のAI推定の残り回数・ログアウト・アカウント削除 |

## 技術構成

| 層 | 使っているもの |
|---|---|
| アプリ | Flutter 3.44.9（Android） |
| 認証 | Firebase Authentication（Googleログイン） |
| データ | Cloud Firestore（オフラインでも手入力・お気に入りからの記録は可能） |
| AI推定 | Cloud Functions（`asia-northeast1`）の `estimateNutrition` から Gemini API（`gemini-flash-lite-latest`、構造化出力）を呼ぶ。**APIキーはアプリに埋め込まず Secret Manager に置く** |
| 退会 | Cloud Functions の `deleteAccount` がデータ（サブコレクション含む）とAuthのユーザーを削除 |

```
lib/
├── main.dart / app.dart        # 起動・MaterialApp
├── models/                     # Nutrition / FoodItem / MealEntry / UserProfile / WeightLog
├── logic/                      # 純粋関数: 消費カロリー・目標の計算、1日・期間の集計、日付、表示形式
├── services/                   # Firestoreのリポジトリ・AI推定（Cloud Functions呼び出し）・認証・写真
├── screens/                    # 画面（ログイン・はじめに・きょう・履歴・体重・設定など）
├── widgets/                    # リング・PFCバー・グラフ・入力欄などの部品
└── theme/
functions/src/                  # Cloud Functions（estimateNutrition / deleteAccount）
firestore.rules                 # セキュリティルール（本人だけ・値の範囲の検証）
rules_test/                     # セキュリティルールのテスト（エミュレータ）
test/                           # 単体・ウィジェットテスト（lib/ と対称の場所）
```

## セットアップ

### 0. 必要なもの

- Flutter 3.44.9（`flutter --version`）
- Node.js 22・Firebase CLI（`npm install -g firebase-tools`）
- Java 21（Firebaseエミュレータ用）

### 1. Firebaseプロジェクトを作る（aimaruとは別のプロジェクトにする）

aimaruの `aimaru-7eb2e` に相乗りしないこと。`firebase deploy` でセキュリティルールを
デプロイすると**プロジェクト単位で丸ごと置き換わる**ため、同じプロジェクトだとaimaruの
ルールを消してしまう。

1. https://console.firebase.google.com → プロジェクトを追加（例: `fuel-xxxxx`）
2. **Blazeプラン（従量課金）にする**。Cloud Functions と Secret Manager に必要（無料枠内なら請求はほぼ発生しない）
3. Authentication → ログイン方法 → **Google** を有効化
4. Firestore Database → 作成（ロケーションは `asia-northeast1` 推奨。本番モードでよい。ルールは手順4でデプロイする）

### 2. Androidアプリを登録して `google-services.json` を置く

1. Firebase Console → プロジェクトの設定 → アプリを追加 → Android
   - パッケージ名: **`io.github.kanerin.fuel`**
2. **SHA-1を登録する**（未登録だとGoogleログインが失敗する）。デバッグ用は次で取得できる:
   ```bash
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
   ```
   リリース署名（App Distribution・Play Store）の鍵のSHA-1も同じ画面で追加する
3. `google-services.json` をダウンロードして `android/app/google-services.json` に置く
   （`.gitignore`済み。**コミットしない**）。`flutterfire configure` で生成してもよい
   - **Googleログインの有効化（手順1-3）とSHA-1の登録の後に**ダウンロードすること。それより前の
     ファイルにはGoogleログイン用のOAuthクライアント（`oauth_client`）が含まれず、ログインが失敗する

Dart側の `firebase_options.dart` は不要（Androidでは `google-services.json` から
生成される設定を `Firebase.initializeApp()` が読む。`lib/services/firebase_bootstrap.dart`）。

### 3. Gemini APIキーを Secret Manager に登録する

1. https://aistudio.google.com/apikey でキーを発行する
   - 課金が有効なGoogle Cloudプロジェクトで発行したキーは無料枠が使えず最初から課金になる。
     無料枠を使うなら、**課金が紐付いていない新規プロジェクト**で発行する（aimaruと同じ注意）
   - aimaruで使っているキーを使い回してもよい（1日の無料枠を両アプリで分け合うことになる）
2. 登録する（ローカルにキーを置かない）:
   ```bash
   firebase functions:secrets:set GEMINI_API_KEY --project <プロジェクトID>
   ```

### 4. ルール・インデックス・Cloud Functions をデプロイする

```bash
cd functions && npm ci && cd ..
firebase deploy --only firestore:rules,firestore:indexes,functions --project <プロジェクトID>
```

**リポジトリにコードがあるだけでは本番では動かない**（aimaruで、未デプロイのままAI機能が
動かなかった反省）。ルールや関数を変えたら、そのたびにデプロイすること。

### 5. 起動

```bash
flutter pub get
flutter run
```

## テスト

| 対象 | コマンド |
|---|---|
| Flutter（解析） | `flutter analyze` |
| Flutter（単体・ウィジェット） | `flutter test` |
| Cloud Functions（型） | `cd functions && npm run typecheck` |
| Cloud Functions（単体） | `cd functions && npm test` |
| Cloud Functions（結合、Firestore/Authエミュレータ） | `cd functions && npm run test:integration` |
| セキュリティルール（Firestoreエミュレータ） | `cd rules_test && npm ci && npm test` |

| 結合テスト（Androidエミュレータ/実機 + Firebaseエミュレータ） | `./scripts/run_e2e.sh` |

エミュレータを使うテストは `demo-fuel` というデモ用のプロジェクトIDで動く
（`demo-` で始まるIDは本番のFirebaseへ一切接続しない）。本番のデータには触れない。
結合テストは `android/app/google-services.json` を一時的にエミュレータ専用のダミー
（`tool/ci/google-services.demo.json`）へ差し替えて実行し、終わったら元に戻す。

## CI/CD

```
作業ブランチ → develop（CI） → release-stg（テスター配布） → release-prd（本番。未整備）
```

| ワークフロー | いつ | 何をする |
|---|---|---|
| `ci.yml` | `develop` へのPR・push | 下の5つのジョブ。Firebaseの秘密情報は使わない |
| `promote-to-stg.yml` | `develop` でCIが成功したとき | `release-stg` へfast-forwardで昇格し、テスター配布を起動する。**リポジトリ変数 `AUTO_PROMOTE_TO_STG=true` を登録するまでは動かない** |
| `release-stg.yml` | `release-stg` へのpush・手動 | 検査 → ルール・インデックス・Cloud Functions を本番へデプロイ → リリースAPKを App Distribution でテスターへ配布 |

### 必須チェックの設定

Settings → Rules → Rulesets → New branch ruleset で、対象を `develop`、Enforcement status を
`Active` にし、**Require status checks to pass** に次のジョブ名を登録する
（`ci.yml` の `name:` と**完全に一致**させること。実在しない名前を登録すると、CIが全部緑でも
永久にマージできなくなる——aimaruで実際に起きた）。

| ジョブ名 | 目安時間 |
|---|---|
| `Secret scan` | 1分 |
| `Flutter (analyze, format & test)` | 数分 |
| `Cloud Functions (typecheck, unit & integration)` | 数分 |
| `Security rules (Firestore)` | 数分 |
| `Integration test (Android emulator)` | 15〜25分 |

検索窓には直近で実行実績のあるチェックしか候補に出ないので、一度CIを走らせてから設定する。
あわせて **Require a pull request before merging** と **Require linear history** も入れておくとよい
（`promote-to-stg.yml` は `--ff-only` 相当で昇格するため、`develop` が直線である前提と合う）。

### テスター配布（App Distribution）

1. Firebase Console → App Distribution を開始し、テスター（自分のGoogleアカウントなど）を追加する
2. リリース署名鍵を作る（**紛失するとPlay Storeに出したアプリを二度と更新できない**。パスワードマネージャーなどに保管する）
   ```bash
   keytool -genkey -v -keystore release.keystore -alias fuel -keyalg RSA -keysize 2048 -validity 10000
   ```
   この鍵のSHA-1もFirebase Console（Androidアプリ → フィンガープリント）に登録する（しないとGoogleログインが失敗する）
3. Google Cloud Console → IAM でデプロイ・配布用のサービスアカウントを作り、次のロールを付けてJSONキーを発行する
   （aimaruで実際にデプロイが通った組み合わせ）:
   `roles/firebaseappdistro.admin`・`roles/firebaserules.admin`・`roles/datastore.indexAdmin`・
   `roles/cloudfunctions.developer`・`roles/iam.serviceAccountUser`・`roles/secretmanager.secretAccessor`・
   `roles/cloudbuild.builds.editor`
4. Settings → Secrets and variables → Actions に次のSecretsを登録する（値はコミットしない）

| Secret名 | 中身 |
|---|---|
| `GOOGLE_SERVICES_JSON_BASE64` | `base64 -i android/app/google-services.json \| tr -d '\n'` |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | 手順3のサービスアカウントのJSON（そのまま） |
| `FIREBASE_PROJECT_ID` | FirebaseのプロジェクトID |
| `FIREBASE_ANDROID_APP_ID` | Firebase Console → プロジェクトの設定 → Androidアプリの「アプリID」（`1:...:android:...`） |
| `APP_DISTRIBUTION_TESTERS` | 通知するテスターのメール（カンマ区切り） |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i release.keystore \| tr -d '\n'` |
| `ANDROID_KEYSTORE_PASSWORD` | 署名鍵のストアパスワード |
| `ANDROID_KEY_ALIAS` | 署名鍵のエイリアス（例: `fuel`） |
| `ANDROID_KEY_PASSWORD` | 署名鍵のキーパスワード |

5. 最初の配布: `release-stg` ブランチを `develop` から作ってpushする（`git push origin develop:release-stg`）か、
   Actions → Distribute to testers を手動実行する。Secretsが足りなければ最初のステップで何が足りないかを出して止まる
6. 以後 `develop` のCIが通るたびに自動で配布したい場合は、Settings → Secrets and variables → Actions → **Variables** に
   `AUTO_PROMOTE_TO_STG` = `true` を登録する

配布のたびに、前回配布した地点からのコミット（`feat:`→新機能、`fix:`→修正）がリリースノートになり、
バージョン名も自動で上がる（`feat:` があればマイナー、それ以外はパッチ。aimaruと同じ仕組み）。

## 注意

AIの推定値・目標値は一般的な目安で、正確さを保証するものではない。医療上の助言ではない。
