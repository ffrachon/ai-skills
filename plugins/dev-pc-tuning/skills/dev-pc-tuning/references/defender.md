# Microsoft Defender and heavy builds

## Why it costs time

Real-time protection scans files when they are created, opened and executed. A Rust or C++
build writes thousands of object files and then *runs new executables* (build scripts, test
binaries) that Defender has never seen, so each first launch is scanned. Node installs unpack
tens of thousands of small files. That's where Windows loses time against Linux/macOS on the
same hardware - together with slower process creation and linking.

## Step 1: measure (admin PowerShell)

Don't exclude anything on a hunch. Record what Defender actually scans during a typical
build or test run:

```powershell
# admin PowerShell. Start recording, run your build/test in another window, then press Enter here.
New-MpPerformanceRecording -RecordTo "$env:USERPROFILE\Desktop\defender.etl"
# (newer Defender platforms also accept -Seconds 300 for a timed, non-interactive recording)

Get-MpPerformanceReport -Path "$env:USERPROFILE\Desktop\defender.etl" `
    -TopFiles 20 -TopExtensions 10 -TopProcesses 10 -TopScans 20 -TopPaths 20
```

Read it for: which paths and processes dominate total scan time (typically `target\`,
`node_modules\`, `.dart_tool\`, the toolchain folders, `%TEMP%`, and processes like
`cargo.exe`, `rustc.exe`, `link.exe`, `node.exe`, `dart.exe`), and how big that total is
compared with the build's wall time. If scans add up to a few seconds on a 10-minute build,
exclusions aren't worth their risk - stop here.

Also time the same build/test twice (cold vs warm) and keep the numbers as a baseline.

The `.etl` file can be large; delete it when done.

## Step 2: the cheapest fix - Dev Drive with performance mode

If the code isn't on a trusted Dev Drive yet, do that first (`dev-drive.md`). Performance
mode keeps scanning on but makes it asynchronous - most of the gain with little of the risk.
Re-measure before going further.

## Step 3: if the recording still justifies it - choose an exclusion strategy

### Option A: narrow exclusions (recommended default)

Exclude only what the recording shows is hot *and* is produced by your own tools:

```powershell
# admin PowerShell - examples, use your own paths from the recording
Add-MpPreference -ExclusionPath "D:\src\myproject\target\:{ScanTrigger:OnAccess}"
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.rustup\:{ScanTrigger:OnAccess}"   # toolchains (if still on C:)
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.cargo\:{ScanTrigger:OnAccess}"
# undo: remove the exact same string
Remove-MpPreference -ExclusionPath "D:\src\myproject\target\:{ScanTrigger:OnAccess}"
# review (admin): (Get-MpPreference).ExclusionPath
```

The `\:{ScanTrigger:OnAccess}` suffix makes it a **contextual exclusion** (Defender platform
4.18.2205 or later; check `(Get-MpComputerStatus).AMProductVersion`): the folder is skipped
by real-time (on-access) scanning only, so scheduled, quick, full and custom scans still look
at it. A plain path exclusion (without the suffix) applies to *every* scan type, including
the custom scans you might run to compensate. The keywords are case-sensitive and the
backslash before the colon is required. The Windows Security app can't show or edit
contextual exclusions; use PowerShell.

- **Gain:** removes most scan time on build output; toolchain exclusions help process start.
- **Risk:** files in those folders are not scanned when written, opened or run. Build output
  is produced by your compiler from code you chose to build, so the extra exposure is mainly
  a malicious dependency's build script writing there. Toolchain folders hold executables
  that run constantly; a tampered toolchain would only be caught by the next scheduled scan.
- Many folders to maintain (every repo, every worktree); a wildcard such as
  `D:\src\*\target` (one `*` = exactly one folder level) is possible but broadens the scope.
- Type paths so PowerShell expands them (`$env:USERPROFILE\...`). A literal `%USERPROFILE%`
  inside an exclusion is expanded by Defender's own service account and points at the wrong
  folder.

**Process exclusions** (`-ExclusionProcess cargo.exe`) look attractive but exclude *every
file that process opens, anywhere* - including anything a dependency's build script makes it
read. Prefer path exclusions; if used, use full paths to the executable, never bare names.

### Option B: whole Dev Drive exclusion (informed choice)

```powershell
# real-time only; scheduled and custom scans still cover the drive
Add-MpPreference -ExclusionPath "D:\:{ScanTrigger:OnAccess}"
# undo: Remove-MpPreference -ExclusionPath "D:\:{ScanTrigger:OnAccess}"
# confirm it was accepted: (Get-MpPreference).ExclusionPath
```

- **Gain:** the maximum - nothing on the drive is scanned. With a trusted Dev Drive already
  in performance mode the extra gain over Option A is often small; measure it.
- **Risk:** anything that lands on the drive is never scanned: cloned repos, downloaded
  dependencies, binaries that tests produce, and *anything else saved there*. Other layers
  (SmartScreen on downloads, cloud protection for files elsewhere, network protection) still
  work, but the drive is a blind spot.
- **Compensating habits** (make them explicit with the user):
  1. Keep **Downloads, installers, and email attachments on C:** - never save them to the
     excluded drive, and never run installers from it.
  2. Don't point machine-wide `TEMP`/`TMP` at the excluded drive (that would be an indirect
     Temp exclusion - see `temp-files.md`).
  3. **Scan the drive now and then.** With the on-access-only form above, a custom scan
     still covers it - e.g. monthly, in admin PowerShell, when no build is running:
     `Start-MpScan -ScanType CustomScan -ScanPath "D:\"` (clean big build folders first to
     make it shorter). With a *plain* `D:\` exclusion, scans skip the drive entirely, so the
     exclusion would have to be removed for the scan and added back afterwards.
  4. Clone from sources you trust, review new dependencies, keep lockfiles.
  5. Reconsider on a shared or work machine - policy may forbid it, and IT may already
     manage exclusions centrally.

### Options compared

| | Narrow (A) | Whole drive (B) |
|---|---|---|
| Speed | most of the gain | maximum |
| Exposure | your build output (+ toolchains if excluded) | everything on the drive |
| Upkeep | per repo/worktree | none |
| Needs habits | light | the list above |

## Hard lines

- **Never exclude `%TEMP%` / `%TMP%`.** Installers, browsers, mail and archive tools unpack
  there; it is one of the most common places malware first lands. Move the *build's* temp
  files instead (`temp-files.md`).
- **Never exclude the whole user profile, `Downloads`, or `C:\`.**
- **Never turn off real-time protection** (or uninstall Defender without a replacement) to
  speed up builds. Performance mode plus narrow exclusions get almost all of the gain.
- **Extension exclusions** (`.rlib`, `.pdb`, `.o`) apply machine-wide, in every folder;
  avoid them.

- **Don't lower cloud protection** (`MAPSReporting`, `CloudBlockLevel`,
  `DisableBlockAtFirstSeen`, `CloudExtendedTimeout`) for speed. Block at first sight and the
  cloud timeout mainly hold files that arrive from the internet; files your own compiler
  writes rarely wait on them. If the recording ever shows long waits on freshly built
  binaries, narrow exclusions on the output folder are the safer lever.

If tamper protection or an organisation policy blocks a change, that is working as
intended - the user should ask whoever manages the device.

## Another antivirus product

If the audit lists a non-Microsoft antivirus, Defender runs in passive mode or is off, and
none of the Defender steps above apply - including Dev Drive performance mode. Use that
product's own performance tooling and exclusion settings, with the same rules: measure
first, exclude build output narrowly, never Temp or Downloads. If its vendor offers a
developer or Dev Drive mode, prefer that over broad exclusions.
