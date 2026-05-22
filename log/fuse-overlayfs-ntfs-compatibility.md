# FUSE-Overlayfs / NTFS Compatibility - Findings & Survival Guide

> Operational log of the rootless-podman-on-NTFS investigation. Steps required to keep the `containerise.sh` flow working across NTFS driver choices and `fuse-overlayfs` versions.

## TL;DR

```
podman ──▶ fuse-overlayfs (userspace) ──▶ user.* xattrs ──▶ NTFS driver ──▶ disk
                 │                              │                 │
                 │                              │                 ├── ntfs-3g (FUSE, fuseblk)
                 │                              │                 └── ntfs3   (kernel, since 5.15)
                 │                              └── ADS-backed; both drivers OK
                 └── only the `1.13-dev` binary is known to misbehave (see below)
```

Project is **driver-agnostic** at the NTFS layer and **largely version-agnostic** for `fuse-overlayfs` itself: the flow has worked on releases ranging from `1.7.x` through current upstream. The single known regression is the `1.13-dev` development snapshot, which strips mode bits on `copy_up`. Anything that is not that specific snapshot - older stable releases, or `1.14+` - has worked here.

## The fuse-overlayfs 1.13-dev xattr regression

On one upgrade path (Ubuntu 25.10 → 26.04 LTS) the `fuse-overlayfs` binary at `/usr/bin/fuse-overlayfs` began self-reporting `version 1.13-dev` despite the source package being labelled `1.14-1build2`. The same workstation on 25.10 (`1.14-1build1`) had not exhibited the bug.
Verified data points so far:

| Suite | Source package | Binary `--version` | Status |
|---|---|---|---|
| questing (25.10) | `fuse-overlayfs 1.14-1build1` | (this host: worked; string not captured) | no symptoms here |
| resolute (26.04 LTS) | `fuse-overlayfs 1.14-1build2` | `1.13-dev` | **confirmed broken on this host** |
| noble, stonking, others | (per `packages.ubuntu.com`) | not measured | unverified |

The `1.13-dev` binary predates the xattr-permission fixes from PRs [#408](https://github.com/containers/fuse-overlayfs/pull/408) / [#409](https://github.com/containers/fuse-overlayfs/pull/409) / [#410](https://github.com/containers/fuse-overlayfs/pull/410) (issue [containers/fuse-overlayfs#407](https://github.com/containers/fuse-overlayfs/issues/407)), so when present it does strip mode bits on `copy_up`.

**Diagnostic is the binary, not the package.** Run `fuse-overlayfs --version`; if it prints `1.13-dev`, treat the binary as suspect regardless of `apt` / `dpkg` metadata. If it prints anything else, no action needed.

**Operational impact is small once diagnosed:** one line in `~/.config/containers/storage.conf` (`mount_program = "/usr/local/bin/fuse-overlayfs"` after installing the upstream binary) plus `podman system reset -f`.

| Symptom inside container | Real cause |
|---|---|
| `sudo: must be owned by uid 0 and have the setuid bit set` | `copy_up` drops the `user.containers.override_stat` xattr → `stat /usr/bin/sudo` returns the real on-disk `-rwxr-xr-x` instead of the emulated `-rwsr-xr-x` |
| `error: could not lock config file /home/<u>/.gitconfig: Permission denied` | Same xattr stripping makes `/home/<u>` appear root-owned at runtime |
| `gpg: WARNING: unsafe permissions on homedir` | Same - `.gnupg` mode reverts to on-disk `0755` |
| `docker exec -u root $CID chmod u+s ...` exits 0 but has no effect | Cached layer's xattr is poisoned; chmod can't restore something the driver immediately re-emulates from broken state |

**Cached layers built while the `1.13-dev` binary was active carry the broken xattrs forward.** No `chmod` / `chown` from inside the container fixes them - the driver re-emulates the corrupted state on every `copy_up`. Recovery requires switching to a binary that does not self-report `1.13-dev` *and* wiping the affected layer cache.

## Preemptive setup (one-time, per host)

### Pick a driver binary, then point `storage.conf` at it

Two viable installation paths. Pick one; the `mount_program` line in `storage.conf` must match.

| Source | Install path | `mount_program` value | Notes |
|---|---|---|---|
| Distro package (`apt install fuse-overlayfs`) | `/usr/bin/fuse-overlayfs` | `"/usr/bin/fuse-overlayfs"` | Default and recommended whenever `fuse-overlayfs --version` does NOT print `1.13-dev`. |
| Upstream release binary | `/usr/local/bin/fuse-overlayfs` | `"/usr/local/bin/fuse-overlayfs"` | Workaround when the distro binary self-reports `1.13-dev`. Also useful for staying ahead of distro lag. |

Upstream install command (only needed when the distro binary self-reports `1.13-dev`):

```sh
curl -L -o /usr/local/bin/fuse-overlayfs \
  https://github.com/containers/fuse-overlayfs/releases/download/v1.16/fuse-overlayfs-x86_64
chmod +x /usr/local/bin/fuse-overlayfs
```

### `~/.config/containers/storage.conf`

```toml
[storage]
driver    = "overlay"
graphroot = "/mnt/drive1/.data/containers"   # any FS with user.* xattrs
runroot   = "/run/user/1000/containers"
[storage.options.overlay]
mount_program = "/usr/local/bin/fuse-overlayfs"  # or /usr/bin/... per table above
```

### Verify

```sh
podman info | grep -A6 mount_program     # must NOT report 1.13-dev
fuse-overlayfs --version                  # primary diagnostic
```

### Wipe poisoned cache after a driver swap

```sh
podman system reset -f        # then optionally:
rm -rf "$graphroot"/*         # residual .lock files are safe to remove
```

## NTFS driver choice - both supported, neither required

| Aspect | `ntfs-3g` (FUSE userspace) | `ntfs3` (kernel, ≥ 5.15) |
|---|---|---|
| `mount` fstype | `fuseblk` | `ntfs3` |
| `user.*` xattrs (req'd by fuse-overlayfs) | ✅ via NTFS Alternate Data Streams | ✅ via NTFS Alternate Data Streams |
| Speed under build load | baseline (extra userspace round-trip) | ~2–4× faster on metadata-heavy ops |
| Dirty-bit (Windows unclean shutdown) | Auto-replays journal, mounts | Refuses RW unless `force` / `nojournal` |
| Repair tool (`ntfsfix`) | Ships with the package | Not provided - depends on ntfs-3g pkg |
| Notable CVE history | LPE class CVEs (CVE-2022-30783..30790) - **only exploitable when setuid-root**; modern Ubuntu installs without setuid bit | None of comparable severity |
| `hiberfil.sys` / Windows Fast Startup | Refuses RW, offers `remove_hiberfile` | Refuses RW |

**Recommended posture for dual-boot dev workstation**:

- `ntfs3` in fstab for daily speed.
- Keep `ntfs-3g` *package* installed for `ntfsfix`.
- Disable Windows Fast Startup (Control Panel → Power Options) - eliminates the dominant source of dirty-bit events.
- On rare dirty-bit failure: `sudo ntfsfix /dev/...` then remount. Never put `force,nojournal` in fstab.

`force` / `nojournal` trade-offs (use only ad-hoc):

| Option | What it does | Cost |
|---|---|---|
| `force` | Mount RW despite dirty bit; journal still present | Writes near pending Windows transactions can corrupt; chkdsk will struggle later |
| `nojournal` | Skip journal replay entirely | Silently discards any in-flight Windows transactions |
| both | Maximum override | Use only for forensic recovery |

## Compatibility within `containerise.sh`

The flow makes **no NTFS-driver-specific decisions**. Same `storage.conf`, same Dockerfiles, same runtime behaviour regardless of `ntfs-3g` vs `ntfs3` under graphRoot, because every interaction with the on-disk layer goes through the `user.*` xattr API which both drivers expose identically.

Switching the NTFS driver after a successful rebuild is safe:

1. `podman stop -a`
2. `umount /mnt/drive1 && mount /mnt/drive1`  (fstab change in between)
3. Round-trip test:
   ```sh
   f=$(mktemp -p /mnt/drive1/.data/containers) \
     && setfattr -n user.test -v hi "$f" \
     && getfattr -n user.test "$f"; rm -f "$f"
   ```
4. Resume podman.

No image rebuild required for the driver swap alone.

## Resolved / non-issues

- **NTFS-3g xattr capacity** verified round-tripping `user.containers.override_stat` and `user.overlay.opaque` on `/mnt/drive1`. Both drivers handle the sizes podman writes.
- **`force_mask` in storage.conf** not set in this project; do not enable (drove issue #407's reproducer).

## Notes

- Development is moving back to a ntfs3 filesystem, please append any future incompatabilities with a ntfs-3g configuration to this file.