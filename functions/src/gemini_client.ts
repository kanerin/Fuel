// ── Gemini API とのやり取り ─────────────────────────────
// aimaru（functions/src/gemini_logic.ts）で実運用している呼び出し・エラー分類を
// 引き継いでいる。fetchを差し込めるので、テストでは実ネットワークに触れない。

/**
 * Geminiのモデル名。gemini-flash-latest は無料枠の1日あたりの回数が少なく
 * 枯渇しやすいため、余裕のある gemini-flash-lite-latest を使う（aimaruと同じ判断）。
 */
export const GEMINI_MODEL = "gemini-flash-lite-latest";

/**
 * Gemini APIの応答を待つ上限。関数自体のタイムアウト（60秒）より短くして、
 * 待ちきれなかったときも「時間切れ」として分類したエラーを返せるようにする
 * （関数ごとタイムアウトすると、利用者の回数を払い戻す機会も失う）。
 */
export const GEMINI_TIMEOUT_MS = 45_000;

export type GeminiPart =
  | { text: string }
  | { inlineData: { mimeType: string; data: string } };

export interface GeminiContent {
  role: "user" | "model";
  parts: GeminiPart[];
}

export interface GeminiRequestBody {
  systemInstruction?: { parts: { text: string }[] };
  contents: GeminiContent[];
  generationConfig?: Record<string, unknown>;
}

/** Gemini APIの失敗を、呼び出し元へ返すHttpsErrorのcodeへ分類したもの。 */
export type GeminiErrorKind =
  | "resource-exhausted"
  | "failed-precondition"
  | "internal"
  | "unavailable";

export function classifyGeminiApiError(status: number): GeminiErrorKind {
  if (status === 429) return "resource-exhausted";
  // 401/403はこちら（サーバー側）が持つ鍵の問題であり、呼び出した利用者の
  // 問題ではない。鍵の未設定・失効のどちらもここに落ちる。
  if (status === 401 || status === 403) return "failed-precondition";
  // Gemini側の一時的な障害は、こちらのコードを直しても意味がない。
  // 「時間をおいて再試行」と案内できるようinternalと区別する。
  if (status === 502 || status === 503 || status === 504) return "unavailable";
  return "internal";
}

/** ログに残す診断メッセージが際限なく伸びないよう、先頭だけを取る。 */
export function truncateForLog(value: string, max = 500): string {
  return value.length <= max ? value : `${value.slice(0, max)}…(${value.length}文字)`;
}

/**
 * Gemini APIの生レスポンスから応答テキストを取り出す。
 * 形が想定と違う場合はnull。
 */
export function extractGeminiText(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const candidates = (body as Record<string, unknown>).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const content = (candidates[0] as Record<string, unknown> | undefined)?.content;
  if (typeof content !== "object" || content === null) return null;
  const parts = (content as Record<string, unknown>).parts;
  if (!Array.isArray(parts) || parts.length === 0) return null;
  const texts = parts
    .map((p) => (p as Record<string, unknown> | undefined)?.text)
    .filter((t): t is string => typeof t === "string");
  return texts.length > 0 ? texts.join("") : null;
}

export interface GeminiCallResult {
  ok: true;
  text: string;
}

export interface GeminiCallError {
  ok: false;
  kind: GeminiErrorKind;
  /**
   * 何が起きたかを関数のログ（`firebase functions:log`）へ残すための文字列。
   * 利用者にはHttpsErrorのcodeしか返らないので、ここを残しておかないと
   * 原因を追えなくなる。APIキーは決して含めないこと。
   */
  detail: string;
}

/** Gemini APIを呼び出し、応答テキストか分類済みのエラーを返す（例外は投げない）。 */
export async function callGeminiApi(
  body: GeminiRequestBody,
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<GeminiCallResult | GeminiCallError> {
  let res: Response;
  try {
    res = await fetchImpl(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      },
    );
  } catch (err) {
    // Gemini側へ到達すらできなかった（DNS・接続断・タイムアウト）
    return {
      ok: false,
      kind: "unavailable",
      detail: `Gemini APIへ到達できませんでした: ${truncateForLog(String(err))}`,
    };
  }

  if (!res.ok) {
    // エラー本文にはモデル名の誤り・鍵の失効・課金未設定など、原因が
    // そのまま書かれていることが多いのでログへ残す
    const text = await res.text().catch(() => "(本文を読めませんでした)");
    return {
      ok: false,
      kind: classifyGeminiApiError(res.status),
      detail: `Gemini APIが${res.status}を返しました（model=${GEMINI_MODEL}）: ${truncateForLog(text)}`,
    };
  }

  let json: unknown;
  try {
    json = await res.json();
  } catch (err) {
    return {
      ok: false,
      kind: "internal",
      detail: `Gemini APIの応答をJSONとして読めませんでした: ${truncateForLog(String(err))}`,
    };
  }

  const text = extractGeminiText(json);
  if (text === null) {
    // 安全フィルタで候補が空になった場合などもここへ落ちる
    return {
      ok: false,
      kind: "internal",
      detail: `Gemini APIの応答から本文を取り出せませんでした: ${truncateForLog(JSON.stringify(json))}`,
    };
  }
  return { ok: true, text };
}
