# dev-pc-tuning - a Claude skill

Helps you make a Windows PC (and optionally a Mac) faster for heavy development work:
large Rust / Flutter / Node builds, long test suites, local PostgreSQL or containers, several
AI coding sessions at once.

It works in four steps: **audit (read-only) -> measure -> recommend -> you apply**. Claude
never changes security settings, antivirus exclusions or system configuration itself. Every
recommendation comes with the expected gain, the risk and the undo command, for you to run
in your own admin PowerShell.

Topics covered: Dev Drive (ReFS) and Defender performance mode, measuring Defender with a
performance recording before excluding anything, narrow vs whole-drive exclusions (and the
habits that go with them), moving build/test temp files instead of excluding Temp, why
turning off indexing usually gains nothing, cleaning 60-115 GB `target` folders and WSL
disks, running one heavy test suite at a time, fewer test binaries, faster test databases
(template databases, non-durable settings for throwaway clusters), optional Rust speed-ups
(linker, sccache, debug info), git/Gradle settings for big repos, WSL file placement and
memory caps, power throttling, how security features like Smart App Control and memory
integrity weigh in (your decision), and the macOS Developer Tools exemption and Rosetta check.

## Install

Pick the line that matches where you use Claude. In every case the skill becomes available
in new conversations or sessions; there is nothing to configure.

| You use | Easiest way | Updates |
|---|---|---|
| **Claude desktop app** (Chat or Code tab) | A. Add the plugin marketplace in Settings | automatic, from the marketplace |
| **Claude Code in a terminal** | B. Two `/plugin` commands | automatic, from the marketplace |
| **claude.ai in a browser** | C. Upload the `.skill` file | re-upload new versions |

### A. Claude desktop app

Typing `/plugin ...` in the desktop app only opens the plugin settings page; it does not run
the rest of the command. Add the marketplace there instead:

1. Open **Settings > Customize > Plugins** (or type `/plugin` in a message box).
2. Click the **+ Add** button (top right) and choose the option to add a **marketplace**
   (from GitHub / from a URL).
3. Enter `ffrachon/ai-skills` (or `https://github.com/ffrachon/ai-skills` if it asks for a
   URL) and confirm.
4. Search for **dev-pc-tuning**: it now appears with *ai-skills* as its source. Install it
   (the **+** button).

Searching for `dev-pc-tuning` **before** step 3 finds nothing: the search only covers
marketplaces that have already been added.

If your version of the app has no marketplace option under **+ Add**, use C (upload) or the
terminal commands in B instead.

### B. Claude Code in a terminal

Inside a `claude` session:

```
/plugin marketplace add ffrachon/ai-skills
/plugin install dev-pc-tuning@ai-skills
```

or straight from the shell:

```bash
claude plugin marketplace add ffrachon/ai-skills
claude plugin install dev-pc-tuning@ai-skills
```

Restart Claude Code if the skill doesn't show up straight away. Later updates:
`/plugin marketplace update ai-skills`. Remove: `/plugin uninstall dev-pc-tuning@ai-skills`.

### C. Upload the skill file (claude.ai, or any app without plugins)

1. Download **`dev-pc-tuning.skill`** from the
   [latest release](https://github.com/ffrachon/ai-skills/releases/latest).
2. Open **Settings > Customize > Skills** (older versions: *Settings > Capabilities >
   Skills*), choose **Upload skill** (under **+ Add** in newer versions) and pick the file.
3. Skills must be enabled for your plan or organisation; if you can't see a Skills section,
   ask your admin.

For a new version, download and upload the new file again.

### D. Manual install for Claude Code

The `.skill` file is a zip. Unzip it into your personal skills folder:

```powershell
# Windows
Expand-Archive dev-pc-tuning.skill -DestinationPath "$env:USERPROFILE\.claude\skills" -Force
```
```bash
# macOS / Linux
mkdir -p ~/.claude/skills && unzip -o dev-pc-tuning.skill -d ~/.claude/skills
```

You should end up with `.claude/skills/dev-pc-tuning/SKILL.md`. Start a new session.

### Check it works

Start a new conversation and ask: *"My builds are slow on this PC, can you check my
setup?"* Claude should say it is using the **dev-pc-tuning** skill and offer to run the
read-only audit.

## Use

Just ask, for example: *"My Rust builds and tests are slow on Windows, can you check my
setup?"* or *"Should I exclude my dev drive from Defender?"*

The audit script can also be run on its own. It only reads; admin is optional, and without
admin the Defender-exclusion and Dev Drive detail lines say "needs admin":

```powershell
powershell -ExecutionPolicy Bypass -File skills\dev-pc-tuning\scripts\audit.ps1 -DevRoot D:\src
```

Options: `-DevRoot <folders>`, `-MaxDepth <n>`, `-SkipSizes` (faster), `-Json`.

## Disclaimer

This skill gives advice about antivirus, security features and system settings. Several of
the changes it discusses trade some protection for speed. It is provided as is, without
warranty (see [LICENSE](../../LICENSE)):

- You decide what to apply, and you run every command yourself. Read each one first.
- Measure before and after; undo anything that didn't help, especially changes with a
  security cost.
- On a work or managed PC, follow your organisation's policy; exclusions and security
  features may be managed by IT for good reasons.
- Commands and product behaviour change between Windows, Defender and toolchain versions.
  Check against current vendor documentation if something doesn't match.

## Folder layout

```
.claude-plugin/plugin.json      plugin manifest
skills/dev-pc-tuning/           the skill
  SKILL.md                      workflow and rules
  scripts/audit.ps1             read-only audit (run from this folder as shown above)
  references/*.md               notes per topic
```

The packaged `dev-pc-tuning.skill` is in `dist/` at the repo root (`python build.py` there
rebuilds it).

## Licence

MIT - see [LICENSE](../../LICENSE).
