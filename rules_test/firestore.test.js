import { after, before, beforeEach, describe, it } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";

import {
  ALICE,
  BOB,
  createTestEnv,
  seed,
  validFavorite,
  validMeal,
  validProfile,
  validWeight,
  without,
} from "./helpers.js";

// Firestore セキュリティルール（../firestore.rules）のテスト。
//
// 守るべき境界は「本人以外は、その人のデータに一切触れない」。
// あわせて、アプリと同じ値の範囲を検証していることを確かめる
// （アプリの不具合や直接アクセスで壊れた値が保存されないように）。
let testEnv;

before(async () => {
  testEnv = await createTestEnv();
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const asAlice = () => testEnv.authenticatedContext(ALICE).firestore();
const asBob = () => testEnv.authenticatedContext(BOB).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

const userPath = (uid = ALICE) => `users/${uid}`;

describe("users/{uid} — 本人だけ", () => {
  it("本人はプロフィールを作成・読み取り・更新できる", async () => {
    const ref = asAlice().doc(userPath());
    await assertSucceeds(ref.set({ profile: validProfile(), updatedAt: new Date() }));
    await assertSucceeds(ref.get());
    await assertSucceeds(ref.set({ profile: validProfile({ age: 36 }), updatedAt: new Date() }));
  });

  it("他人は読めず、書けない", async () => {
    await seed(testEnv, userPath(), { profile: validProfile() });

    await assertFails(asBob().doc(userPath()).get());
    await assertFails(asBob().doc(userPath()).set({ profile: validProfile() }));
    await assertFails(asBob().doc(userPath()).update({ "profile.weightKg": 60 }));
  });

  it("未ログインは読めず、書けない", async () => {
    await seed(testEnv, userPath(), { profile: validProfile() });

    await assertFails(asAnon().doc(userPath()).get());
    await assertFails(asAnon().doc(userPath()).set({ profile: validProfile() }));
  });

  it("クライアントからは本体を削除できない（退会はサブコレクションごとCloud Functionsで消す）", async () => {
    await seed(testEnv, userPath(), { profile: validProfile() });

    await assertFails(asAlice().doc(userPath()).delete());
  });

  it("想定外のトップレベルのフィールドは書けない", async () => {
    await assertFails(
      asAlice().doc(userPath()).set({ profile: validProfile(), aiCallCount: 0 }),
    );
  });
});

describe("users/{uid}.profile — 値の検証", () => {
  const save = (profile) => asAlice().doc(userPath()).set({ profile, updatedAt: new Date() });

  it("任意項目（目標体重・手動の目標カロリー）はnullでも、値があってもよい", async () => {
    await assertSucceeds(save(validProfile({ targetWeightKg: null, customTargetKcal: null })));
    await assertSucceeds(save(validProfile({ targetWeightKg: 62.5, customTargetKcal: 1800 })));
  });

  it("年齢は15〜100の整数", async () => {
    await assertSucceeds(save(validProfile({ age: 15 })));
    await assertSucceeds(save(validProfile({ age: 100 })));
    await assertFails(save(validProfile({ age: 14 })));
    await assertFails(save(validProfile({ age: 101 })));
    await assertFails(save(validProfile({ age: 35.5 })));
    await assertFails(save(validProfile({ age: "35" })));
  });

  it("身長は120〜220cm、体重は30〜250kg（小数も可）", async () => {
    await assertSucceeds(save(validProfile({ heightCm: 158.5, weightKg: 52.3 })));
    await assertFails(save(validProfile({ heightCm: 119 })));
    await assertFails(save(validProfile({ heightCm: 221 })));
    await assertFails(save(validProfile({ weightKg: 29.9 })));
    await assertFails(save(validProfile({ weightKg: 250.1 })));
  });

  it("性別・活動レベル・PFCプリセットは決まった値だけ", async () => {
    await assertFails(save(validProfile({ sex: "other" })));
    await assertFails(save(validProfile({ activityLevel: "extreme" })));
    await assertFails(save(validProfile({ pfcPreset: "keto" })));
  });

  it("目標とペースの組み合わせ（維持は0、減量は0.25〜0.75、増量は0.25〜0.5）", async () => {
    await assertSucceeds(save(validProfile({ goal: "maintain", weeklyRateKg: 0 })));
    await assertSucceeds(save(validProfile({ goal: "lose", weeklyRateKg: 0.75 })));
    await assertSucceeds(save(validProfile({ goal: "gain", weeklyRateKg: 0.25 })));
    await assertFails(save(validProfile({ goal: "maintain", weeklyRateKg: 0.5 })));
    await assertFails(save(validProfile({ goal: "lose", weeklyRateKg: 1 })));
    await assertFails(save(validProfile({ goal: "gain", weeklyRateKg: 0.75 })));
    await assertFails(save(validProfile({ goal: "bulk", weeklyRateKg: 0.25 })));
  });

  it("PFC比率は各5〜70%の整数で、合計100%", async () => {
    await assertSucceeds(save(validProfile({ pfcPreset: "custom", proteinRatio: 5, fatRatio: 25, carbsRatio: 70 })));
    await assertFails(save(validProfile({ proteinRatio: 20, fatRatio: 20, carbsRatio: 50 })));
    await assertFails(save(validProfile({ proteinRatio: 4, fatRatio: 26, carbsRatio: 70 })));
    await assertFails(save(validProfile({ proteinRatio: 20.5, fatRatio: 24.5, carbsRatio: 55 })));
  });

  it("目標体重は30〜250kg、手動の目標カロリーは1000〜5000kcalの整数", async () => {
    await assertFails(save(validProfile({ targetWeightKg: 20 })));
    await assertFails(save(validProfile({ customTargetKcal: 999 })));
    await assertFails(save(validProfile({ customTargetKcal: 5001 })));
    await assertFails(save(validProfile({ customTargetKcal: 1800.5 })));
  });

  it("必須項目が欠けている・想定外の項目があるプロフィールは拒否", async () => {
    await assertFails(save(without(validProfile(), "weightKg")));
    await assertFails(save(without(validProfile(), "goal")));
    await assertFails(save(validProfile({ bodyFat: 20 })));
  });

  it("体重の記録に合わせて profile.weightKg だけを更新できる（更新後のprofile全体を検証する）", async () => {
    await seed(testEnv, userPath(), { profile: validProfile() });

    await assertSucceeds(asAlice().doc(userPath()).update({ "profile.weightKg": 69.5 }));
    await assertFails(asAlice().doc(userPath()).update({ "profile.weightKg": 10 }));
  });
});

describe("users/{uid}/meals — 食事の記録", () => {
  const mealRef = (db, id = "m1", uid = ALICE) => db.doc(`users/${uid}/meals/${id}`);

  it("本人は作成・読み取り・更新・削除できる", async () => {
    await assertSucceeds(mealRef(asAlice()).set(validMeal()));
    await assertSucceeds(mealRef(asAlice()).get());
    await assertSucceeds(mealRef(asAlice()).set(validMeal({ mealType: "dinner", calories: 975 })));
    await assertSucceeds(mealRef(asAlice()).delete());
  });

  it("本人は1日分の記録をクエリできる", async () => {
    await seed(testEnv, "users/alice/meals/m1", validMeal());

    await assertSucceeds(asAlice().collection("users/alice/meals").where("date", "==", "2026-10-21").get());
  });

  it("他人・未ログインは読めず、書けない", async () => {
    await seed(testEnv, "users/alice/meals/m1", validMeal());

    await assertFails(mealRef(asBob()).get());
    await assertFails(asBob().collection("users/alice/meals").get());
    await assertFails(mealRef(asBob(), "m2").set(validMeal()));
    await assertFails(mealRef(asBob()).delete());
    await assertFails(mealRef(asAnon()).get());
  });

  it("名前は1〜60文字（日本語の60文字も通る）、量は0〜40文字", async () => {
    await assertSucceeds(mealRef(asAlice()).set(validMeal({ name: "あ".repeat(60), amount: "い".repeat(40) })));
    await assertSucceeds(mealRef(asAlice()).set(validMeal({ amount: "" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ name: "" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ name: "あ".repeat(61) })));
    await assertFails(mealRef(asAlice()).set(validMeal({ amount: "い".repeat(41) })));
  });

  it("エネルギーは0〜5000kcal、PFCは0〜500g", async () => {
    await assertSucceeds(mealRef(asAlice()).set(validMeal({ calories: 0, protein: 0, fat: 0, carbs: 0 })));
    await assertSucceeds(mealRef(asAlice()).set(validMeal({ calories: 5000, protein: 500 })));
    await assertFails(mealRef(asAlice()).set(validMeal({ calories: 5001 })));
    await assertFails(mealRef(asAlice()).set(validMeal({ calories: -1 })));
    await assertFails(mealRef(asAlice()).set(validMeal({ protein: 500.1 })));
    await assertFails(mealRef(asAlice()).set(validMeal({ fat: "20" })));
  });

  it("日付はYYYY-MM-DD、食事区分と作成元は決まった値だけ", async () => {
    await assertFails(mealRef(asAlice()).set(validMeal({ date: "2026/10/21" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ date: "2026-10-21T12:00" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ mealType: "brunch" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ source: "import" })));
  });

  it("必須項目の欠け・想定外の項目・作成日時がTimestampでないものは拒否", async () => {
    await assertFails(mealRef(asAlice()).set(without(validMeal(), "carbs")));
    await assertFails(mealRef(asAlice()).set(validMeal({ note: "メモ" })));
    await assertFails(mealRef(asAlice()).set(validMeal({ createdAt: "2026-10-21" })));
  });
});

describe("users/{uid}/weights — 体重", () => {
  const weightRef = (db, date = "2026-10-21", uid = ALICE) => db.doc(`users/${uid}/weights/${date}`);

  it("本人は記録・読み取り・削除できる", async () => {
    await assertSucceeds(weightRef(asAlice()).set(validWeight()));
    await assertSucceeds(weightRef(asAlice()).get());
    await assertSucceeds(weightRef(asAlice()).delete());
  });

  it("他人は読めず、書けない", async () => {
    await seed(testEnv, "users/alice/weights/2026-10-21", validWeight());

    await assertFails(weightRef(asBob()).get());
    await assertFails(weightRef(asBob(), "2026-10-22").set(validWeight("2026-10-22")));
  });

  it("ドキュメントIDと日付が一致し、IDが日付の形であること", async () => {
    await assertFails(weightRef(asAlice(), "2026-10-21").set(validWeight("2026-10-22")));
    await assertFails(weightRef(asAlice(), "latest").set(validWeight("latest")));
  });

  it("体重は30〜250kg", async () => {
    await assertFails(weightRef(asAlice()).set(validWeight("2026-10-21", { weightKg: 29 })));
    await assertFails(weightRef(asAlice()).set(validWeight("2026-10-21", { weightKg: 251 })));
    await assertFails(weightRef(asAlice()).set(validWeight("2026-10-21", { weightKg: "70" })));
  });

  it("想定外の項目は拒否", async () => {
    await assertFails(weightRef(asAlice()).set(validWeight("2026-10-21", { bodyFat: 20 })));
  });
});

describe("users/{uid}/favorites — お気に入り", () => {
  const favRef = (db, id = "f1", uid = ALICE) => db.doc(`users/${uid}/favorites/${id}`);

  it("本人は登録・読み取り・削除できる", async () => {
    await assertSucceeds(favRef(asAlice()).set(validFavorite()));
    await assertSucceeds(asAlice().collection("users/alice/favorites").orderBy("createdAt", "desc").get());
    await assertSucceeds(favRef(asAlice()).delete());
  });

  it("他人は読めず、書けない", async () => {
    await seed(testEnv, "users/alice/favorites/f1", validFavorite());

    await assertFails(favRef(asBob()).get());
    await assertFails(favRef(asBob(), "f2").set(validFavorite()));
  });

  it("食べ物として不正な値（名前なし・範囲外）や想定外の項目は拒否", async () => {
    await assertFails(favRef(asAlice()).set(validFavorite({ name: "" })));
    await assertFails(favRef(asAlice()).set(validFavorite({ calories: 9999 })));
    await assertFails(favRef(asAlice()).set(validFavorite({ date: "2026-10-21" })));
  });
});

describe("aiUsage/{uid} — AI推定の回数制限", () => {
  it("本人は残り回数の表示のために読める", async () => {
    await seed(testEnv, "aiUsage/alice", { date: "2026-10-21", count: 3, limit: 50 });

    await assertSucceeds(asAlice().doc("aiUsage/alice").get());
  });

  it("本人でも書き換えられない（カウントを0に戻して上限を外せないように）", async () => {
    await seed(testEnv, "aiUsage/alice", { date: "2026-10-21", count: 50, limit: 50 });

    await assertFails(asAlice().doc("aiUsage/alice").set({ date: "2026-10-21", count: 0, limit: 50 }));
    await assertFails(asAlice().doc("aiUsage/alice").update({ count: 0 }));
    await assertFails(asAlice().doc("aiUsage/alice").delete());
  });

  it("他人は読めない", async () => {
    await seed(testEnv, "aiUsage/alice", { date: "2026-10-21", count: 3, limit: 50 });

    await assertFails(asBob().doc("aiUsage/alice").get());
  });
});

describe("それ以外のパス", () => {
  it("ルールに無いコレクションは誰も読み書きできない", async () => {
    await assertFails(asAlice().doc("admin/config").get());
    await assertFails(asAlice().doc("users/alice/notes/n1").set({ text: "x" }));
  });
});
