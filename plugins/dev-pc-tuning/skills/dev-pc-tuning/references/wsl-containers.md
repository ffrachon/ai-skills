# WSL 2, Docker and Podman: speed, resource limits and a Linux test lane

(Disk space for WSL/container images: `cleanup.md`.)

## Keep Linux-side code inside the Linux filesystem

Files under `/mnt/c/...` or `/mnt/d/...` are reached from WSL through a network-style file
protocol. Builds, `git status` and `npm install` there are typically **several times
slower** than on the distro's own ext4 disk.

- **Do:** clone repos you build inside WSL into the Linux home (`~/src/...`). Windows tools
  can still open them at `\\wsl$\<distro>\home\<user>\src` (or `\\wsl.localhost\...`).
- **Don't:** build Windows-side projects from WSL through `/mnt`, or Linux-side projects
  from Windows through `\\wsl$` - each side is fast on its own filesystem.
- **Measure:** time `git status` or a build in both places.
- Risk: none; undo by moving the repo back. The ext4 disk is a VHDX file, so put the distro
  itself on the Dev Drive if C: is short of space (`wsl --manage <distro> --move`, see
  `cleanup.md`).

## Cap memory and CPU (`.wslconfig`)

WSL 2 (and Docker Desktop and Podman machines, which run in it) can use up to half of the
RAM by default (older versions: more) and all CPU cores. During a heavy Windows-side build
that competes with the build; with several containers running it can push Windows into
paging.

`%USERPROFILE%\.wslconfig` (create it if missing; it is the user's file):

```ini
[wsl2]
# pick for the workload; leave Windows enough for builds + IDEs
memory=16GB
# optional; leave unset unless WSL work starves Windows builds
processors=8
```

(Keep comments on their own lines; don't put them after a value.)

Then `wsl --shutdown` and start WSL again. Undo: delete the lines (or the file) and
`wsl --shutdown`.

`.wslconfig` applies to **every** distro (and to Docker/Podman machines on WSL), and
`wsl --shutdown` stops **all** of them at once. Before running it, check
`wsl --list --running`: a CI runner, database or long test run inside WSL is cut off
mid-job. Pause the runner (or wait for its job to finish) first.

- **Gain:** a responsive Windows side and fewer paging stalls when Linux-side work and
  Windows builds overlap. Measure with Task Manager's memory graph during a typical day.
- **Risk:** too low a cap makes containers or the database inside WSL run out of memory -
  raise it if they get killed.
- Newer WSL versions return freed memory to Windows over time; check
  `wsl --version` and the WSL documentation for `autoMemoryReclaim` on your version rather
  than copying a setting from an old blog post.

## Docker Desktop / Podman resource limits

- Docker Desktop on the WSL 2 backend, and Podman machines using the WSL provider (the
  Windows default), follow `.wslconfig`; Docker's own CPU/memory sliders apply only to its
  Hyper-V backend.
- Podman with the Hyper-V provider, and Podman/Docker on a Mac: `podman machine inspect`
  shows CPUs and memory; `podman machine stop`, then
  `podman machine set --cpus 4 --memory 8192`, then `podman machine start` (undo: set the
  old values). Docker Desktop for Mac: Settings > Resources.
- Containers that only serve tests (database, cache) rarely need more than a few cores.
  `docker run --cpus 2 --memory 2g ...` caps one container.
- Bind-mounting a Windows folder into a Linux container goes through the same slow
  file-sharing path as `/mnt/c`; prefer named volumes for database data.

## A Linux lane for a Windows-hosted test suite

A large test suite developed on Windows can often run faster in a WSL 2 distro, with the
code on the distro's own ext4 disk (not `/mnt/...`). In one measurement (a large Rust
workspace with PostgreSQL-backed integration tests), the tests ran about **25% faster** in
WSL than on Windows, the compile took about the same time, and the build folder needed
**less than half the disk** (about 47 GB against about 110 GB: no `.pdb` debug files).
Defender doesn't scan inside the ext4 disk, and process start-up and file creation are
cheaper on Linux.

- **Measure before switching, per step.** Run the same check on both sides with a
  timestamp on every log line (in the distro: pipe through `ts '%H:%M:%S'` from
  `moreutils`; in PowerShell: `ForEach-Object { "$(Get-Date -Format HH:mm:ss) $_" }`).
  Compare compile, test start-up and each test group separately: a lane that wins on tests
  but loses on compile may not pay off for short runs.
- **Gain:** faster full test runs, less build output on the Windows drives, and a Linux run
  that is closer to CI. Check against the baseline full-check time.
- **Risk:** a second copy of the toolchain and caches to keep up to date; the clock and
  networking side effects below; WSL and Windows still share cores and disk.
- **Undo:** stop using the lane and remove its distro (next section).

## A dedicated distro for the lane (no admin needed)

Keep the lane in its own distro, apart from the one you use by hand, so its packages,
services and settings can't surprise you, and you can throw it away. Once WSL itself is
installed, adding a distro needs no administrator rights. Newer WSL (check `wsl --help`
for `--name` and `--location`):

```powershell
wsl --list --online                                    # names you can install
wsl --install <Distro> --name <name> --location D:\WSL\<name> --no-launch
wsl -d <name>                                          # first start: create the user
```

- `--location` puts its disk on the dev drive instead of under the user profile on C:.
- **Gain:** a clean, reproducible lane; nothing it installs touches your everyday distro.
- **Risk:** a few GB per distro; one more set of packages to update.
- **Undo:** `wsl --unregister <name>`. This **deletes the distro and everything in its
  disk** for good; `wsl --export <name> <file>.tar` first if anything in it matters.

## Getting the code in, and driving the lane from Windows

- **Fetch with git from the Windows checkout** into ext4, instead of building through
  `/mnt`:
  ```bash
  git config --global --add safe.directory /mnt/d/src/app   # the Windows checkout
  git clone /mnt/d/src/app ~/src/app                        # once
  git -C ~/src/app fetch origin && git -C ~/src/app checkout --detach origin/<branch>
  ```
  `safe.directory` is needed because the Windows files look owned by another user. Name
  the one repo, not `*`: it tells git to trust that repo's config and hooks. Undo:
  `git config --global --unset-all safe.directory /mnt/d/src/app`. Fetch only sees
  committed work, not unsaved edits in the Windows checkout.
- **Private git dependencies** (e.g. cargo `git = "..."` dependencies): keep a local bare
  mirror and rewrite the URL to it, so the lane needs no credentials:
  ```bash
  git clone --mirror /mnt/d/src/private-dep ~/mirrors/private-dep.git   # once
  git -C ~/mirrors/private-dep.git fetch --prune                          # each run
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=url.$HOME/mirrors/private-dep.git.insteadOf
  export GIT_CONFIG_VALUE_0=https://github.com/<org>/private-dep
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  ```
  Set `CARGO_NET_GIT_FETCH_WITH_CLI=true`: cargo's built-in git ignores the
  `GIT_CONFIG_*` environment variables, so without it cargo still tries the real URL. (A
  permanent `git config --global url.<mirror>.insteadOf <url>` works too; undo with
  `git config --global --unset url.<mirror>.insteadOf`.) Risk: the mirror goes stale if
  the fetch is skipped.
- **Run commands with `wsl.exe --exec`**, so the arguments reach the program as they are
  instead of being re-parsed by a shell:
  ```powershell
  wsl.exe -d <name> --cd /home/<user>/src/app --exec ./scripts/check.sh --fast
  ```
  Without `--exec`, WSL hands the line to the distro's shell, and quotes, `$` and `;` are
  interpreted a second time. If you must pass a shell script, pass it as one argument to
  `--exec sh -c '...'` and avoid double quotes inside it: PowerShell versions quote embedded
  double quotes differently. When a script builds the `wsl.exe` command line itself, leave
  its options unquoted: `wsl.exe` reads the raw command line, and a quoted `"--list"` is
  not an option but a Linux command, run in the **default** distro, which that starts.
- **Probing from Windows starts distros.** Any `wsl -d <distro> ...` boots a stopped
  distro, with its services (a time daemon, a database). For read-only checks, list
  `wsl --list --running` first and probe only those.
- **From Git Bash**, prefix with `MSYS_NO_PATHCONV=1`, or Git Bash rewrites Linux paths such
  as `/home/<user>/src/app` into Windows paths before `wsl.exe` sees them:
  `MSYS_NO_PATHCONV=1 wsl.exe -d <name> --exec /home/<user>/src/app/scripts/check.sh`.

## One time source for all distros (clock steps back, random test failures)

All WSL 2 distros share **one Linux kernel**, and Hyper-V already keeps that kernel's
clock in sync with Windows. A time daemon (`systemd-timesyncd`, `chrony`, `ntpd`) in
**any** distro that runs systemd fights that sync: it slews the clock by changing the
kernel tick (seen: 10240-10328 instead of 10000), the clock runs fast, Hyper-V steps it
back, and the cycle repeats. Result: the clock **steps back about a second every minute,
in every distro**, including the ones without the daemon.

Time-sensitive tests then fail at random and pass on rerun: rate limits answering "too
soon", "newest first" lists in the wrong order, jobs "due now" that aren't due yet, expiry
checks off by a second.

**Symptoms (read-only checks, in any running distro):**

```bash
sudo dmesg | grep -c 'Time jumped backwards'      # count since the WSL kernel started
timedatectl timesync-status                       # offset ~1 s, poll interval stuck at its minimum
systemctl is-active systemd-timesyncd chrony chronyd ntp
# kernel tick, should be 10000 (adjtimex with modes = 0 only reads)
python3 -c 'import ctypes,sys; b=ctypes.create_string_buffer(256); ctypes.CDLL(None).adjtimex(b); print(int.from_bytes(b.raw[88:96], sys.byteorder, signed=True))'
# count backward clock steps for two minutes (should be 0)
python3 -c '
import time
prev, back, end = time.time_ns(), 0, time.monotonic() + 120
while time.monotonic() < end:
    t = time.time_ns(); back += t < prev; prev = t; time.sleep(0.01)
print("backward steps:", back)'
```

(`tick` sits at byte offset 88 of `struct timex` on 64-bit Linux.) The audit script runs
the daemon, tick and `dmesg` checks in each **running** distro; it doesn't start stopped
ones. The `dmesg` count covers everything since the WSL kernel started, so a problem that
was already fixed still shows; the audit also reports how long ago the last jump was.

**Fix**, in **every** distro that runs a time daemon (the user runs these; `-u root` needs
no password):

```powershell
wsl -d <distro> -u root -- systemctl disable --now systemd-timesyncd   # or chrony / chronyd
# then reset the kernel tick (ADJ_TICK|ADJ_FREQUENCY = 0x4002, tick 10000, frequency 0)...
wsl -d <distro> -u root --exec python3 -c "import ctypes,struct; b=ctypes.create_string_buffer(256); struct.pack_into('I',b,0,0x4002); struct.pack_into('q',b,88,10000); print(ctypes.CDLL(None).adjtimex(b))"
# ...or restart the WSL kernel instead (stops ALL distros; see the .wslconfig note above)
wsl --shutdown
```

Then rerun the tick check (10000) and the backward-step loop (0).

- **Gain:** the random time-based failures stop (seen: seven intermittent failures in one
  suite, gone after the fix).
- **Risk:** small. Windows, through Hyper-V, stays the one time source. After the host
  sleeps or hibernates, WSL's clock can lag until Hyper-V catches up; if it stays wrong,
  `wsl --shutdown` resets it.
- **Undo:** `wsl -d <distro> -u root -- systemctl enable --now systemd-timesyncd` (or
  `chrony`).

## Mirrored networking: side effects

With `networkingMode=mirrored` in `.wslconfig`, WSL and Windows share `localhost`. Windows
tools then reach Linux services directly, but:

- **Ports are shared.** A service in the distro can't use a port Windows already uses.
  Example: PostgreSQL on Windows holds 5432, so run the distro's test cluster on another
  port (`sudo pg_createcluster <version> test --port 5433 --start`) and switch off
  Ubuntu's default cluster so it doesn't try 5432 at boot
  (`echo manual | sudo tee /etc/postgresql/<version>/main/start.conf`, then
  `sudo pg_ctlcluster <version> main stop`). Undo: `echo auto | sudo tee` the same
  `start.conf`, and `sudo pg_dropcluster <version> test --stop`.
- **A connection to a closed localhost port is dropped, not refused.** Code or tests that
  expect "connection refused" at once (e.g. "server not up yet" or "service down" checks)
  wait out their whole timeout instead. If such tests are slow only in WSL, check this
  before tuning anything else; give them a short connect timeout.
- **It applies to every distro** and needs `wsl --shutdown` to change, like any
  `.wslconfig` setting. Risk of switching back to NAT mode: Windows tools that reach the
  distro's services on `localhost` stop working. Undo: remove the line and `wsl --shutdown`.

## One machine, two operating systems

WSL 2 and Windows share the same cores, RAM and disk. A full run in WSL and another on
Windows contend exactly like two Windows runs (`test-runs.md`):

- **One lock for heavy runs covers both.** Take it on the Windows side, in the script that
  starts the WSL run (`wsl.exe ... --exec ...`), so a Windows full check and a WSL full
  check never overlap.
- **Measure the disk before and after a run:** the distro's used space (`df -h /` inside,
  the `ext4.vhdx` file size outside) and the build folder (`du -sh ~/src/app/target`). The
  VHDX grows and doesn't shrink on its own; make it sparse or compact it as in `cleanup.md`,
  and clean the build folder there like any other.
