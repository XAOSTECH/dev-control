// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { App } from "octokit";
import { config } from "../config.js";
import { parseCommands } from "../commands.js";
import { handleFind } from "./commitSearch.js";
import { handleFixHistory } from "./fixHistory.js";
import { handleRevert } from "./revert.js";

/** Register webhook event handlers on the App instance. */
export function registerHandlers(app: App): void {
  app.webhooks.on("issue_comment.created", async ({ octokit, payload }) => {
    const body = payload.comment.body ?? "";
    const commands = parseCommands(body, config.commandPrefix);
    if (!commands.length) {
      return;
    }

    const owner = payload.repository.owner.login;
    const repo = payload.repository.name;
    const issueNumber = payload.issue.number;
    const commenter = payload.comment.user?.login ?? "";
    const installationId = payload.installation?.id;
    if (!installationId || !commenter) {
      return;
    }

    for (const cmd of commands) {
      try {
        if (cmd.name === "find") {
          await handleFind({ octokit, owner, repo, issueNumber, cmd });
        } else if (cmd.name === "revert") {
          await handleRevert({ app, octokit, owner, repo, installationId, issueNumber, commenter });
        } else {
          await handleFixHistory({ app, octokit, owner, repo, installationId, issueNumber, commenter, cmd });
        }
      } catch (err) {
        // Never let one command crash the webhook handler.
        console.error(`Command "${cmd.raw}" failed:`, err);
      }
    }
  });

  app.webhooks.onError((error) => {
    console.error("Webhook error:", error);
  });
}
