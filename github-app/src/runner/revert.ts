// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { config } from "../config.js";

interface RunResult {
  code: number;
  out: string;
}

function run(cmd: string, args: string[], cwd: string): Promise<RunResult> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd, env: process.env });
    let out = "";
    child.stdout.on("data", (d) => (out += d.toString()));
    child.stderr.on("data", (d) => (out += d.toString()));
    child.on("close", (code) => resolve({ code: code ?? -1, out }));
    child.on("error", (err) => resolve({ code: -1, out: out + String(err) }));
  });
}

function authedUrl(cloneUrl: string, token: string): string {
  return cloneUrl.replace("https://", `https://x-access-token:${token}@`);
}

export interface RevertResult {
  ok: boolean;
  backupTag: string | null;
  restoredHead: string;
  log: string;
}

/**
 * Reset a branch to its most recent pre-rewrite backup tag and force-push.
 * Backup tags are created by fix-history.sh as `backup/<branch>-pre-*`.
 */
export async function runRevert(opts: {
  cloneUrl: string;
  branch: string;
  token: string;
}): Promise<RevertResult> {
  const workdir = await mkdtemp(join(tmpdir(), "dc-revert-"));
  const repoDir = join(workdir, "repo");
  const url = authedUrl(opts.cloneUrl, opts.token);
  let log = "";

  try {
    let r = await run("git", ["clone", "--", url, repoDir], workdir);
    log += r.out;
    if (r.code !== 0) {
      return { ok: false, backupTag: null, restoredHead: "", log };
    }

    // Fetch tags and pick the newest backup tag for this branch.
    await run("git", ["fetch", "--tags", "--force"], repoDir);
    const safeBranch = opts.branch.replace(/\//g, "-");
    const listed = (
      await run("git", ["tag", "-l", `backup/${opts.branch}-pre-*`, `backup/${safeBranch}-pre-*`], repoDir)
    ).out
      .trim()
      .split(/\r?\n/)
      .filter(Boolean)
      .sort();
    const backupTag = listed.length ? listed[listed.length - 1] : null;
    if (!backupTag) {
      return { ok: false, backupTag: null, restoredHead: "", log };
    }

    await run("git", ["checkout", "-B", opts.branch, `refs/tags/${backupTag}`], repoDir);
    const restoredHead = (await run("git", ["rev-parse", "HEAD"], repoDir)).out.trim();

    // The clone's origin already carries the tokenised URL, so push to origin.
    r = await run("git", ["push", "--force-with-lease", "origin", opts.branch], repoDir);
    log += r.out;

    return { ok: r.code === 0, backupTag, restoredHead, log };
  } finally {
    await rm(workdir, { recursive: true, force: true });
  }
}
