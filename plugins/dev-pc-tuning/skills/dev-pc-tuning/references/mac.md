# Mac notes

Apple Silicon Macs are often as fast as, or faster than, a high-end Windows desktop for
compile-and-test loops: test execution itself can be about twice as fast, but time can be
lost to macOS checking every **newly built executable** the first time it runs (each test
binary, each build script). On one comparison, a cold run on an M1 laptop ended up roughly
level with an i9 desktop for exactly that reason.

## Read-only checks

```bash
sw_vers; sysctl -n machdep.cpu.brand_string; sysctl -n hw.ncpu hw.memsize
df -h /                                  # free space
du -sh ~/path/to/repos/*/target 2>/dev/null | sort -h | tail   # big build folders
spctl --status                           # Gatekeeper on/off (should stay on)
mdutil -s /                              # Spotlight indexing status of the volume
tmutil isexcluded ~/path/to/repo/target  # Time Machine exclusion of build output
rustc -vV | grep host                    # should say aarch64-apple-darwin on Apple Silicon
file "$(command -v cargo)" "$(command -v node)" "$(command -v flutter)"   # arm64, not x86_64
launchctl limit maxfiles; ulimit -n      # open-file limits
```

**Rosetta check:** on Apple Silicon, an x86_64 toolchain (an old Intel-era rustup or Homebrew
under `/usr/local`, or a terminal app set to "Open using Rosetta") runs everything under
translation and is much slower. If the host triple or `file` says x86_64, reinstall the
toolchain natively (rustup, Homebrew in `/opt/homebrew`) and untick "Open using Rosetta" in
the terminal's Get Info. No security cost.

To see whether first-run checks cost time: run the same freshly built test binary twice; if
the first launch is noticeably slower than the second, that's the per-binary check.

## Developer Tools exemption (a user decision)

macOS lets you mark a terminal app (and IDEs) as a developer tool:
**System Settings > Privacy & Security > Developer Tools**, then enable Terminal (or iTerm,
VS Code, ...). If the pane isn't shown, `spctl developer-mode enable-terminal` makes it
appear (it doesn't enable anything by itself).

- **What it does:** programs launched from that app skip some of the Gatekeeper/notarization
  checks that run when an unknown executable starts - which is exactly what new test
  binaries are.
- **Gain:** removes the first-run delay for each new binary; noticeable on large test suites
  with many binaries.
- **Risk:** *anything* you run from that terminal gets the same pass, including a script or
  binary downloaded from the internet. XProtect and other protections still exist, but one
  check is gone for that app.
- **Undo:** untick the app in the same pane.
- Present it as a choice; suggest it only for a terminal/IDE used for development, not for
  a browser or a general-purpose app. Never disable Gatekeeper globally
  (`spctl --master-disable`) for speed.

## Other Mac habits

- **Spotlight:** exclude repo folders (System Settings > Spotlight > Search Privacy) or name
  a folder with a `.noindex` suffix; useful when `mds_stores` is busy during builds.
- **Time Machine:** exclude `target`, `node_modules`, `build`
  (`tmutil addexclusion <path>`; undo `tmutil removeexclusion <path>`).
- **Open files limit** for big test suites: `ulimit -n` (raise per shell, e.g.
  `ulimit -n 10240`).
- **Docker/Podman:** the VM disk image lives under the user's Library folder and grows;
  prune and check the VM's CPU/RAM allocation (`wsl-containers.md`). Bind-mounted host
  folders are slower than named volumes for database data.
- **Linker:** Apple's current linker (Xcode 15+) is already fast; no change needed. Merging
  integration tests into one binary (`rust.md`) helps here too, since each new binary pays
  the first-run check.
- **PostgreSQL / git / Gradle settings** in `postgres.md` and `other-tools.md` apply on a
  Mac as well.
- The same habits as on Windows apply: targeted tests while iterating, one full run at a
  time (`test-runs.md`), clean old build output (`cleanup.md`).
