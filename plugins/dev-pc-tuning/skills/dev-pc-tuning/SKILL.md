---
name: dev-pc-tuning
description: Audit and tune a Windows PC (and optionally a Mac) for heavy software development - large Rust, Flutter, Node or C++ builds, long test suites, local PostgreSQL or containers, several AI coding sessions or IDEs at once. Runs a read-only audit, helps measure where time goes (Defender scanning, slow linking, temp files on C:, indexing, disk space), then recommends changes with the gain, the risk and how to undo each one, as commands the user runs themselves. Use this whenever someone says builds or tests are slow on Windows, asks about Dev Drive, ReFS, Defender exclusions or performance mode, antivirus slowing cargo/flutter/npm, where to put caches or TEMP, cleaning up huge target or node_modules folders, test runs timing out when several run at once, or why their Mac is faster or slower than their PC for builds - even if they don't say "tuning".
---

# Dev PC tuning

Help someone make a development machine faster for heavy build and test work without
quietly weakening its security. The pattern is always: **audit (read-only) -> measure ->
recommend -> the user applies**.

## Ground rules

These exist because the changes involved (antivirus exclusions, file-system settings, power
plans) trade security or stability for speed, and that trade is the user's to make knowingly.

- **Never change system configuration yourself.** Don't add Defender exclusions, turn on
  performance mode, edit the registry, change power plans, format or create volumes, change
  indexing, or delete build folders on your own - even if you have an admin shell and the user
  says "just do it". Give the commands; the user runs them in their own **admin PowerShell**
  (Mac: their own Terminal / System Settings). Reading state is fine; writing it is theirs.
- **Every recommendation carries four things:** what it does, the expected gain (and how to
  check it), the risk, and the exact undo command.
- **Measure before recommending a security trade-off.** Defender exclusions in particular are
  justified by a performance recording, not by folklore.
- **Hard lines to state plainly if asked:** don't exclude `%TEMP%` / the whole user profile /
  `Downloads`, and don't turn off real-time protection. Explain why and offer the safer
  alternative (redirect temp files to the dev drive; exclude specific folders or processes).
- Use generic paths (`$env:USERPROFILE`, `$env:LOCALAPPDATA`, `D:\` as an example dev drive)
  and adapt to what the audit actually found.

## Workflow

### 1. Audit (read-only)

Run the bundled script from a normal PowerShell (admin optional - without it, Defender and
Dev Drive details report "needs admin"):

```powershell
powershell -ExecutionPolicy Bypass -File <skill-dir>\scripts\audit.ps1
# options: -DevRoot D:\src    (where the projects live; default: auto-detect)
#          -Json              (machine-readable output, for you to parse)
#          -SkipSizes         (skip the build-folder size scan, which can take minutes)
```

`-ExecutionPolicy Bypass` applies to that one process only; it does not change the machine's
policy. If the user prefers, they can read the script first - it only reads.

The script reports: Windows/CPU/RAM, volumes and file systems, Dev Drive status and trust,
Defender state (real-time, performance mode, exclusions), where toolchains and caches live
(rustup, cargo, Flutter, Pub, npm, pnpm, Gradle, TEMP), Windows Search scope, power plan,
page file, free space, size of build-output folders (`target`, `build`, `.dart_tool`,
`node_modules`), WSL/Docker/Podman disk images and `.wslconfig` caps, Smart App Control and
memory-integrity state, global git and Gradle settings, PostgreSQL services, and a list of
findings.

On a Mac, there is no script; ask for or run the read-only commands in
`references/mac.md`.

### 2. Summarise and ask what hurts

Give a short summary of the findings (what's already good, what stands out), then ask what
they actually feel: slow first build, slow incremental build, slow test start-up, tests timing
out, disk filling up, machine unusable during runs. The answer decides which levers matter -
don't recommend all of them.

### 3. Measure

Pick the measurement that matches the complaint (details in the references):

- **Defender overhead:** a performance recording during a typical build/test
  (`references/defender.md`). Also time the same build once with the target folder warm vs
  cold.
- **Linking:** `cargo build --timings` or the time between "Compiling" finishing and the test
  binary starting (`references/rust.md`).
- **Contention:** time one full test run alone vs two at once (`references/test-runs.md`).
- Note the baseline numbers so every change can be judged against them.

### 4. Recommend, ordered by gain-for-risk

Typical order (skip what the audit shows is already done):

1. **Free disk / clean build output** - no security cost (`references/cleanup.md`).
2. **One heavy full test run at a time; targeted tests while iterating** - a habit, free
   (`references/test-runs.md`).
3. **Dev Drive (ReFS) for code, caches and build output** (`references/dev-drive.md`).
4. **Move build/test temp files onto the dev drive** instead of excluding Temp
   (`references/temp-files.md`).
5. **Defender: performance mode, then narrow exclusions if the recording justifies them**;
   whole-drive exclusion only as an informed choice with compensating habits
   (`references/defender.md`).
6. **Fewer test binaries, faster test databases** - merge Rust integration tests into one
   binary, aggregate Flutter test files, template databases and non-durable settings on a
   throwaway test cluster (`references/rust.md`, `references/test-runs.md`,
   `references/postgres.md`). Measure first; often the biggest test-time wins.
7. **Optional, measure each:** faster linker, sccache, debug-info settings, separate
   rust-analyzer target (`references/rust.md`); git fsmonitor, Gradle cache
   (`references/other-tools.md`); WSL file placement and memory caps
   (`references/wsl-containers.md`).
8. **Power** - "Best performance" power mode on a desktop (laptop: only while plugged in);
   check whether background builds get throttled (`references/windows-extras.md`).
9. **Indexing** - usually nothing to gain; explain why (`references/indexing.md`).

Smart App Control, memory integrity (HVCI) and other security features: report their state
and the trade-off, and leave the decision to the user (`references/windows-extras.md`).

For each, use this shape:

```
### <change>
What: <one or two sentences>
Expected gain: <honest range, and how to check it against the baseline>
Risk: <security / stability / disk cost>
Apply (admin PowerShell):   <commands>
Undo:                       <commands>
```

### 5. Re-measure

After the user applies something, rerun the same measurement and the audit, and report the
before/after. If a change gained nothing, say so and suggest undoing it - especially if it
had a security cost.

## Reference files

Read only what the conversation needs.

| File | When |
|---|---|
| `references/dev-drive.md` | Creating/using a Dev Drive, ReFS, trust and filter settings, what to move onto it |
| `references/defender.md` | Measuring Defender, performance mode, narrow vs whole-drive exclusions, compensating habits |
| `references/temp-files.md` | Moving TEMP/TMP for builds and tests to the dev drive |
| `references/indexing.md` | Windows Search / content indexing questions |
| `references/cleanup.md` | Huge `target` / `build` / `node_modules` folders, caches, WSL/container disks |
| `references/test-runs.md` | Overlapping test runs, databases, ports, CPU contention, targeted tests |
| `references/rust.md` | Linker, sccache, debug info, merging test binaries, build-lock contention, nightly options |
| `references/postgres.md` | Test-only PostgreSQL: template databases, non-durable settings, connections |
| `references/wsl-containers.md` | WSL file placement, `.wslconfig` memory/CPU caps, Docker/Podman limits |
| `references/other-tools.md` | Git fsmonitor/untracked cache, Gradle cache and daemons, Node |
| `references/windows-extras.md` | Power throttling, RAM/page file, Smart App Control, HVCI, rejected tweaks |
| `references/mac.md` | Mac: scanning of new binaries, Developer Tools exemption, Rosetta, read-only checks |
