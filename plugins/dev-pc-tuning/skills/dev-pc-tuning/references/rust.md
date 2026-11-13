# Optional Rust build speed-ups

All optional. Each one helps some projects a lot and others not at all, so measure before
and after (`cargo build --timings` writes an HTML report to `target\cargo-timings\`; for
tests, time `cargo test --no-run` and the run separately). Keep a change only if it helps.
None of these touch security settings; they are project or user config the user edits.

## Faster linker

Linking big test binaries with MSVC `link.exe` can take a large share of an incremental
build on Windows. `rust-lld` ships with every rustup toolchain:

```toml
# <repo>\.cargo\config.toml  (or %USERPROFILE%\.cargo\config.toml)
[target.x86_64-pc-windows-msvc]
linker = "rust-lld.exe"
```

- Gain: often a large cut in link time for big binaries; little for small crates.
- Risk: occasional incompatibilities (some C/C++ dependencies, debug-info quirks with
  debuggers). It still needs the MSVC build tools / Windows SDK libraries installed, like
  `link.exe`. If anything breaks, remove the lines. Undo: delete the section.
- Don't bother with MSVC's `/DEBUG:FASTLINK`: Microsoft no longer recommends it, and the
  debug-info settings below cut PDB cost more simply.
- Linux: recent stable Rust already uses `lld` by default on `x86_64-unknown-linux-gnu`;
  `mold` is another option there. macOS: Apple's newer linker is already fast.

## sccache (compilation cache)

```powershell
cargo install sccache --locked
setx RUSTC_WRAPPER sccache            # undo: setx RUSTC_WRAPPER "" (and remove the variable)
sccache --show-stats
```

- Helps: clean builds, `cargo clean` followed by rebuilds, several worktrees building the
  same dependencies, CI.
- Doesn't help: incremental builds of your own crates (incremental compilation is not
  cached). Adds a small overhead per rustc call and uses disk (put `SCCACHE_DIR` on the Dev
  Drive).

## Less debug info in dev builds

Debug info is a big part of compile, link and disk cost:

```toml
# Cargo.toml
[profile.dev]
debug = "line-tables-only"     # backtraces with file:line, much smaller; or debug = 0

[profile.dev.package."*"]
debug = false                  # no debug info for dependencies
```

- Gain: faster links, much smaller `target`.
- Cost: weaker debugger experience (variables not inspectable). Undo: remove the lines.

## Fewer integration-test binaries (measure first; often the biggest test-time win)

Every file in `tests\*.rs` is a separate crate and a separate executable: each one is linked
(the slow step on Windows), scanned by Defender on first run, and started as a new process.
A workspace with 40 integration-test files links 40 binaries after every change to the
library. Moving them into one binary changes that to one link:

```
tests/
  it/
    main.rs        // mod api; mod billing; mod auth;  ...
    api.rs
    billing.rs
```

(and delete the old top-level `tests\*.rs` files, or set `autotests = false` and declare
one `[[test]] name = "it" path = "tests/it/main.rs"` in `Cargo.toml`.)

- Gain: link time and first-run scan time drop roughly in proportion to the number of
  binaries merged; measure `cargo test --no-run` before and after.
- Cost: a change in one test file recompiles the whole merged test crate; tests now share
  one process, so global state (env vars, statics, a shared DB pool) must be safe to share.
  `cargo test --test it <filter>` still runs a subset. Undo: split the files back.
- Same idea for Flutter: see `test-runs.md`.

## Don't fight over the build lock

Cargo takes a lock on the `target` folder. An IDE's rust-analyzer running `cargo check`, an
AI session running `cargo test` and a terminal build in the **same checkout** queue behind
each other ("Blocking waiting for file lock") and can invalidate each other's work when
their flags differ.

- Give rust-analyzer its own target folder: VS Code setting
  `"rust-analyzer.cargo.targetDir": true` (uses `target\rust-analyzer`). Costs disk; undo
  by removing the setting.
- Give each parallel session its own git worktree rather than sharing one checkout.
- While iterating on compile errors, `cargo check` (no codegen, no linking) is several times
  faster than `cargo build` / `cargo test`.

## Other knobs (measure)

- `[profile.dev.package."*"] opt-level = 1..3` - optimised dependencies make *tests run*
  faster at the cost of a slower first build.
- `[profile.test]` / `[profile.dev] incremental = true` (default) - leave on locally.
- `split-debuginfo` - platform defaults are usually right.
- `cargo nextest` - runs each test in its own process, often faster for large suites and
  better at isolating hangs; on Windows, process creation and scanning of each test binary
  cost more, so measure.
- Workspace layout: many small crates parallelise better than one huge crate.
- Nightly-only, experimental, measure: the Cranelift codegen backend
  (`rustup component add rustc-codegen-cranelift-preview --toolchain nightly`, then
  `codegen-backend = "cranelift"` in a profile with `cargo-features = ["codegen-backend"]`)
  can cut debug-build codegen time; the parallel front end (`RUSTFLAGS="-Zthreads=8"`) helps
  large crates. Neither is worth moving a team to nightly for; try them on a branch.
- Not worth it: `-Zshare-generics` (already on for debug builds), changing
  `CARGO_INCREMENTAL` (already on for dev/test; it must stay off only under sccache, which
  handles that itself).
