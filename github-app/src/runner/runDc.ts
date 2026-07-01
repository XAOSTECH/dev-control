// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import { spawn } from "node:child_process";
import { access, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { config } from "../config.js";

export interface DcRunResult {
  ok: boolean;
  preHead: string;
  postHead: string;
  backupTag: string | null;
  changed: boolean;
  log: string;
}

interface RunResult {
  code: number;
  out: string;
}

function run(
  cmd: string,
  args: string[],
  cwd: string,
  env?: NodeJS.ProcessEnv,
  stdin?: string,
): Promise<RunResult> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd, env: { ...process.env, ...env } });
    let out = "";
    child.stdout.on("data", (d) => (out += d.toString()));
    child.stderr.on("data", (d) => (out += d.toString()));
    if (stdin !== undefined) {
      child.stdin.write(stdin);
      child.stdin.end();
    }
    child.on("close", (code) => resolve({ code: code ?? -1, out }));
    child.on("error", (err) => resolve({ code: -1, out: out + String(err) }));
  });
}

const git = (args: string[], cwd: string) => run("git", args, cwd);

function authedUrl(cloneUrl: string, token: string): string {
  return cloneUrl.replace("https://", `https://x-access-token:${token}@`);
}

/**
 * Clone the target branch into a throwaway dir, run fix-history.sh with the
 * given arguments (answering interactive prompts with "y" so it force-pushes),
 * and report the before/after HEAD plus any backup tag created.
 */
export async function runDc(opts: {
  cloneUrl: string;
  branch: string;
  token: string;
  dcArgs: string[];
}): Promise<DcRunResult> {
  await access(config.fixHistoryScript).catch(() => {
    throw new Error(`fix-history.sh not found at ${config.fixHistoryScript}`);
  });

  const workdir = await mkdtemp(join(tmpdir(), "dc-app-"));
  const repoDir = join(workdir, "repo");
  let log = "";

  try {
    let r = await run(
      "git",
      ["clone", "--branch", opts.branch, "--", authedUrl(opts.cloneUrl, opts.token), repoDir],
      workdir,
    );
    log += r.out;
    if (r.code !== 0) {
      return { ok: false, preHead: "", postHead: "", backupTag: null, changed: false, log };
    }

    await git(["config", "user.name", config.botName], repoDir);
    await git(["config", "user.email", config.botEmail], repoDir);

    const preHead = (await git(["rev-parse", "HEAD"], repoDir)).out.trim();

    // fix-history.sh is interactive; feed "y" for the confirm + push prompts.
    r = await run(
      "bash",
      [config.fixHistoryScript, ...opts.dcArgs, "--no-cleanup"],
      repoDir,
      { NO_EDIT_MODE: "true" },
      "y\ny\ny\ny\n",
    );
    log += r.out;

    const postHead = (await git(["rev-parse", "HEAD"], repoDir)).out.trim();
    const tagsOut = (await git(["tag", "-l", "backup/*"], repoDir)).out.trim();
    const tags = tagsOut ? tagsOut.split(/\r?\n/).filter(Boolean) : [];
    const backupTag = tags.length ? tags[tags.length - 1] : null;

    return {
      ok: r.code === 0,
      preHead,
      postHead,
      backupTag,
      changed: preHead !== "" && preHead !== postHead,
      log,
    };
  } finally {
    await rm(workdir, { recursive: true, force: true });
  }
}
