# Workflow Templates

These workflow templates are maintained in `dev-control` and consumed by `dc init` when generating repository scaffolding.

This README is for maintainers editing templates in this repo. It is not copied into generated target repositories.

## Included Workflows

- `init.yml`: initial repository/docs/license/bootstrap workflow with placeholder replacement.
- `remote-init.yml`: example caller for the reusable central loader workflow.
- `bash-lint.yml`: baseline bash linting for push/PR/manual runs.
- `bash-lint-advanced.yml`: linting with auto-fix PR flow and security app token usage.
- `codeql.yml`: advanced code scanning on PR/schedule/manual.
- `validate-pr.yml`: unprivileged PR validation gate used by automerge.
- `automerge.yml`: privileged merge workflow triggered after successful `Validate PR for Automerge`.
- `anglicise.yml`: automated UK spelling updates with PR creation.
- `replace.yml`: search/replace automation with PR creation.
- `update.yml`: scheduled/manual dependency/repo maintenance automation.
- `release.yml`: release/tag/changelog automation.
- `security-autofix.yml`: CodeQL-driven autofix workflow and security PR creation.

## Requisites by Template

- Needs bot app credentials (`anglicise`, `replace`, `update`, `release`):
`{{BOT_APP_ID_SECRET}}`, `{{BOT_PRIVATE_KEY_SECRET}}`.
- Needs security app credentials (`bash-lint-advanced`):
`{{SECURITY_APP_ID_SECRET}}`, `{{SECURITY_PRIVATE_KEY_SECRET}}`.
- Needs identity signing inputs (templates using the identity action):
`{{GPG_PRIVATE_KEY_SECRET}}`, `{{GPG_PASSPHRASE_SECRET}}`, `{{USER_TOKEN_SECRET}}`, and `vars.BOT_NAME`.
- `codeql.yml` and `security-autofix.yml` require Code Scanning/Advanced Security features to be enabled.
- `security-autofix.yml` currently expects `secrets.XSS_AI` and `secrets.XSS_PK` as its app credentials.
- `automerge.yml` depends on `validate-pr.yml` and uses local action path `./.github/actions/identity` in generated repos.
- `remote-init.yml` is an example workflow calling `xaoscience/dev-control/.github/workflows/central-loader.yml@main`; adjust owner/ref for your environment.

For template conventions and broader context, see the templates folders in:
<https://github.com/XAOSTECH/dev-control>
