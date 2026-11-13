# Git, Gradle and Node settings for big projects

All optional and per user or per repo; none touch security settings. Measure each.

## Git: faster `git status` in big repos

AI coding sessions and IDEs run `git status` constantly. In a repo with a large working tree
(many thousands of files), each call walks every folder.

```powershell
# per repo (run inside it); or add --global for all repos
git config core.fsmonitor true          # built-in file-watcher daemon (Git for Windows 2.37+)
git config core.untrackedCache true     # remember which folders had no new files
# measure before and after (run twice; the first call after enabling warms the cache):
Measure-Command { git status } | Select TotalMilliseconds
# undo:
git config --unset core.fsmonitor; git config --unset core.untrackedCache
git fsmonitor--daemon stop
```

- **Gain:** `git status` from seconds to well under a second in large trees; nothing in
  small repos - skip it there.
- **Cost:** one small background daemon per repo/worktree that has been used; not for
  network drives. `feature.manyFiles=true` sets the untracked cache and a compact index
  format in one go.
- Make sure build output is in `.gitignore` (`target/`, `build/`, `node_modules/`), or Git
  walks it too. `core.preloadindex` is already on by default.

## Gradle (Android builds of Flutter apps)

`<project>\android\gradle.properties` (per project) or `%USERPROFILE%\.gradle\gradle.properties`
(all projects; or under `GRADLE_USER_HOME`):

```properties
# reuse task outputs across builds and branches
org.gradle.caching=true
# build independent modules in parallel
org.gradle.parallel=true
# daemon heap; check what the project already sets before changing it
org.gradle.jvmargs=-Xmx4g
```

(In `.properties` files a `#` only starts a comment at the beginning of a line.)

- **Gain:** large on repeated Android builds and branch switches; none for `flutter test`,
  which doesn't use Gradle.
- **Cost:** cache disk space under the Gradle home (put it on the Dev Drive,
  `dev-drive.md`). The configuration cache (`org.gradle.configuration-cache=true`) can help
  more but breaks some plugins; try it on its own. Undo: delete the lines.
- **Daemons:** each Gradle version, and each differing set of JVM args, keeps its own daemon
  (often 1-4 GB each) for hours. With several sessions or worktrees,
  `gradlew --stop` (or `gradle --stop`) frees that memory; `gradlew --status` lists them.

## Node

- Prefer `pnpm` (hard-linked content store) or `npm ci` with a warm cache on the Dev Drive;
  installs write tens of thousands of small files, so the Dev Drive and Defender
  performance mode matter most here.
- Test runners (vitest, jest) default to one worker per core; with several sessions, cap
  them (`--maxWorkers=4` in both) rather than letting several runs overlap at full width.
