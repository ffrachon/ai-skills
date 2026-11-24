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
   **A self-hosted CI runner on the same machine counts as a full check.** A release or
   CI job running its test suite on this PC competes for the same CPU, disk and local database,
   but sessions don't see it, so they start their own full runs alongside it. In one case a
   release job needed two reruns: one database statement timeout and one flaky time-sensitive
   test, both from load. Have the runner's test job take the same lock, or check for a busy
   runner (`gh run list --status in_progress`, or the runner's `_work` folder activity) before
   starting a full run.
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
8. **Consider a Linux lane in WSL 2** for a big suite (measure first): in one measurement
   the tests ran about 25% faster in a dedicated distro on its own ext4 disk, with less
   than half the build-output disk. It shares the machine, so the same lock must cover
   both sides (`wsl-containers.md`).

**Time-sensitive tests failing at random only in WSL** (rate limits "too soon", wrong
"newest first" order, jobs not yet due): check the WSL clock before blaming the tests. A
time daemon in any distro makes the shared kernel clock step back about a second every
minute (`wsl-containers.md`, "One time source"). **Tests that wait for "connection
refused" are slow only in WSL:** mirrored networking drops connections to closed
localhost ports instead (`wsl-containers.md`, "Mirrored networking").

For AI coding sessions specifically: tell each session the rule ("targeted tests while
working, one full check at the end, wait if another full check is running") - for example
in a shared instructions file such as `CLAUDE.md`.

## How much can run at once

A rule of thumb from a 20-thread, 64 GB desktop shared by up to five AI coding sessions,
each in its own git worktree:

| What | Safe at once | What keeps them apart |
|---|---|---|
| Targeted tests (one file, one crate) | one per session (5 there) | separate worktrees; heavy ones also take a test slot |
| Database-heavy test runs | about 3 | a counting lock ("test slots": N lock files, a run takes any free one) so the shared PostgreSQL never runs out of connections |
| Full checks | **one per machine** | the full-check lock |
| Parts inside one full check | 2-3 tracks side by side | ordering within each track (below) |

A second full check on the same machine is only safe once nothing is shared by name: a
separate database cluster per check, OS-chosen ports, container names unique to each run,
separate browser profiles. Until then it collides (one case: two overlapping checks both
had to rerun parts). Measure what it would save before building it: with the habits below,
the queue for the single slot is usually short.

**Make the full-check lock first come, first served.** A plain "retry every 30 s" lock lets
a late arrival grab the lock while an earlier waiter sleeps; one session waited 95 minutes
that way. Have each waiter write a ticket file (arrival time, process id) and let only the
oldest live ticket try the lock; drop tickets whose process is gone.

## Running the parts of one full check side by side

A full check is often several independent parts (backend tests, a security scan, translations,
two front-end builds with browser checks, a static site with an accessibility pass). Running
them in 2-3 tracks at once cut one project's check from about 60 to about 25 minutes. Rules
that came out of the failures:

- Keep the CPU- and database-heavy part (the backend's compile and tests) in a track of its
  own, or on another machine (below).
- Put parts that write the same files in the same track, in order. In one case, one front
  end's checks put a stub in a shared vendor folder that the other front end's checks then
  took for the real thing.
- Start browser-heavy parts (hundreds of pages in headless Chromium) after the big compile
  has finished: a browser fleet next to a full `cargo` compile ran the machine out of
  sockets.
- Log each part to its own file with start, end, status and seconds, plus one summary file,
  so a failure points at a part and a rerun can repeat only the failed parts.
- Let the script skip parts nothing changed (`--since <base ref>`: map folders to parts), but
  always run the cheap cross-cutting ones (security scan, translations).

## A second machine as the second full-check slot

A second machine (a laptop, a Mac) with its own lock doubles the full checks you can run
with no contention at all. In one setup an M1 laptop ran the backend part as fast as the
i9 desktop, while the desktop ran the rest. What made it reliable:

- **Send the exact commit,** not a working folder: bundle `HEAD` (`git bundle`), check it out
  on the other machine, and record the commit and tree with the result.
- **Keep it warm:** a scheduled job on the main PC asks the second machine to build the main
  branch whenever it moves, only when the machine is idle, and gives way to a waiting check.
  Cold starts (a full rebuild, about 20-40 extra minutes) came from a disk-cleanup threshold
  set too high, which deleted the build cache every time; size it from the real build size.
- **Install its dependencies from a file, every run:** a pinned requirements file synced into
  the lane's own virtual environment before each run, plus a check that the toolchain
  version matches the main PC's. A package added by hand on one machine was missing on the
  other and cost 40 minutes.
- **A 10-second dry run** (`--preflight`: reach the machine, lock free, toolchain and packages
  match) catches all of that before a 25-minute run.
- **Mind tool differences between operating systems.** macOS's BSD `tar` has no `--mtime`
  (GNU tar has), so a reproducible-archive step that worked on Linux and Windows failed
  there; use GNU tar (`gtar` from Homebrew) or a portable option.
- **Tell every session the slot exists, every time.** AI sessions kept defaulting to the one
  lock they knew about and queued behind each other while the second machine sat idle; it
  had to be written into every task brief, not left to a general note.

## Several branches checked separately, then merged

When several sessions each work on a branch and check it before merging into main, most of
the waiting comes from reruns after main moves, not from the checks themselves. What kept
the safety without the waste:

- **Keep a passing check when main moved elsewhere:** if the commits main gained touch none
  of the parts the branch's check covered, merge without rerunning. A change in a shared
  area still means a rerun.
- **Order branches that touch the same files:** decide up front which one merges first; the
  second merges it in before its single final check, instead of checking twice.
- **One final check on the merged result** if no branch's check ran on exactly what will be
  released.

## Tools a check needs: install them where every worktree finds them

A test step that quietly **skips** when its tool is missing is worse than one that fails. In
one case the browser tests of a whole branch were skipped, and the check still reported
"passed", because each fresh git worktree lacked the browser-testing tool: the project's
docs installed it inside one checkout (`npm install --no-save`).

- Install shared test tools once in a folder outside the worktrees and point `NODE_PATH` at
  its `node_modules` (or the equivalent for other languages), so every checkout resolves
  them.
- Treat "skipped: tool not found" in a local full check as an environment problem to fix,
  or make the check fail on it (a `--strict` flag), at least for the final check.
- For Playwright specifically, see `other-tools.md` ("Several Playwright versions on one
  machine"): installing a browser can delete the browsers of other projects.

**Port clashes show up as rare, random failures** ("address already in use", 1 page in 700
of an accessibility pass) only when other checks run alongside. Bind every test server to
port 0 and pass the chosen port to its clients, rather than fixing ports per project.
