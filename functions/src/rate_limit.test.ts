import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { isOverLimit, nextRateLimitState, tokyoDateKey } from "./rate_limit";

describe("tokyoDateKey", () => {
  it("Asia/Tokyoの日付（UTCの15時で日付が変わる）", () => {
    assert.equal(tokyoDateKey(new Date("2026-10-21T14:59:59Z")), "2026-10-21");
    assert.equal(tokyoDateKey(new Date("2026-10-21T15:00:00Z")), "2026-10-22");
  });
});

describe("isOverLimit", () => {
  it("記録が無ければ許可", () => {
    assert.equal(isOverLimit(undefined, "2026-10-21", 50), false);
  });

  it("日付が変わっていれば前日のカウントを引き継がない", () => {
    assert.equal(isOverLimit({ date: "2026-10-20", count: 999 }, "2026-10-21", 50), false);
  });

  it("上限未満なら許可、上限ちょうどで拒否", () => {
    assert.equal(isOverLimit({ date: "2026-10-21", count: 49 }, "2026-10-21", 50), false);
    assert.equal(isOverLimit({ date: "2026-10-21", count: 50 }, "2026-10-21", 50), true);
    assert.equal(isOverLimit({ date: "2026-10-21", count: 55 }, "2026-10-21", 50), true);
  });
});

describe("nextRateLimitState", () => {
  it("記録が無ければ1件目", () => {
    assert.deepEqual(nextRateLimitState(undefined, "2026-10-21"), { date: "2026-10-21", count: 1 });
  });

  it("同じ日なら1増やす", () => {
    assert.deepEqual(nextRateLimitState({ date: "2026-10-21", count: 4 }, "2026-10-21"), {
      date: "2026-10-21",
      count: 5,
    });
  });

  it("日付が変わっていれば1からやり直す", () => {
    assert.deepEqual(nextRateLimitState({ date: "2026-10-20", count: 50 }, "2026-10-21"), {
      date: "2026-10-21",
      count: 1,
    });
  });
});
