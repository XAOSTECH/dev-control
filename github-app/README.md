<!--
SPDX-Licence-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2025-2026 xaoscience
-->

# Dev-Control GitHub App

A GitHub App that surfaces dev-control's history tooling directly inside
GitHub. It listens for slash commands in pull-request / issue comments and
runs the existing [`scripts/fix-history.sh`](../scripts/fix-history.sh) logic in
a sandboxed worker clone, then reports a clear before/after state with a
one-click revert.

It deliberately **reuses the dev-control bash scripts** rather than
re-implementing history rewriting in JS — history rewrites need a real clone +
`git`, which only the scripts do safely. That is the whole reason this app lives
inside the dev-control monorepo (so the worker can call `../scripts/...`).

## Commands

Comment on a pull request:

| Command | Action |
| --- | --- |
| `/dc find <keyword>` | Search the repo's commit history for a keyword (read-only). |
| `/dc combine <A> <B>` | Fuse two adjacent commits into one (`--combine`). |
| `/dc drop <A> [B …]` | Drop one or more commits (`--drop`). |
| `/dc dedu` | Squash consecutive identical-message commits (`--dedu`). |
| `/dc sign` | Re-sign the branch's commits (`--sign`). |
| `/dc revert` | Reset the branch to the most recent pre-rewrite backup tag. |

Append `--sign` to `combine` / `drop` / `dedu` to re-sign the rewritten commits.

Rewrite commands require the commenter to have **write** access to the repo.

## Architecture

```
github-app/
  app.manifest.yml        GitHub App manifest (permissions + events)
  src/
    server.ts             webhook entry (octokit App + node middleware)
    config.ts             env / secrets loading
    commands.ts           parse "/dc <name> <args>" from comment bodies
    auth.ts               permission check + installation token
    handlers/
      index.ts            event registration + routing
      util.ts             comment / log helpers
      commitSearch.ts     /dc find
      fixHistory.ts       /dc combine|drop|dedu|sign
      revert.ts           /dc revert
    runner/
      runDc.ts            clone → run fix-history.sh → capture pre/post → push
      revert.ts           clone → reset to backup tag → force-push
```

The worker authenticates the clone with a short-lived **installation access
token** (`https://x-access-token:<token>@github.com/...`), so no SSH keys are
needed. `fix-history.sh` itself performs the `git push --force-with-lease`.

## Local development

```bash
cd github-app
cp .env.example .env        # fill APP_ID, PRIVATE_KEY, WEBHOOK_SECRET
npm install
npm run dev                 # tsx watch; expose with a tunnel (smee/ngrok)
```

Point the App's webhook URL at `https://<tunnel>/api/github/webhooks`.

## Production

```bash
npm run build && npm start
# or
docker build -t dev-control-github-app .
```

A scoped CI workflow can deploy only this folder with
`on: { push: { paths: ['github-app/**'] } }`.

## Security notes

- Webhook payloads are signature-verified by `@octokit/webhooks` via the App.
- Rewrite commands are gated on the commenter's write permission.
- Every rewrite creates a `backup/<branch>-pre-*` tag (pushed), enabling
  `/dc revert`.
- Worker clones live in a `mkdtemp` dir and are removed in a `finally` block.
