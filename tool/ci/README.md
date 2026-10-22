# tool/ci

`google-services.demo.json` は **Firebaseエミュレータ専用のダミー設定**（本物の鍵は含まない）。
結合テスト（`integration_test/`）を流すときだけ `android/app/google-services.json` としてコピーして使う
（`scripts/run_e2e.sh` と `.github/workflows/ci.yml` の e2e ジョブ）。

- `project_id` は実在しない `demo-fuel`、APIキーもダミーなので、どこへ繋いでも本番のデータには
  触れられない（Firebaseエミュレータも `demo-` で始まるIDを「本番に一切接続しないデモ用」として扱う）
- アプリは `--dart-define=USE_FIREBASE_EMULATOR=true` のときだけエミュレータへ繋ぐ
  （`lib/services/firebase_bootstrap.dart`）。このファイルのまま本番向けにビルドしても動かない
- **APIキーはダミーでも「`A` で始まる39文字」の形にしておくこと。** Cloud FunctionsのAndroid SDKは
  呼び出しのたびにInstance ID（firebase-iid）のトークンを取りに行き、そこでAPIキーの形式
  （`\AA[\w-]{38}\z`）を確かめて、合わなければ関数を呼ぶ前に例外を投げる。以前は `demo-key` に
  していたため、認証・Firestoreは動くのにAI推定だけが関数まで届かなかった。`AIza` で始めると
  秘密情報スキャン（gitleaks）が本物のGoogle APIキーとして検知するので、`AIza` では始めない
- 本番・テスター配布のビルドでは、Firebase Consoleからダウンロードした本物の
  `google-services.json`（GitHub Secretsの `GOOGLE_SERVICES_JSON_BASE64`）を使う
