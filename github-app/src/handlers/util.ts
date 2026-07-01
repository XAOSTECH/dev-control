// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { Octokit } from "octokit";

/** Post a comment on an issue or pull request. */
export async function comment(
  octokit: Octokit,
  owner: string,
  repo: string,
  issueNumber: number,
  body: string,
): Promise<void> {
  await octokit.rest.issues.createComment({
    owner,
    repo,
    issue_number: issueNumber,
    body,
  });
}

/** Keep only the last `n` characters of a (potentially large) log. */
export function tail(text: string, n = 2000): string {
  return text.length > n ? `…${text.slice(-n)}` : text;
}

/** Resolve a pull request's head ref and clone URL from an issue/PR number. */
export async function resolvePrHead(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
): Promise<{ branch: string; cloneUrl: string } | null> {
  try {
    const pr = await octokit.rest.pulls.get({ owner, repo, pull_number: prNumber });
    const head = pr.data.head;
    if (!head.repo) {
      return null;
    }
    return { branch: head.ref, cloneUrl: head.repo.clone_url };
  } catch {
    return null;
  }
}
