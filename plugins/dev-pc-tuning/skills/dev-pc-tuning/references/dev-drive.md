# Dev Drive (ReFS)

## What it is

A Dev Drive is a ReFS volume that Windows 11 (22H2 build 22621.2338 or later) marks as a
developer volume. Two things make it faster for builds than an NTFS folder on C:

- **Defender performance mode.** On a *trusted* Dev Drive, Defender scans files
  asynchronously (it opens the file for the build first and scans afterwards) instead of
  blocking each open. Builds create and open huge numbers of small files, so this is where
  most of the gain comes from. Real-time protection stays on.
- **ReFS block cloning.** Copies within the same ReFS volume can share blocks instead of
  duplicating data. Since Windows 11 24H2 the standard copy APIs (Explorer, `copy`,
  `Copy-Item`, `CopyFile`) do this automatically on a Dev Drive, so copying a big fixture
  folder or a packaged build is near-instant and costs no extra space. Tools that copy by
  reading and writing bytes themselves don't benefit. Nothing to configure.

Performance mode exists **only** for Dev Drives and only when Defender is the active
antivirus; with another antivirus product, see the end of `defender.md`.

Microsoft's published figures are "up to ~30%" faster builds; real gains depend on how much
of the build time is file I/O and scanning. Measure (see `defender.md`).

## Checks (read-only)

```powershell
fsutil devdrv query            # global: Dev Drive enabled? AV filter attached?
fsutil devdrv query D:         # per volume (admin; "Access is denied" otherwise): dev volume? trusted? filters
Get-Volume | Format-Table DriveLetter, FileSystem, FileSystemLabel, Size, SizeRemaining
Get-MpPreference | Select PerformanceModeStatus   # 0 = enabled, 1 = disabled
```

## Creating one

Formatting erases the volume, so this is always the user's step:

- **Settings > System > Storage > Advanced storage settings > Disks & volumes > Create Dev
  Drive** - on unallocated space, by shrinking a volume, or as a VHDX file (fixed or
  dynamically expanding). Minimum 50 GB. A VHDX on C: is the easy start; a separate physical
  SSD/partition is better if available.
- Or, for an existing *empty* volume (admin PowerShell; **erases D:**):
  ```powershell
  Format-Volume -DriveLetter D -DevDrive
  ```
  Undo: back up, then reformat as NTFS (`Format-Volume -DriveLetter D -FileSystem NTFS`) - also erases.

Existing volumes cannot be converted in place; copy the data off and back.

## Trust and performance mode

New Dev Drives are trusted at creation. If the audit says performance mode is disabled:

```powershell
# admin PowerShell
fsutil devdrv trust D:                               # undo: fsutil devdrv untrust D:
Set-MpPreference -PerformanceModeStatus Enabled      # undo: -PerformanceModeStatus Disabled
fsutil devdrv query D:                               # confirm
```

Gain: the main Dev Drive benefit. Risk: small - files are still scanned, just
asynchronously, so a malicious file could be opened before its scan finishes. Real-time
protection must be on for performance mode to work at all. Managed/work PCs may control this
by policy; then it's a question for IT.

Antivirus filters: `fsutil devdrv setFiltersAllowed ...` controls which file-system filters
(e.g. container or projection filters) may attach. Only touch it if a tool you use says it
needs a filter on the Dev Drive.

## What to put on it

Put things that are written a lot during builds:

| Move | How (examples; adapt the drive letter) | Notes |
|---|---|---|
| Source repos / worktrees | clone into `D:\src\...` | Biggest win: build output lives beside the code. |
| Cargo home | `setx CARGO_HOME D:\packages\cargo` then move `%USERPROFILE%\.cargo` | Re-open shells; `cargo` and `rustup` binaries live in `CARGO_HOME\bin`, update PATH. |
| Rustup toolchains | `setx RUSTUP_HOME D:\packages\rustup` then move `%USERPROFILE%\.rustup` | Or reinstall rustup with both set. |
| Pub cache (Dart/Flutter) | `setx PUB_CACHE D:\packages\pub` | Then `flutter pub get` refills it. |
| npm cache | `npm config set cache D:\packages\npm-cache --global` | |
| pnpm store | `pnpm config set store-dir D:\packages\pnpm-store` | |
| Gradle | `setx GRADLE_USER_HOME D:\packages\gradle` | Android builds. |
| NuGet / pip / Maven | `NUGET_PACKAGES`, `PIP_CACHE_DIR`, `MAVEN_OPTS=-Dmaven.repo.local=...` | |
| Flutter SDK | move the SDK folder, update PATH | It writes its own cache under `bin\cache`. |
| Build/test temp files | see `temp-files.md` | Scoped to builds, not machine-wide. |

`setx` writes the *user* environment (no admin needed) and only affects new processes.
Undo: `setx NAME ""` then delete it in *Edit environment variables for your account*, and
move the folder back.

**Gain:** toolchain and cache folders are mostly *read* during builds; moving them helps less
than moving the repos, but it does help first builds and dependency downloads, and frees C:.
**Risk:** low; the main pitfall is a half-done move (old PATH entries, tools that cached the
old path). Do one at a time and run a build after each.

## What not to put on it

- The OS, program installs, or anything that must work before the drive mounts.
- Downloads and installers (see the whole-drive-exclusion discussion in `defender.md`).
- Databases you care about without backups - same as anywhere.
