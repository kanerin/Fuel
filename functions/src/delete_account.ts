// ── 退会（アカウントと全データの削除）─────────────────────────
// Play Storeの方針上、アカウントを作れるアプリには削除の手段が要る。
// クライアントから1件ずつ消すと、途中で失敗したときに中途半端なデータが残り、
// 件数が多いと時間もかかるので、サーバー側でまとめて消す。

import type { Auth } from "firebase-admin/auth";
import type { Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError } from "firebase-functions/v2/https";

/** users/{uid}（サブコレクションを含む）と aiUsage/{uid} を削除する。 */
export async function deleteUserData(db: Firestore, uid: string): Promise<void> {
  await db.recursiveDelete(db.collection("users").doc(uid));
  await db.collection("aiUsage").doc(uid).delete();
}

export interface DeleteAccountDeps {
  db: Firestore;
  auth: Auth;
}

/**
 * データ → Authのユーザーの順に消す。途中で失敗しても、Authのユーザーが
 * 残っている限り利用者はログインしてやり直せる（どちらの削除も、
 * 既に消えていれば何もしないので2回目も成功する）。
 */
export async function handleDeleteAccount(
  deps: DeleteAccountDeps,
  uid: string | undefined,
): Promise<{ deleted: true }> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }

  await deleteUserData(deps.db, uid);
  try {
    await deps.auth.deleteUser(uid);
  } catch (err) {
    if ((err as { code?: unknown }).code !== "auth/user-not-found") throw err;
  }

  logger.info("deleteAccount: アカウントと全データを削除しました", { uid });
  return { deleted: true };
}
