import assert from "node:assert/strict";
import { after, afterEach, before, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { EstimateDeps, handleEstimateNutrition } from "./estimate_nutrition";

// estimateNutrition の本体を、エミュレータのFirestore（回数制限）と
// 差し替えたfetch（Gemini API）で端から端まで通す。
// FIRESTORE_EMULATOR_HOST が無い場合（npm test 単体）はスキップする。
const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;

const NOW = () => new Date("2026-10-21T03:00:00Z"); // 東京 12:00
const TODAY = "2026-10-21";

const geminiReply = (payload: unknown) =>
  new Response(
    JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }] }),
    { status: 200 },
  );

function fakeFetch(handler: () => Response | Promise<Response>, calls?: { count: number; body?: unknown }) {
  return (async (_input: string | URL | Request, init?: RequestInit) => {
    if (calls) {
      calls.count++;
      calls.body = JSON.parse(String(init?.body));
    }
    return handler();
  }) as typeof fetch;
}

function isHttpsError(code: string, check?: (e: HttpsError) => void) {
  return (err: unknown) => {
    assert.ok(err instanceof HttpsError, `HttpsErrorではありません: ${String(err)}`);
    assert.equal(err.code, code);
    check?.(err);
    return true;
  };
}

describe("handleEstimateNutrition", { skip: EMULATOR ? false : "エミュレータ未起動" }, () => {
  let app: ReturnType<typeof initializeApp>;
  let db: Firestore;

  before(() => {
    app = initializeApp({ projectId: "demo-fuel" }, `it-estimate-${Date.now()}`);
    db = getFirestore(app);
  });

  after(async () => {
    await deleteApp(app);
  });

  afterEach(async () => {
    await db.recursiveDelete(db.collection("aiUsage"));
  });

  const deps = (overrides: Partial<EstimateDeps>): EstimateDeps => ({
    db,
    apiKey: "test-key",
    now: NOW,
    ...overrides,
  });

  const count = async () => (await db.collection("aiUsage").doc("u1").get()).data()?.count;

  it("推定結果を正規化して返し、残り回数を添える", async () => {
    const calls = { count: 0, body: undefined as unknown };
    const result = await handleEstimateNutrition(
      deps({
        fetchImpl: fakeFetch(
          () =>
            geminiReply({
              items: [
                { name: "牛丼", amount: "並盛", calories: 652.4, protein: 22.04, fat: 22, carbs: 90 },
                { name: "味噌汁", amount: "1杯", calories: 40, protein: 3, fat: 1.5, carbs: 4 },
              ],
              note: "並盛として推定しました",
            }),
          calls,
        ),
      }),
      "u1",
      { text: "牛丼並盛と味噌汁" },
    );

    assert.deepEqual(result, {
      items: [
        { name: "牛丼", amount: "並盛", calories: 652, protein: 22, fat: 22, carbs: 90 },
        { name: "味噌汁", amount: "1杯", calories: 40, protein: 3, fat: 1.5, carbs: 4 },
      ],
      note: "並盛として推定しました",
      remaining: 49,
    });
    assert.equal(calls.count, 1);
    // プロンプトはサーバー側で組み立てる（利用者の文章はuserパートに入るだけ）
    const sent = calls.body as { systemInstruction: unknown; contents: { parts: { text?: string }[] }[] };
    assert.ok(sent.systemInstruction);
    assert.match(sent.contents[0].parts[0].text ?? "", /牛丼並盛と味噌汁/);
    assert.equal(await count(), 1);
  });

  it("未ログインは拒否し、Geminiを呼ばない", async () => {
    const calls = { count: 0 };
    await assert.rejects(
      handleEstimateNutrition(deps({ fetchImpl: fakeFetch(() => geminiReply({ items: [] }), calls) }), undefined, {
        text: "牛丼",
      }),
      isHttpsError("unauthenticated"),
    );
    assert.equal(calls.count, 0);
  });

  it("入力が不正なら理由を返し、回数を消費しない", async () => {
    await assert.rejects(
      handleEstimateNutrition(deps({}), "u1", { text: "" }),
      isHttpsError("invalid-argument", (e) => assert.match(e.message, /食べたもの/)),
    );
    assert.equal(await count(), undefined);
  });

  it("APIキーが未設定なら、回数を消費せずに failed-precondition", async () => {
    await assert.rejects(
      handleEstimateNutrition(deps({ apiKey: "" }), "u1", { text: "牛丼" }),
      isHttpsError("failed-precondition"),
    );
    assert.equal(await count(), undefined);
  });

  it("1日の上限に達したら、Geminiを呼ばずに details.reason=daily_limit で拒否", async () => {
    await db.collection("aiUsage").doc("u1").set({ date: TODAY, count: 3, limit: 3 });
    const calls = { count: 0 };

    await assert.rejects(
      handleEstimateNutrition(
        deps({ dailyLimit: 3, fetchImpl: fakeFetch(() => geminiReply({ items: [] }), calls) }),
        "u1",
        { text: "牛丼" },
      ),
      isHttpsError("resource-exhausted", (e) => assert.deepEqual(e.details, { reason: "daily_limit", limit: 3 })),
    );
    assert.equal(calls.count, 0);
  });

  it("Gemini側の障害（503）なら unavailable を返し、回数を払い戻す", async () => {
    await assert.rejects(
      handleEstimateNutrition(
        deps({ fetchImpl: fakeFetch(() => new Response("overloaded", { status: 503 })) }),
        "u1",
        { text: "牛丼" },
      ),
      isHttpsError("unavailable"),
    );
    assert.equal(await count(), 0);
  });

  it("Geminiのクォータ切れ（429）は、1日の上限とは区別できる形（details無し）で返し、回数を払い戻す", async () => {
    await assert.rejects(
      handleEstimateNutrition(
        deps({ fetchImpl: fakeFetch(() => new Response("quota", { status: 429 })) }),
        "u1",
        { text: "牛丼" },
      ),
      isHttpsError("resource-exhausted", (e) => assert.equal(e.details, undefined)),
    );
    assert.equal(await count(), 0);
  });

  it("応答を解釈できなければ internal（Geminiは応答を生成しているので回数は戻さない）", async () => {
    await assert.rejects(
      handleEstimateNutrition(
        deps({
          fetchImpl: fakeFetch(
            () => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "牛丼は650kcal" }] } }] })),
          ),
        }),
        "u1",
        { text: "牛丼" },
      ),
      isHttpsError("internal"),
    );
    assert.equal(await count(), 1);
  });

  it("食べ物が見つからなければ空の結果を返す（エラーにはしない）", async () => {
    const result = await handleEstimateNutrition(
      deps({ fetchImpl: fakeFetch(() => geminiReply({ items: [], note: "食べ物の説明が見つかりませんでした" })) }),
      "u1",
      { text: "こんにちは" },
    );

    assert.deepEqual(result.items, []);
    assert.match(result.note, /見つかりません/);
  });
});
