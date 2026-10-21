import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  callGeminiApi,
  classifyGeminiApiError,
  extractGeminiText,
  GEMINI_MODEL,
  GeminiCallError,
  GeminiRequestBody,
  truncateForLog,
} from "./gemini_client";

const body: GeminiRequestBody = { contents: [{ role: "user", parts: [{ text: "牛丼" }] }] };

function fakeFetch(handler: (url: string, init: RequestInit) => Response | Promise<Response>): typeof fetch {
  return (async (input: string | URL | Request, init?: RequestInit) => handler(String(input), init ?? {})) as typeof fetch;
}

const geminiOk = (text: string) =>
  new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), { status: 200 });

describe("classifyGeminiApiError", () => {
  it("429はクォータ切れ", () => assert.equal(classifyGeminiApiError(429), "resource-exhausted"));
  it("401/403はサーバー側の鍵の問題", () => {
    assert.equal(classifyGeminiApiError(401), "failed-precondition");
    assert.equal(classifyGeminiApiError(403), "failed-precondition");
  });
  it("502/503/504は一時的な障害", () => {
    for (const s of [502, 503, 504]) assert.equal(classifyGeminiApiError(s), "unavailable");
  });
  it("それ以外はinternal", () => {
    assert.equal(classifyGeminiApiError(400), "internal");
    assert.equal(classifyGeminiApiError(500), "internal");
  });
});

describe("extractGeminiText", () => {
  it("最初の候補のテキストを取り出す（複数パートは連結）", () => {
    assert.equal(
      extractGeminiText({ candidates: [{ content: { parts: [{ text: '{"items":' }, { text: "[]}" }] } }] }),
      '{"items":[]}',
    );
  });

  it("形が違えばnull（安全フィルタで候補が空になった場合など）", () => {
    assert.equal(extractGeminiText(null), null);
    assert.equal(extractGeminiText({ candidates: [] }), null);
    assert.equal(extractGeminiText({ candidates: [{ finishReason: "SAFETY" }] }), null);
    assert.equal(extractGeminiText({ candidates: [{ content: { parts: [{ inlineData: {} }] } }] }), null);
  });
});

describe("truncateForLog", () => {
  it("短ければそのまま、長ければ先頭だけと元の長さ", () => {
    assert.equal(truncateForLog("abc"), "abc");
    assert.equal(truncateForLog("a".repeat(10), 4), "aaaa…(10文字)");
  });
});

describe("callGeminiApi", () => {
  it("モデル・APIキー（ヘッダー）・本文を付けてPOSTし、応答テキストを返す", async () => {
    let captured: { url: string; init: RequestInit } | undefined;
    const result = await callGeminiApi(
      body,
      "secret-key",
      fakeFetch((url, init) => {
        captured = { url, init };
        return geminiOk('{"items":[]}');
      }),
    );

    assert.deepEqual(result, { ok: true, text: '{"items":[]}' });
    assert.equal(
      captured?.url,
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    );
    assert.equal(captured?.init.method, "POST");
    assert.equal((captured?.init.headers as Record<string, string>)["x-goog-api-key"], "secret-key");
    assert.deepEqual(JSON.parse(String(captured?.init.body)), body);
    assert.ok(captured?.init.signal, "待ち時間の上限（AbortSignal）を付ける");
    assert.ok(!captured?.url.includes("secret-key"), "APIキーはURLに載せない（ログやプロキシに残るため）");
  });

  it("HTTPエラーは分類し、本文をログ用の詳細に残す（APIキーは含めない）", async () => {
    const result = (await callGeminiApi(
      body,
      "secret-key",
      fakeFetch(() => new Response('{"error":{"message":"quota exceeded"}}', { status: 429 })),
    )) as GeminiCallError;

    assert.equal(result.ok, false);
    assert.equal(result.kind, "resource-exhausted");
    assert.match(result.detail, /429/);
    assert.match(result.detail, /quota exceeded/);
    assert.match(result.detail, new RegExp(GEMINI_MODEL));
    assert.ok(!result.detail.includes("secret-key"));
  });

  it("到達できなければunavailable（例外は投げない）", async () => {
    const result = (await callGeminiApi(
      body,
      "k",
      fakeFetch(() => {
        throw new TypeError("fetch failed");
      }),
    )) as GeminiCallError;

    assert.equal(result.kind, "unavailable");
    assert.match(result.detail, /到達できませんでした/);
  });

  it("応答がJSONでなければinternal", async () => {
    const result = (await callGeminiApi(body, "k", fakeFetch(() => new Response("<html>", { status: 200 })))) as GeminiCallError;

    assert.equal(result.kind, "internal");
  });

  it("候補が空（安全フィルタ等）ならinternal", async () => {
    const result = (await callGeminiApi(
      body,
      "k",
      fakeFetch(() => new Response(JSON.stringify({ candidates: [] }), { status: 200 })),
    )) as GeminiCallError;

    assert.equal(result.kind, "internal");
    assert.match(result.detail, /本文を取り出せませんでした/);
  });
});
