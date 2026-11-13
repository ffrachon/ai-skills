# Big test suites: one full run at a time

With several AI coding sessions or terminals on one machine, the most common slowdown is not
a setting - it is two or more full test runs overlapping. They compete for:

- **CPU and RAM:** each run already uses all cores (cargo and most runners parallelise by
  default). Two runs don't finish in the same time; each goes roughly **2x slower**, and
  memory pressure can make it worse.
- **The local database:** shared PostgreSQL connection limits, locks on shared schemas,
  `CREATE DATABASE` contention, fixtures one run drops while another uses them.
- **Ports:** two servers trying to bind the same port; one fails or, worse, talks to the
  other run's server.
- **Disk and Defender:** two sets of new test binaries to scan, two builds writing at once.

The visible symptom is **timeouts and flaky failures** that disappear when a run is alone,
which then trigger reruns that make it worse.

## Habits that fix it

1. **While iterating, run targeted tests only:**
   - Rust: `cargo test --test <file>` (one integration test file), `cargo test -p <crate>`,
     `cargo test <name_filter>`; `cargo nextest run -E 'test(name)'` if nextest is used.
   - Flutter/Dart: `flutter test test/path/to_test.dart`, `--plain-name "<test name>"`.
   - Node: `npx vitest run path`, `npx jest path -t "<name>"`.
   These take seconds to a minute and can run side by side.
2. **One full check at a time.** Run the whole suite once, at the end. If several sessions
   share the machine, agree on a lock - e.g. the full-check script takes a lock file and
   waits if another run holds it:
   ```powershell
   $lock = 'D:\tmp\full-check.lock'
   while ($true) {
       try { $fs = [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None'); break }
       catch { Write-Host 'Another full check is running; waiting...'; Start-Sleep 30 }
   }
   try { <# run the full suite here #> } finally { $fs.Close() }
   ```
   (An exclusive file handle is released automatically if the process dies.)
3. **Isolate what must run in parallel:** per-run database names (or schemas), ports chosen
   by the OS (bind to port 0) or from a per-run range, per-run temp folders
   (`temp-files.md`).
4. **Cap parallelism when sharing the machine:** `cargo test -- --test-threads=4`,
   `CARGO_BUILD_JOBS=8`, `flutter test --concurrency=4`. Fewer threads per run beats two
   runs fighting.
5. **Fewer test executables / compilation units** (measure first). Rust: merge
   `tests\*.rs` into one test binary (`rust.md`). Flutter/Dart: every test file is compiled
   and started separately; a single entry file that imports the others
   (`test/all_test.dart` calling each file's `main()` inside a `group`) can cut a large
   suite's time a lot. Cost: files share one isolate, so global state and `setUpAll`
   ordering must be safe to share; keep the per-file layout for targeted runs.
6. **Database-heavy suites:** template databases and non-durable settings on a throwaway
   test cluster (`postgres.md`).
7. **Don't wait idle on a 25-minute run** in an AI session; hand the wait to a background
   job and check back, and don't start a second full run "to save time".

For AI coding sessions specifically: tell each session the rule ("targeted tests while
working, one full check at the end, wait if another full check is running") - for example
in a shared instructions file such as `CLAUDE.md`.
