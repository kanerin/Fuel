// ── estimateNutrition の本体 ─────────────────────────────
// onCall の外に出してあり、Firestore・APIキー・fetch・時計を引数で受け取る。
// 結合テスト（estimate_nutrition.integration.test.ts）は、エミュレータの
// Firestoreと差し替えたfetchでこの関数をそのまま呼んで検証する。

import type { Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError } from "firebase-functions/v2/https";

import { callGeminiApi, truncateForLog } from "./gemini_client";
import {
  AI_DAILY_CALL_LIMIT,
  buildEstimateRequestBody,
  NutritionEstimate,
  parseEstimateRequest,
  parseNutritionResponse,
} from "./nutrition_logic";
import { consumeDailyQuota, refundDailyQuota, tokyoDateKey } from "./rate_limit";

export interface EstimateDeps {
  db: Firestore;
  /** Secret Manager の GEMINI_API_KEY。未設定なら空文字。 */
  apiKey: string;
  fetchImpl?: typeof fetch;
  now?: () => Date;
  dailyLimit?: number;
}

export interface EstimateResponse extends NutritionEstimate {
  /** 今日の残り回数 */
  remaining: number;
}

export async function handleEstimateNutrition(
  deps: EstimateDeps,
  uid: string | undefined,
  data: unknown,
): Promise<EstimateResponse> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }

  const parsed = parseEstimateRequest(data);
  if (!parsed.ok) {
    throw new HttpsError("invalid-argument", parsed.message);
  }

  // 鍵が無ければ何回呼んでも失敗するので、利用者の回数を消費する前に止める
  if (!deps.apiKey) {
    logger.error(
      "estimateNutrition: GEMINI_API_KEYシークレットが空です。Secret Managerへの登録と再デプロイが必要です",
    );
    throw new HttpsError("failed-precondition", "AIのAPIキーが設定されていません");
  }

  const todayKey = tokyoDateKey((deps.now ?? (() => new Date()))());
  const limit = deps.dailyLimit ?? AI_DAILY_CALL_LIMIT;
  const quota = await consumeDailyQuota(deps.db, uid, todayKey, limit);
  if (!quota.allowed) {
    // details.reason で「1日の上限」と「Gemini側のクォータ切れ」をアプリが見分ける
    // （lib/services/nutrition_estimator.dart の describeEstimateFailure）
    throw new HttpsError("resource-exhausted", `今日のAI推定の回数（${limit}回）を使い切りました`, {
      reason: "daily_limit",
      limit,
    });
  }

  const result = await callGeminiApi(
    buildEstimateRequestBody(parsed.request),
    deps.apiKey,
    deps.fetchImpl,
  );
  if (!result.ok) {
    // 利用者へ返せるのはHttpsErrorのcodeだけなので、原因はここでログへ残す
    logger.error(`estimateNutrition: ${result.detail}`, { kind: result.kind, uid });
    // Gemini側の障害・クォータ切れは利用者のせいではないので回数を返す
    // （Geminiに課金されるのは応答を生成したときだけなので、ここで返しても損はしない）
    if (result.kind === "unavailable" || result.kind === "resource-exhausted") {
      await refundDailyQuota(deps.db, uid, todayKey).catch((err: unknown) =>
        logger.warn("estimateNutrition: 回数の払い戻しに失敗しました", { uid, err: String(err) }),
      );
    }
    throw new HttpsError(result.kind, "AIとの通信でエラーが発生しました");
  }

  const estimate = parseNutritionResponse(result.text);
  if (!estimate) {
    logger.error("estimateNutrition: Geminiの応答を解釈できませんでした", {
      uid,
      response: truncateForLog(result.text, 300),
    });
    throw new HttpsError("internal", "AIの応答を解釈できませんでした");
  }

  logger.info("estimateNutrition: 推定しました", {
    uid,
    items: estimate.items.length,
    withImage: parsed.request.image !== undefined,
  });
  return { ...estimate, remaining: quota.remaining };
}
