# Code Signing with SignPath.io

Dev-control integrates **Authenticode code signing** via [SignPath.io](https://signpath.io) to eliminate Windows SmartScreen warnings on release binaries.

## How It Works

| Layer | Tool | Purpose                               |
|-------|------|---------------------------------------|
| GPG   | `identity` action | Signs git commits and tags → provenance |
| Authenticode | SignPath.io | Signs `.exe`/`.dll`/`.msi` → SmartScreen trust |

Both coexist — GPG proves *who committed*, Authenticode proves *who built the binary*.

The signing step is **optional and gracefully degrading**. If SignPath isn't configured, it skips with a warning instead of failing the release.

## Flow

```
build-*.yml → [Sign build artefacts] → Create GitHub Release
              (only when sign_artifacts: true)
```

After build workflows complete and artefacts are downloaded into `dist/`, the release workflow:

1. Finds all `.exe`, `.dll`, `.msi` files in `dist/`
2. Submits each to SignPath via REST API
3. Polls for completion (up to 10 minutes per file)
4. Replaces unsigned files with signed versions
5. Regenerates `SHA256SUMS.txt` from signed binaries
6. Adds a "Verification" section to release notes

## Org-Level Setup (One Time)

1. **Register** at [signpath.io/open-source](https://signpath.io/open-source) for XAOSTECH
2. **Install** the SignPath GitHub App on the XAOSTECH organisation
3. **Create a signing policy** called `release-signing`
4. **Create artefact configurations** for each format:

   | Slug | Format | Use Case |
   |------|--------|----------|
   | `exe` | Authenticode PE | `.exe`, `.dll` files |
   | `msi` | Authenticode MSI | Windows installers |
   | `ps1` | Authenticode script | PowerShell scripts |

5. **Store org-level configuration:**
   - **Org variable:** `SIGNPATH_ORG_ID` — your SignPath organisation ID
   - **Org secret:** `SIGNPATH_API_TOKEN` — API token from SignPath dashboard

## Per-Repo Setup

Each repo that wants signing needs:

1. **Create a SignPath project** in the XAOSTECH SignPath dashboard for the repo
2. **Set repo variable:** `SIGNPATH_PROJECT_SLUG` — the project slug (e.g. `egs-ll`)
3. **Trigger with signing enabled:**
   - Manual dispatch: check "Sign Windows binaries via SignPath.io"
   - Or set `sign_artifacts: true` in the workflow dispatch

No additional secrets are needed per-repo — the org secret `SIGNPATH_API_TOKEN` is inherited.

### Example: EGS-LL

| Setting | Value |
|---------|-------|
| Repo variable: `SIGNPATH_PROJECT_SLUG` | `egs-ll` |
| Build workflow | `build-gui.yml` (produces `EGS-LL-gui` artefact with `.exe`) |
| Artefact configuration | `exe` |
| Dispatch option | `sign_artifacts: true` |

## Verification

After a signed release, users can verify binaries:

**PowerShell:**
```powershell
Get-AuthenticodeSignature .\YourFile.exe | Format-List *
```

**Expected output:** `Status: Valid`, `SignerCertificate` issued to XAOSTECH.

## Standalone Workflow

For repos that want to sign artefacts outside the release flow, `sign-artifacts.yml` is available as a reusable `workflow_call` workflow:

```yaml
jobs:
  sign:
    uses: ./.github/workflows/sign-artifacts.yml
    with:
      artifact_name: my-build
      artifact_configuration: exe
    permissions:
      id-token: write
      actions: read
```

See [workflows-templates/sign-artifacts.yml](../workflows-templates/sign-artifacts.yml) for full input/output documentation.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "SIGNPATH_ORG_ID not set — skipping" | Org variable missing | Add `SIGNPATH_ORG_ID` in org settings → Variables |
| "SIGNPATH_PROJECT_SLUG not set" | Repo variable missing | Add `SIGNPATH_PROJECT_SLUG` in repo settings → Variables |
| "SIGNPATH_API_TOKEN secret not set" | Org secret missing | Add `SIGNPATH_API_TOKEN` in org settings → Secrets |
| "No signable files found" | Build doesn't produce `.exe`/`.dll`/`.msi` | Check your `build-*.yml` uploads the right files |
| "Signing timed out" | SignPath queue or processing delay | Retry the release, or increase poll timeout |
| "Signing denied" | Policy or project misconfiguration | Check SignPath dashboard for the signing request |
