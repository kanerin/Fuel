import { readFileSync } from "node:fs";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";

// テストで使う固定のID。ALICE がデータの持ち主、BOB は無関係の第三者という構図。
// このアプリで守る境界は「本人かどうか」だけなので、この2人で大半のケースを表現できる。
export const ALICE = "alice";
export const BOB = "bob";

export async function createTestEnv() {
  return initializeTestEnvironment({
    projectId: "demo-fuel",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
}

/**
 * ルールを迂回して初期データを入れる。
 * ルール越しに用意しようとすると「準備そのものがルールに阻まれる」ため、
 * 前提データは必ずこの経路で作る。
 */
export async function seed(testEnv, path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(path).set(data);
  });
}

/** アプリ（UserProfile.toMap）が保存するのと同じ形の、有効なプロフィール。 */
export function validProfile(overrides = {}) {
  return {
    sex: "male",
    age: 35,
    heightCm: 170,
    weightKg: 70,
    activityLevel: "moderate",
    goal: "lose",
    weeklyRateKg: 0.5,
    pfcPreset: "balanced",
    proteinRatio: 20,
    fatRatio: 25,
    carbsRatio: 55,
    targetWeightKg: 65,
    customTargetKcal: null,
    ...overrides,
  };
}

/** アプリ（MealEntry.toMap）が保存するのと同じ形の、有効な食事の記録。 */
export function validMeal(overrides = {}) {
  return {
    date: "2026-10-21",
    mealType: "lunch",
    name: "牛丼",
    amount: "並盛",
    calories: 650,
    protein: 22,
    fat: 22,
    carbs: 90.5,
    source: "ai",
    createdAt: new Date("2026-10-21T12:00:00+09:00"),
    ...overrides,
  };
}

export function validWeight(date = "2026-10-21", overrides = {}) {
  return { date, weightKg: 69.5, updatedAt: new Date(), ...overrides };
}

export function validFavorite(overrides = {}) {
  return {
    name: "プロテイン",
    amount: "1杯",
    calories: 120,
    protein: 24,
    fat: 1.5,
    carbs: 3,
    createdAt: new Date(),
    ...overrides,
  };
}

/** オブジェクトから指定したキーを除いたコピー。 */
export function without(obj, ...keys) {
  const copy = { ...obj };
  for (const k of keys) delete copy[k];
  return copy;
}
