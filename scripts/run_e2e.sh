#!/usr/bin/env bash
# 結合テスト（integration_test/）をローカルで実行するスクリプト。
#
# 実機/エミュレータ上でアプリを本当に起動して操作する。Firebaseの接続先は
# ローカルのエミュレータ（プロジェクトID demo-fuel）なので、本番のデータには触れない。
#
# 事前準備:
#   1. Androidエミュレータ（または実機）を1台つないでおく
#   2. firebase-tools と Java 21 を入れておく（npm install -g firebase-tools）
#
# 使い方:
#   ./scripts/run_e2e.sh                                       # 全部
#   ./scripts/run_e2e.sh integration_test/meal_flow_test.dart  # 1ファイルだけ
#
# 注意: android/app/google-services.json をエミュレータ用のダミーに一時的に
# 差し替え、終了時に元へ戻す（本物の設定でビルドするとエミュレータの
# プロジェクトIDと食い違って繋がらないため）。
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_ID="demo-fuel"
TARGET="${1:-integration_test}"
GS_JSON="android/app/google-services.json"
BACKUP=""

restore() {
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    mv "$BACKUP" "$GS_JSON"
  elif [ -z "$BACKUP" ]; then
    rm -f "$GS_JSON"
  fi
  [ -n "${emulator_pid:-}" ] && kill "$emulator_pid" 2>/dev/null || true
}
trap restore EXIT

if [ -f "$GS_JSON" ]; then
  BACKUP="$(mktemp)"
  cp "$GS_JSON" "$BACKUP"
fi
cp tool/ci/google-services.demo.json "$GS_JSON"

# ── Cloud Functions をビルド（Functionsエミュレータが lib/ を読む）──
echo "▶ Cloud Functions をビルドします"
(cd functions && npm ci --silent && npm run build --silent)

# ── Firebaseエミュレータを起動（既に動いていればそれを使う）──
if nc -z 127.0.0.1 8080 2>/dev/null; then
  echo "▶ Firebaseエミュレータは既に起動しています"
else
  echo "▶ Firebaseエミュレータを起動します"
  firebase emulators:start --only auth,firestore,functions --project "$PROJECT_ID" \
    > /tmp/fuel-firebase-emulator.log 2>&1 &
  emulator_pid=$!

  echo -n "  起動待ち"
  for _ in $(seq 1 90); do
    if nc -z 127.0.0.1 8080 2>/dev/null && nc -z 127.0.0.1 9099 2>/dev/null && nc -z 127.0.0.1 5001 2>/dev/null; then
      break
    fi
    echo -n "."
    sleep 2
  done
  echo ""
  if ! nc -z 127.0.0.1 5001 2>/dev/null; then
    echo "✗ Firebaseエミュレータが起動しませんでした。ログ: /tmp/fuel-firebase-emulator.log"
    exit 1
  fi
fi

# ── 結合テストを実行 ──
# USE_FIREBASE_EMULATOR=true を渡さないとテスト側が起動を拒否する（本番保護）。
echo "▶ 結合テストを実行: $TARGET"
flutter test "$TARGET" \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --reporter expanded
