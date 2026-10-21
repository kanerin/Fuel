import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { handleDeleteAccount } from "./delete_account";

// 退会で、本人のデータ（サブコレクションを含む）とAuthのユーザーが消え、
// 他の利用者のデータには触れないことを、エミュレータで確かめる。
const EMULATORS = process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST;

describe("handleDeleteAccount", { skip: EMULATORS ? false : "エミュレータ未起動" }, () => {
  let app: ReturnType<typeof initializeApp>;
  let db: Firestore;
  let auth: Auth;

  before(() => {
    app = initializeApp({ projectId: "demo-fuel" }, `it-delete-${Date.now()}`);
    db = getFirestore(app);
    auth = getAuth(app);
  });

  after(async () => {
    await deleteApp(app);
  });

  afterEach(async () => {
    await db.recursiveDelete(db.collection("users"));
    await db.recursiveDelete(db.collection("aiUsage"));
    const users = await auth.listUsers();
    await Promise.all(users.users.map((u) => auth.deleteUser(u.uid)));
  });

  async function seedUser(uid: string) {
    await auth.createUser({ uid });
    const user = db.collection("users").doc(uid);
    await user.set({ profile: { age: 35 } });
    await user.collection("meals").doc("m1").set({ name: "牛丼", date: "2026-10-21" });
    await user.collection("meals").doc("m2").set({ name: "味噌汁", date: "2026-10-21" });
    await user.collection("weights").doc("2026-10-21").set({ weightKg: 70 });
    await user.collection("favorites").doc("f1").set({ name: "プロテイン" });
    await db.collection("aiUsage").doc(uid).set({ date: "2026-10-21", count: 3 });
  }

  it("本人のデータ（サブコレクション・回数制限を含む）とAuthのユーザーを削除する", async () => {
    await seedUser("u1");

    assert.deepEqual(await handleDeleteAccount({ db, auth }, "u1"), { deleted: true });

    assert.equal((await db.collection("users").doc("u1").get()).exists, false);
    for (const sub of ["meals", "weights", "favorites"]) {
      const snap = await db.collection("users").doc("u1").collection(sub).get();
      assert.equal(snap.size, 0, `${sub} が残っている`);
    }
    assert.equal((await db.collection("aiUsage").doc("u1").get()).exists, false);
    await assert.rejects(auth.getUser("u1"), (e: unknown) => (e as { code?: string }).code === "auth/user-not-found");
  });

  it("他の利用者のデータには触れない", async () => {
    await seedUser("u1");
    await seedUser("u2");

    await handleDeleteAccount({ db, auth }, "u1");

    assert.equal((await db.collection("users").doc("u2").get()).exists, true);
    assert.equal((await db.collection("users").doc("u2").collection("meals").get()).size, 2);
    assert.equal((await auth.getUser("u2")).uid, "u2");
  });

  it("2回目の呼び出し（途中で失敗してやり直した場合）も成功する", async () => {
    await seedUser("u1");
    await handleDeleteAccount({ db, auth }, "u1");

    assert.deepEqual(await handleDeleteAccount({ db, auth }, "u1"), { deleted: true });
  });

  it("未ログインは拒否", async () => {
    await assert.rejects(
      handleDeleteAccount({ db, auth }, undefined),
      (e: unknown) => e instanceof HttpsError && e.code === "unauthenticated",
    );
  });
});
