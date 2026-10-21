import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildEstimateRequestBody,
  MAX_IMAGE_BASE64_LENGTH,
  MAX_ITEMS,
  MAX_TEXT_LENGTH,
  parseEstimateRequest,
  parseNutritionResponse,
  RESPONSE_SCHEMA,
  SYSTEM_INSTRUCTION,
} from "./nutrition_logic";

describe("parseEstimateRequest", () => {
  it("文章だけ: 前後の空白を落とす", () => {
    assert.deepEqual(parseEstimateRequest({ text: "  牛丼並盛\n" }), {
      ok: true,
      request: { text: "牛丼並盛" },
    });
  });

  it("写真だけ（文章は空でもよい）", () => {
    assert.deepEqual(parseEstimateRequest({ text: "", image: { mimeType: "image/jpeg", data: "AAEC" } }), {
      ok: true,
      request: { text: "", image: { mimeType: "image/jpeg", data: "AAEC" } },
    });
  });

  it("文章と写真の両方", () => {
    const result = parseEstimateRequest({ text: "大盛り", image: { mimeType: "image/png", data: "AAEC" } });
    assert.equal(result.ok, true);
  });

  it("文章も写真も無ければ拒否", () => {
    const result = parseEstimateRequest({ text: "   " });
    assert.equal(result.ok, false);
    assert.match((result as { message: string }).message, /食べたもの/);
  });

  it("オブジェクトでない・文章が文字列でなければ拒否", () => {
    assert.equal(parseEstimateRequest(null).ok, false);
    assert.equal(parseEstimateRequest("牛丼").ok, false);
    assert.equal(parseEstimateRequest({ text: 123 }).ok, false);
  });

  it(`文章は${MAX_TEXT_LENGTH}文字まで`, () => {
    assert.equal(parseEstimateRequest({ text: "あ".repeat(MAX_TEXT_LENGTH) }).ok, true);
    assert.equal(parseEstimateRequest({ text: "あ".repeat(MAX_TEXT_LENGTH + 1) }).ok, false);
  });

  it("写真の種類はJPEG・PNG・WebP・HEIC・HEIFだけ", () => {
    for (const mimeType of ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]) {
      assert.equal(parseEstimateRequest({ image: { mimeType, data: "AAEC" } }).ok, true, mimeType);
    }
    assert.equal(parseEstimateRequest({ image: { mimeType: "image/gif", data: "AAEC" } }).ok, false);
    assert.equal(parseEstimateRequest({ image: { mimeType: "application/pdf", data: "AAEC" } }).ok, false);
  });

  it("写真がbase64でない・空・大きすぎるなら拒否", () => {
    assert.equal(parseEstimateRequest({ image: { mimeType: "image/jpeg", data: "not base64!" } }).ok, false);
    assert.equal(parseEstimateRequest({ image: { mimeType: "image/jpeg", data: "" } }).ok, false);
    const tooLarge = "A".repeat(MAX_IMAGE_BASE64_LENGTH + 1);
    const result = parseEstimateRequest({ image: { mimeType: "image/jpeg", data: tooLarge } });
    assert.equal(result.ok, false);
    assert.match((result as { message: string }).message, /大きすぎ/);
  });

  it("image: null は写真なしとして扱う", () => {
    assert.deepEqual(parseEstimateRequest({ text: "牛丼", image: null }), {
      ok: true,
      request: { text: "牛丼" },
    });
  });
});

describe("buildEstimateRequestBody", () => {
  it("ルールはsystemInstructionに、利用者の入力はuserのパートに分けて入れる", () => {
    const body = buildEstimateRequestBody({ text: "牛丼並盛と味噌汁" });

    assert.deepEqual(body.systemInstruction, { parts: [{ text: SYSTEM_INSTRUCTION }] });
    assert.equal(body.contents.length, 1);
    assert.equal(body.contents[0].role, "user");
    const userText = (body.contents[0].parts[0] as { text: string }).text;
    assert.match(userText, /牛丼並盛と味噌汁/);
    assert.equal(body.contents[0].parts.length, 1, "写真が無ければパートは文章だけ");
  });

  it("構造化出力（JSONスキーマ指定）・低めのtemperatureで呼ぶ", () => {
    const body = buildEstimateRequestBody({ text: "牛丼" });

    assert.deepEqual(body.generationConfig, {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0.2,
    });
  });

  it("写真はinlineDataのパートとして付ける", () => {
    const body = buildEstimateRequestBody({ text: "", image: { mimeType: "image/jpeg", data: "AAEC" } });

    assert.deepEqual(body.contents[0].parts[1], { inlineData: { mimeType: "image/jpeg", data: "AAEC" } });
    assert.match((body.contents[0].parts[0] as { text: string }).text, /写真/);
  });

  it("入力中の指示文に従わないことをシステム側で明示している（プロンプトインジェクション対策）", () => {
    assert.match(SYSTEM_INSTRUCTION, /指示や命令のような文/);
    assert.match(SYSTEM_INSTRUCTION, /items を空配列/);
  });

  it("スキーマは品目ごとに名前・量・kcal・PFCを必須にしている", () => {
    assert.deepEqual(RESPONSE_SCHEMA.properties.items.items.required, [
      "name",
      "amount",
      "calories",
      "protein",
      "fat",
      "carbs",
    ]);
  });
});

describe("parseNutritionResponse", () => {
  it("品目ごとに読み、kcalは整数・gは小数1桁に丸める", () => {
    const result = parseNutritionResponse(
      JSON.stringify({
        items: [{ name: " 牛丼 ", amount: "並盛", calories: 652.6, protein: 22.04, fat: 21.96, carbs: 90 }],
        note: "並盛として推定",
      }),
    );

    assert.deepEqual(result, {
      items: [{ name: "牛丼", amount: "並盛", calories: 653, protein: 22, fat: 22, carbs: 90 }],
      note: "並盛として推定",
    });
  });

  it("負の値・数値でない値は0、上限を超える値は上限に収める", () => {
    const result = parseNutritionResponse(
      JSON.stringify({
        items: [{ name: "謎の料理", amount: "", calories: 99999, protein: -3, fat: "12.5", carbs: null }],
        note: "",
      }),
    );

    assert.deepEqual(result?.items[0], {
      name: "謎の料理",
      amount: "",
      calories: 5000,
      protein: 0,
      fat: 12.5,
      carbs: 0,
    });
  });

  it("名前の無い品・オブジェクトでない要素は捨てる", () => {
    const result = parseNutritionResponse(
      JSON.stringify({ items: [{ name: "", calories: 100 }, "ラーメン", null, { name: "餃子", calories: 300 }] }),
    );

    assert.deepEqual(result?.items.map((i) => i.name), ["餃子"]);
    assert.equal(result?.items[0].amount, "", "amountが無ければ空文字");
  });

  it(`品目は${MAX_ITEMS}件まで`, () => {
    const items = Array.from({ length: MAX_ITEMS + 3 }, (_, i) => ({ name: `品${i}`, calories: 1 }));
    assert.equal(parseNutritionResponse(JSON.stringify({ items }))?.items.length, MAX_ITEMS);
  });

  it("長すぎる名前・量は切り詰める（絵文字を途中で切らない）", () => {
    const result = parseNutritionResponse(
      JSON.stringify({ items: [{ name: "🍜".repeat(70), amount: "あ".repeat(50), calories: 1 }] }),
    );

    assert.equal(Array.from(result!.items[0].name).length, 60);
    assert.equal(result!.items[0].name, "🍜".repeat(60));
    assert.equal(result!.items[0].amount.length, 40);
  });

  it("食べ物が無い（空配列）はそのまま返す", () => {
    assert.deepEqual(parseNutritionResponse('{"items":[],"note":"食べ物の説明が見つかりませんでした"}'), {
      items: [],
      note: "食べ物の説明が見つかりませんでした",
    });
  });

  it("コードブロックで包まれていても読む", () => {
    assert.equal(parseNutritionResponse('```json\n{"items":[{"name":"卵","calories":76}]}\n```')?.items[0].name, "卵");
  });

  it("JSONでない・itemsが配列でなければnull", () => {
    assert.equal(parseNutritionResponse("牛丼は650kcalです"), null);
    assert.equal(parseNutritionResponse('{"items":"牛丼"}'), null);
    assert.equal(parseNutritionResponse("[]"), null);
    assert.equal(parseNutritionResponse("null"), null);
  });
});
