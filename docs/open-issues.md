# 残課題

「今どこまで出来ていて、何が残っているか」を1枚で把握するためのもの。PRの中で都度更新する。

## 利用者（人間）にしかできない準備

| # | 内容 | 手順 |
|---|---|---|
| H1 | Firebaseプロジェクトの作成（Blazeプラン）・Googleログインの有効化・Firestoreの作成 | README「1.」 |
| H2 | Androidアプリの登録（`io.github.kanerin.fuel`）・SHA-1の登録・`google-services.json` の配置 | README「2.」 |
| H3 | Gemini APIキーを Secret Manager に登録 | README「3.」 |
| H4 | ルール・インデックス・Cloud Functions の初回デプロイ | README「4.」 |

## これから（優先度順）

| 優先度 | 内容 | メモ |
|---|---|---|
| P1 | 実機での動作確認（Googleログイン・AI推定・写真・オフライン時の記録） | エミュレータ・単体テストでは確認できない経路 |
| P2 | App Check の導入 | `estimateNutrition` を正規のアプリ以外から呼ばれにくくする（回数制限は既にある） |
| P2 | 記録のリマインダー通知（食事・体重） | ローカル通知で十分（FCMは不要） |
| P2 | 前日の食事のコピー | 「最近食べたもの」で代替できているが、まとめてコピーしたい場面がある |
| P3 | iOS対応 | `flutter create --platforms=ios .`。Googleログインの URL scheme・写真の権限の説明文が要る |
| P3 | 食品データベースの検索 | AI推定・手入力・お気に入りで代替している |
| P3 | 運動・歩数・水分の記録 | 要件定義の対象外（`docs/requirements.md` 10章） |
| P3 | データのエクスポート（CSV） | |
