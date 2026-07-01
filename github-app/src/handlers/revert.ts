// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { App, Octokit } from "octokit";
import { hasWriteAccess, installationToken } from "../auth.js";
import { runRevert } from "../runner/revert.js";
import { comment, resolvePrHead } from "./util.js";

/** `/dc revert` — reset the PR branch to its most recent pre-rewrite backup tag. */
export async function handleRevert(ctx: {
  app: App;
  octokit: Octokit;
  owner: string;
  repo: string;
  installationId: number;
  issueNumber: number;
  commenter: string;
}): Promise<void> {
  const { app, octokit, owner, repo, installationId, issueNumber, commenter } = ctx;

  if (!(await hasWriteAccess(octokit, owner, repo, commenter))) {
    await comment(octokit, owner, repo, issueNumber, `@${commenter} you need write access to run \`revert\`.`);
    return;
  }

  const head = await resolvePrHead(octokit, owner, repo, issueNumber);
  if (!head) {
    await comment(octokit, owner, repo, issueNumber, "`/dc revert` must be run on a pull request.");
    return;
  }

  const token = await installationToken(app, installationId);
  const result = await runRevert({ cloneUrl: head.cloneUrl, branch: head.branch, token });

  if (!result.ok || !result.backupTag) {
    await comment(
      octokit,
      owner,
      repo,
      issueNumber,
      `:warning: No pre-rewrite backup tag found for \`${head.branch}\`; nothing to revert.`,
    );
    return;
  }

  await comment(
    octokit,
    owner,
    repo,
    issueNumber,
    `:rewind: Reverted \`${head.branch}\` to backup \`${result.backupTag}\` (now at \`${result.restoredHead.slice(0, 7)}\`).`,
  );
}
