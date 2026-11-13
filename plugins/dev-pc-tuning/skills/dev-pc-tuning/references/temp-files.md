# Build and test temp files: redirect, don't exclude

Test suites (database fixtures, generated files, extracted archives, `tempfile` crates,
Dart's `Directory.systemTemp`) write and delete many files in `%TEMP%`, which sits on C:
(NTFS, fully scanned). Moving *those* writes to the Dev Drive gets ReFS plus performance-mode
scanning, without the danger of excluding Temp for every program on the machine.

Rust's `std::env::temp_dir()` and Dart/Flutter both follow the `TMP` / `TEMP` environment
variables on Windows (`TMP` is checked first), so setting them for the build/test process is
enough. Verify once with a test that prints `std::env::temp_dir()` (Rust) or
`Directory.systemTemp.path` (Dart).

## Option 1: per shell / per script (simplest)

```powershell
New-Item -ItemType Directory -Force D:\tmp\build | Out-Null
$env:TMP = 'D:\tmp\build'; $env:TEMP = 'D:\tmp\build'
cargo test        # or: flutter test, npm test, your test script
```

Affects only that window. Undo: close the window.

## Option 2: per Rust project via cargo config

```toml
# <repo>\.cargo\config.toml  (or %USERPROFILE%\.cargo\config.toml for all projects)
[env]
TMP  = { value = "D:\\tmp\\build", force = true }
TEMP = { value = "D:\\tmp\\build", force = true }
```

Cargo passes `[env]` to build scripts, `rustc`, and the binaries run by `cargo run` /
`cargo test`. Undo: delete the lines. Integration tests can also use
`env!("CARGO_TARGET_TMPDIR")`, which lives inside `target\` (already on the Dev Drive if the
repo is).

## Option 3: in the test runner script

If the project has a test script, set `TMP`/`TEMP` (and e.g. a per-run subfolder) at its
top. This also helps keep parallel runs from colliding (`test-runs.md`).

## Why not change the user/machine TEMP?

Possible (`setx TEMP D:\tmp` / `setx TMP D:\tmp`), but then *every* program's temp files go
there: installers, browser downloads in progress, archive extraction. If the Dev Drive is
excluded from Defender (whole-drive option), that silently becomes a Temp exclusion. If it is
not excluded, it is mostly harmless, but some installers and tools misbehave when Temp is on a
non-system or ReFS volume. Recommend scoping it to builds and tests.

## Housekeeping

Tests that crash leave files behind. Clean the folder now and then (when nothing is
running): `Remove-Item D:\tmp\build\* -Recurse -Force` - the user runs it; check the path
first.
