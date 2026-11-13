# Other Windows levers: power throttling, memory, and security features

## Builds slow down when their window is in the background (measure first)

Windows "power throttling" (EcoQoS) runs work it considers background at lower clocks and,
on CPUs with performance and efficiency cores (Intel 12th gen and later, many laptops),
prefers the efficiency cores. A build or test run in a minimized terminal, or launched by a
background agent, can be classed that way.

- **Measure:** time the same build twice, once with its terminal in front and once
  minimized. On a desktop CPU without efficiency cores, on the "Best performance" power
  mode, the difference is usually nil - stop there.
- **Apply (if it differs):** first set *Settings > System > Power & battery > Power mode* to
  **Best performance** (plugged in). If background runs are still slower, opt specific
  tools out of throttling (admin PowerShell; use the real paths on that machine):
  ```powershell
  powercfg /powerthrottling disable /path "$env:USERPROFILE\.cargo\bin\cargo.exe"
  powercfg /powerthrottling list                     # review
  # undo:
  powercfg /powerthrottling reset /path "$env:USERPROFILE\.cargo\bin\cargo.exe"
  ```
  Child processes (rustc, the linker, test binaries) are separate executables; list the
  ones that matter or apply it to the terminal/agent host instead, and re-measure.
- **Risk:** none for security; more power draw and heat, which matters on battery.

Core parking needs no tuning on current Windows; the power mode above covers it.

## RAM and the page file

Parallel builds are memory-hungry: each `rustc` or linker process can take 1-4 GB on big
crates, and two full runs plus a database, containers and IDEs add up quickly.

- **Check during a full run:** Task Manager > Performance > Memory ("Committed" vs its
  limit, and whether "In use" sits near the total). The audit shows RAM and page-file size.
- **If memory runs out:** run one heavy job at a time (`test-runs.md`), cap build jobs
  (`CARGO_BUILD_JOBS=8`, or `[build] jobs = 8` in cargo config), cap WSL
  (`wsl-containers.md`). More RAM helps only if the machine actually pages.
- **Keep the page file system-managed and on the fastest SSD.** Disabling it doesn't speed
  anything up; it turns memory peaks into out-of-memory build failures.

## Security features: user decisions, not tuning steps

These cost some performance and protect against real attacks. Report their state (the audit
reads it), explain the trade-off, and leave the choice to the user. Never suggest turning
them off as a routine step.

### Smart App Control

When **On**, Windows checks every executable it hasn't seen before against cloud reputation
and blocks unsigned code with no reputation. Freshly built test binaries are exactly that,
so developers report blocked or slow-starting builds. When in **Evaluation**, it watches and
may switch itself on or off. When **Off**, nothing changes.

- If it is On and builds work at normal speed, leave it.
- If it blocks or slows builds, the user may turn it off in *Windows Security > App & browser
  control > Smart App Control*. Recent Windows 11 builds (from the April 2026 updates) let
  it be turned back on there; on older builds turning it off was one-way without a
  reinstall - say so before they decide.

### Memory integrity (HVCI) and virtualization-based security

Kernel isolation features. On current CPUs the measured cost for compile workloads is
typically a few percent or less; on older CPUs it can be more.

- Recommend leaving them on. If the user still wants to test, measure a full build with it
  on and off (*Windows Security > Device security > Core isolation*; needs a restart) and
  turn it back on unless the difference is large. Many work PCs enforce it by policy.
- WSL 2, Docker and Hyper-V need the hypervisor anyway, so turning VBS off doesn't remove
  virtualization overhead for them.

### SmartScreen

Checks files that carry the "downloaded from the internet" mark. Files your compiler writes
don't carry it, so SmartScreen doesn't slow builds. Leave it on.

## Checked and not recommended

- **Lowering Defender cloud protection / block at first sight:** aimed at downloaded files;
  not where build time goes (see `defender.md`).
- **MSVC `/DEBUG:FASTLINK`, `-Zshare-generics`, changing `CARGO_INCREMENTAL`:** see
  `rust.md`.
- **Core parking tweaks, `disablelastaccess`, 8.3-name tweaks on NTFS:** negligible on
  current Windows, and a Dev Drive (ReFS) doesn't create 8.3 names anyway.
- **Third-party RAM disks for builds or databases:** extra drivers and data-loss risk for a
  gain a Dev Drive plus the PostgreSQL settings in `postgres.md` mostly already give.
