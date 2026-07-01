// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import type { App, Octokit } from "octokit";

const WRITE_LEVELS = new Set(["admin", "write", "maintain"]);

/** True when the user has write-equivalent permission on the repository. */
export async function hasWriteAccess(
  octokit: Octokit,
  owner: string,
  repo: string,
  username: string,
): Promise<boolean> {
  try {
    const res = await octokit.rest.repos.getCollaboratorPermissionLevel({
      owner,
      repo,
      username,
    });
    return WRITE_LEVELS.has(res.data.permission);
  } catch {
    return false;
  }
}

/** Mint a short-lived installation access token for git operations. */
export async function installationToken(app: App, installationId: number): Promise<string> {
  const res = await app.octokit.rest.apps.createInstallationAccessToken({
    installation_id: installationId,
  });
  return res.data.token;
}
