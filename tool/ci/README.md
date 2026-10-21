# tool/ci

`google-services.demo.json` は **Firebaseエミュレータ専用のダミー設定**（本物の鍵は含まない）。
結合テスト（`integration_test/`）を流すときだけ `android/app/google-services.json` としてコピーして使う
（`scripts/run_e2e.sh` と `.github/workflows/ci.yml` の e2e ジョブ）。

- `project_id` が `demo-` で始まるので、Firebase SDKは本番のFirebaseへ一切接続しない
- アプリは `--dart-define=USE_FIREBASE_EMULATOR=true` のときだけエミュレータへ繋ぐ
  （`lib/services/firebase_bootstrap.dart`）。このファイルのまま本番向けにビルドしても動かない
- 本番・テスター配布のビルドでは、Firebase Consoleからダウンロードした本物の
  `google-services.json`（GitHub Secretsの `GOOGLE_SERVICES_JSON_BASE64`）を使う
