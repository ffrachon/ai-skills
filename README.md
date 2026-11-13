# ai-skills

Skills for Claude (Claude Code and the Claude apps).

| Skill | What it does |
|---|---|
| [dev-pc-tuning](plugins/dev-pc-tuning/) | Audit and tune a Windows PC (and optionally a Mac) for heavy development work: large Rust / Flutter / Node builds, long test suites, local databases and containers, several AI coding sessions at once. Read-only audit, measure, then recommendations you apply yourself. |

## Install

### Claude Code

Add this repository as a plugin marketplace once, then install the skills you want:

```
/plugin marketplace add ffrachon/ai-skills
/plugin install dev-pc-tuning@ai-skills
```

Restart Claude Code if the skill doesn't show up straight away. To get updates later:
`/plugin marketplace update ai-skills`.

### Claude apps (claude.ai / desktop)

Download the skill's `.skill` file from the
[latest release](https://github.com/ffrachon/ai-skills/releases/latest) (or from `dist/`),
then open *Settings > Capabilities > Skills*, choose *Upload skill* and pick the file.
Skills must be enabled for your plan or organisation.

### Manual (Claude Code)

A `.skill` file is a zip. Unzip it into `~/.claude/skills/` (Windows:
`%USERPROFILE%\.claude\skills\`) so you get `~/.claude/skills/<skill>/SKILL.md`.

## Layout

```
.claude-plugin/marketplace.json     marketplace listing all plugins
plugins/<plugin>/
  .claude-plugin/plugin.json        plugin manifest
  README.md                         what the skill does, disclaimer
  skills/<skill>/SKILL.md           the skill (plus scripts/, references/)
dist/<skill>.skill                  packaged skills for the Claude apps
build.py                            rebuilds everything in dist/
```

After editing a skill: `python build.py`, bump `version` in `plugin.json` and in
`marketplace.json`, commit, and attach the new `.skill` to a release.

## Licence

MIT - see [LICENSE](LICENSE). Provided as is, without warranty; each skill's README has
its own disclaimer.
