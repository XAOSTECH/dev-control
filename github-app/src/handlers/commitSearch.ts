// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { Octokit } from "octokit";
import type { ParsedCommand } from "../commands.js";
import { comment } from "./util.js";

/** `/dc find <keyword>` — search the repo's commit history (read-only). */
export async function handleFind(ctx: {
  octokit: Octokit;
  owner: string;
  repo: string;
  issueNumber: number;
  cmd: ParsedCommand;
}): Promise<void> {
  const { octokit, owner, repo, issueNumber, cmd } = ctx;
  const keyword = cmd.args.join(" ").trim();

  if (!keyword) {
    await comment(octokit, owner, repo, issueNumber, "Usage: `/dc find <keyword>`");
    return;
  }

  const res = await octokit.rest.search.commits({
    q: `repo:${owner}/${repo} ${keyword}`,
    per_page: 10,
  });

  if (!res.data.items.length) {
    await comment(octokit, owner, repo, issueNumber, `No commits matching \`${keyword}\`.`);
    return;
  }

  const lines = res.data.items.map((item) => {
    const sha = item.sha.slice(0, 7);
    const subject = item.commit.message.split("\n", 1)[0];
    return `- [\`${sha}\`](${item.html_url}) ${subject}`;
  });

  await comment(
    octokit,
    owner,
    repo,
    issueNumber,
    `**Commits matching \`${keyword}\`** (top ${lines.length}):\n${lines.join("\n")}`,
  );
}
