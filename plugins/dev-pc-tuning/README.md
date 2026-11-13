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

### Claude Code (recommended: updates come with the plugin)

```
/plugin marketplace add ffrachon/ai-skills
/plugin install dev-pc-tuning@ai-skills
```

Later updates: `/plugin marketplace update ai-skills`.

### Claude apps (claude.ai / desktop)

Download `dev-pc-tuning.skill` from the
[latest release](https://github.com/ffrachon/ai-skills/releases/latest) (or `dist/` at the
repo root), then open
*Settings > Capabilities > Skills* (the name may vary slightly by version), choose
*Upload skill*, and pick the file. Skills need to be enabled for your plan/organisation.

### Claude Code, manual install

The `.skill` file is a zip; unzip it into your personal skills folder:

```powershell
# Windows
Expand-Archive dev-pc-tuning.skill -DestinationPath "$env:USERPROFILE\.claude\skills" -Force
```
```bash
# macOS / Linux
mkdir -p ~/.claude/skills && unzip -o dev-pc-tuning.skill -d ~/.claude/skills
```

You should end up with `.claude/skills/dev-pc-tuning/SKILL.md`. Start a new session.

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
