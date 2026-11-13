# ai-skills

Skills for Claude (Claude Code and the Claude apps).

| Skill | What it does |
|---|---|
| [dev-pc-tuning](plugins/dev-pc-tuning/) | Audit and tune a Windows PC (and optionally a Mac) for heavy development work: large Rust / Flutter / Node builds, long test suites, local databases and containers, several AI coding sessions at once. Read-only audit, measure, then recommendations you apply yourself. |

## Install

| You use | How |
|---|---|
| **Claude desktop app** | **Settings > Customize > Plugins > + Add** > add a marketplace > `ffrachon/ai-skills`, then install the skill from the list. (Typing `/plugin ...` in the app only opens this page.) |
| **Claude Code in a terminal** | `/plugin marketplace add ffrachon/ai-skills`, then `/plugin install <skill>@ai-skills` |
| **claude.ai in a browser** | Download the `.skill` file from the [latest release](https://github.com/ffrachon/ai-skills/releases/latest) and upload it under **Settings > Customize > Skills** |

Step-by-step instructions, with fallbacks: see each skill's README, e.g.
[dev-pc-tuning](plugins/dev-pc-tuning/README.md#install).

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
