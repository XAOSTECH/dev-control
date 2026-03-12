# Action Templates

These action templates are maintained in `dev-control` and consumed by `dc init` when generating repository scaffolding.

The README in this folder is for maintainers editing templates in this repo. It is not copied into generated target repositories.

## Current Template

- `identity/action.yml`: composite action used by multiple workflow templates to set bot git identity and optionally configure GPG signing.

## How `identity` Is Used

- Workflow templates call this action to configure `git config user.name` and `git config user.email` for bot commits.
- If GPG material is provided, it imports the key and enables commit/tag signing.
- If `user-token` is provided, it can register the bot public GPG key with GitHub for verified signatures.

## Required Inputs and Typical Secret/Var Mapping

- `gpg-private-key` -> `${{ secrets['{{GPG_PRIVATE_KEY_SECRET}}'] }}`
- `gpg-passphrase` -> `${{ secrets['{{GPG_PASSPHRASE_SECRET}}'] }}`
- `user-token` -> `${{ secrets['{{USER_TOKEN_SECRET}}'] }}` (classic PAT with `write:gpg_key` for key registration)
- `bot-name` -> `${{ vars.BOT_NAME || '{{BOT_NAME}}' }}`
- `bot-email` -> defaults to `{{BOT_EMAIL}}` (override when needed)

Store these as org-level secrets/vars when shared across repos, or repo-level when scoped per repository.

For template conventions and broader context, see the templates folders in:
<https://github.com/XAOSTECH/dev-control>
