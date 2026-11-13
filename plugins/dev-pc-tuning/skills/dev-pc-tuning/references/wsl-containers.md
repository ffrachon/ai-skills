# WSL 2, Docker and Podman: speed and resource limits

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
