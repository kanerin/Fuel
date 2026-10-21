// ── AI推定の1日あたりの回数制限 ─────────────────────────────
// aiUsage/{uid} に { date, count, limit } を持つ。クライアントからは
// 書けない（firestore.rules で write: false）ので、利用者が自分でカウントを
// 0へ戻してレート制限を外すことはできない。

import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";

export interface RateLimitState {
  /** Asia/TokyoでのYYYY-MM-DD。日付が変わったらカウントをリセットする。 */
  date: string;
  count: number;
}

/** Asia/TokyoでのYYYY-MM-DD。sv-SEロケールがこの並びで整形してくれる。 */
export function tokyoDateKey(now: Date): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(now);
}

/**
 * 今回の呼び出しを許可してよいか。日付が変わっている（記録が無い）
 * 場合は、今日はまだ0回として扱う。
 */
export function isOverLimit(
  current: RateLimitState | undefined,
  todayKey: string,
  limit: number,
): boolean {
  if (!current || current.date !== todayKey) return false;
  return current.count >= limit;
}

/** 今回の呼び出しを数えた後の状態。日付が変わっていれば1から数え直す。 */
export function nextRateLimitState(
  current: RateLimitState | undefined,
  todayKey: string,
): RateLimitState {
  if (!current || current.date !== todayKey) return { date: todayKey, count: 1 };
  return { date: todayKey, count: current.count + 1 };
}

function readState(data: FirebaseFirestore.DocumentData | undefined): RateLimitState | undefined {
  if (!data || typeof data.date !== "string") return undefined;
  return { date: data.date, count: typeof data.count === "number" ? data.count : 0 };
}

export type ConsumeResult = { allowed: true; remaining: number } | { allowed: false };

/**
 * 1回分を消費する。トランザクションなので、素早い連打でも上限を超えて通さない。
 * 拒否した場合は書き込まない。
 */
export async function consumeDailyQuota(
  db: Firestore,
  uid: string,
  todayKey: string,
  limit: number,
): Promise<ConsumeResult> {
  const ref = db.collection("aiUsage").doc(uid);
  return db.runTransaction(async (tx) => {
    const current = readState((await tx.get(ref)).data());
    if (isOverLimit(current, todayKey, limit)) return { allowed: false } as const;

    const next = nextRateLimitState(current, todayKey);
    tx.set(ref, {
      date: next.date,
      count: next.count,
      // アプリが「残り回数」を表示するために読む（上限をアプリに埋め込まずに済む）
      limit,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { allowed: true, remaining: Math.max(0, limit - next.count) } as const;
  });
}

/**
 * [consumeDailyQuota] で消費した1回分を返す。
 *
 * Gemini側の障害・クォータ切れのように利用者のせいではない失敗で、
 * 利用者の1日の回数まで減ってしまわないようにするため。日付が変わっていたら何もしない。
 */
export async function refundDailyQuota(db: Firestore, uid: string, todayKey: string): Promise<void> {
  const ref = db.collection("aiUsage").doc(uid);
  await db.runTransaction(async (tx) => {
    const current = readState((await tx.get(ref)).data());
    if (!current || current.date !== todayKey || current.count <= 0) return;
    tx.update(ref, { count: current.count - 1, updatedAt: FieldValue.serverTimestamp() });
  });
}
