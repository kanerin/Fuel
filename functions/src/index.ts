import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

import { handleDeleteAccount } from "./delete_account";
import { handleEstimateNutrition } from "./estimate_nutrition";

// 東京リージョン。アプリ側（lib/services/firebase_bootstrap.dart の
// kFunctionsRegion）と揃えること。maxInstances は、万一大量に呼ばれたときに
// Geminiの利用料が青天井にならないための上限。
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });

initializeApp();
const db = getFirestore();

// Gemini APIキーはアプリに埋め込まず、Secret Manager に置く
// （firebase functions:secrets:set GEMINI_API_KEY）。
const geminiApiKey = defineSecret("GEMINI_API_KEY");

// ── 食べたもの（文章・写真）からPFCを推定する ─────────────────
export const estimateNutrition = onCall({ secrets: [geminiApiKey], timeoutSeconds: 60 }, (request) =>
  handleEstimateNutrition({ db, apiKey: geminiApiKey.value() }, request.auth?.uid, request.data),
);

// ── 退会: アカウントと全データを削除する ───────────────────────
export const deleteAccount = onCall((request) =>
  handleDeleteAccount({ db, auth: getAuth() }, request.auth?.uid),
);
