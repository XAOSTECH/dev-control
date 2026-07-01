// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { App, Octokit } from "octokit";
import { hasWriteAccess, installationToken } from "../auth.js";
import type { ParsedCommand } from "../commands.js";
import { splitArgs } from "../commands.js";
import { runDc } from "../runner/runDc.js";
import { comment, resolvePrHead, tail } from "./util.js";

/** Map a parsed `/dc` command to fix-history.sh arguments, or null if invalid. */
export function buildDcArgs(cmd: ParsedCommand): string[] | null {
  const { positionals, flags } = splitArgs(cmd.args);
  const sign = flags.has("--sign") ? ["--sign"] : [];

  switch (cmd.name) {
    case "combine":
      if (positionals.length !== 2) return null;
      return ["--combine", positionals[0], positionals[1], ...sign];

    case "drop":
      if (positionals.length < 1) return null;
      // fix-history --drop accepts one or more commits (newest-first internally)
      return ["--drop", ...positionals, ...sign];

    case "dedu":
    case "deduplicate":
      return ["--dedu", ...sign];

    case "sign":
      return ["--sign"];

    default:
      return null;
  }
}

/** `/dc combine|drop|dedu|sign` — run a history rewrite on the PR branch. */
export async function handleFixHistory(ctx: {
  app: App;
  octokit: Octokit;
  owner: string;
  repo: string;
  installationId: number;
  issueNumber: number;
  commenter: string;
  cmd: ParsedCommand;
}): Promise<void> {
  const { app, octokit, owner, repo, installationId, issueNumber, commenter, cmd } = ctx;

  if (!(await hasWriteAccess(octokit, owner, repo, commenter))) {
    await comment(octokit, owner, repo, issueNumber, `@${commenter} you need write access to run \`${cmd.name}\`.`);
    return;
  }

  const dcArgs = buildDcArgs(cmd);
  if (!dcArgs) {
    await comment(octokit, owner, repo, issueNumber, `Invalid usage of \`/dc ${cmd.name}\`. See the README for syntax.`);
    return;
  }

  const head = await resolvePrHead(octokit, owner, repo, issueNumber);
  if (!head) {
    await comment(octokit, owner, repo, issueNumber, `\`/dc ${cmd.name}\` must be run on a pull request (with a head branch in this repo).`);
    return;
  }

  await comment(octokit, owner, repo, issueNumber, `:hourglass_flowing_sand: Running \`${cmd.raw}\` on \`${head.branch}\`…`);

  const token = await installationToken(app, installationId);
  const result = await runDc({ cloneUrl: head.cloneUrl, branch: head.branch, token, dcArgs });

  if (!result.ok || !result.changed) {
    await comment(
      octokit,
      owner,
      repo,
      issueNumber,
      `:warning: \`${cmd.raw}\` did not rewrite history.\n\n<details><summary>log</summary>\n\n\`\`\`\n${tail(result.log)}\n\`\`\`\n</details>`,
    );
    return;
  }

  const revertLine = result.backupTag
    ? `\n\nRevert with \`/dc revert\` _(backup \`${result.backupTag}\`)_.`
    : "";

  await comment(
    octokit,
    owner,
    repo,
    issueNumber,
    `:white_check_mark: \`${cmd.raw}\` complete on \`${head.branch}\`.\n\n` +
      `**Before:** \`${result.preHead.slice(0, 7)}\` → **After:** \`${result.postHead.slice(0, 7)}\`${revertLine}`,
  );
}
