// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import "dotenv/config";
import { fileURLToPath } from "node:url";

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function resolvePrivateKey(): string {
  const b64 = process.env.PRIVATE_KEY_BASE64;
  if (b64) {
    return Buffer.from(b64, "base64").toString("utf8");
  }
  // Support keys stored with literal "\n" sequences in a single-line env var
  return required("PRIVATE_KEY").replace(/\\n/g, "\n");
}

export const config = {
  appId: required("APP_ID"),
  privateKey: resolvePrivateKey(),
  webhookSecret: required("WEBHOOK_SECRET"),
  port: Number(process.env.PORT ?? 3000),
  botName: process.env.APP_BOT_NAME ?? "dev-control[bot]",
  botEmail: process.env.APP_BOT_EMAIL ?? "dev-control[bot]@users.noreply.github.com",
  commandPrefix: process.env.COMMAND_PREFIX ?? "/dc",
  // ../scripts/fix-history.sh relative to this file (src/config.ts → repo root)
  fixHistoryScript:
    process.env.DC_FIX_HISTORY ??
    fileURLToPath(new URL("../../scripts/fix-history.sh", import.meta.url)),
} as const;
