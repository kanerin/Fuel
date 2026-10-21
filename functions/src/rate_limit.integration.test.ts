import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";

import { consumeDailyQuota, refundDailyQuota } from "./rate_limit";

// 回数制限のトランザクションを、エミュレータのFirestoreで実際に通す。
// 判定そのもの（isOverLimit・nextRateLimitState）は rate_limit.test.ts で検証済み。
// FIRESTORE_EMULATOR_HOST が無い場合（npm test 単体）はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

describe("consumeDailyQuota / refundDailyQuota", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  let app: ReturnType<typeof initializeApp>;
  let db: Firestore;

  before(() => {
    app = initializeApp({ projectId: "demo-fuel" }, `it-rate-limit-${Date.now()}`);
    db = getFirestore(app);
  });

  after(async () => {
    await deleteApp(app);
  });

  afterEach(async () => {
    await db.recursiveDelete(db.collection("aiUsage"));
  });

  const usage = async (uid: string) => (await db.collection("aiUsage").doc(uid).get()).data();

  it("初回は許可して1回目として記録し、上限も書いておく（アプリが残り回数を出すため）", async () => {
    const result = await consumeDailyQuota(db, "u1", "2026-10-21", 50);

    assert.deepEqual(result, { allowed: true, remaining: 49 });
    const data = await usage("u1");
    assert.equal(data?.date, "2026-10-21");
    assert.equal(data?.count, 1);
    assert.equal(data?.limit, 50);
  });

  it("同じ日は積み上がり、上限に達したら拒否してカウントを書き換えない", async () => {
    for (let i = 0; i < 3; i++) await consumeDailyQuota(db, "u1", "2026-10-21", 3);

    const result = await consumeDailyQuota(db, "u1", "2026-10-21", 3);

    assert.deepEqual(result, { allowed: false });
    assert.equal((await usage("u1"))?.count, 3);
  });

  it("日付が変わればまた使える", async () => {
    await db.collection("aiUsage").doc("u1").set({ date: "2026-10-20", count: 50, limit: 50 });

    const result = await consumeDailyQuota(db, "u1", "2026-10-21", 50);

    assert.deepEqual(result, { allowed: true, remaining: 49 });
  });

  it("同時に呼ばれても上限を超えて通さない（トランザクション）", async () => {
    const results = await Promise.all(
      Array.from({ length: 8 }, () => consumeDailyQuota(db, "u1", "2026-10-21", 5)),
    );

    assert.equal(results.filter((r) => r.allowed).length, 5);
    assert.equal((await usage("u1"))?.count, 5);
  });

  it("利用者ごとに別々に数える", async () => {
    await consumeDailyQuota(db, "u1", "2026-10-21", 1);

    assert.deepEqual(await consumeDailyQuota(db, "u2", "2026-10-21", 1), { allowed: true, remaining: 0 });
  });

  it("払い戻すと1回分戻る", async () => {
    await consumeDailyQuota(db, "u1", "2026-10-21", 50);
    await consumeDailyQuota(db, "u1", "2026-10-21", 50);

    await refundDailyQuota(db, "u1", "2026-10-21");

    assert.equal((await usage("u1"))?.count, 1);
  });

  it("日付が変わった後の払い戻しは何もしない（今日の回数を減らさない）", async () => {
    await consumeDailyQuota(db, "u1", "2026-10-22", 50);

    await refundDailyQuota(db, "u1", "2026-10-21");

    assert.equal((await usage("u1"))?.count, 1);
  });

  it("記録が無ければ払い戻しは何もしない", async () => {
    await refundDailyQuota(db, "u1", "2026-10-21");

    assert.equal(await usage("u1"), undefined);
  });
});
