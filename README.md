# pr-review-lenses

A faithful port of Anthropic's [`pr-review-toolkit`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) Claude Code plugin to **GitHub Copilot CLI** and **opencode**.

Same six specialized review lenses plus an orchestrator, ported to each runtime's agent format (`.agent.md` for Copilot, `mode`/`permission` frontmatter for opencode). The tools use different formats, so the personas are ported rather than dropped in.

## The agents

| Agent | What it does | Edits code? |
|-------|--------------|-------------|
| `code-reviewer` | General quality + project-guideline compliance + bug detection. Confidence-scored 0-100, reports only >=80. | No (advisory) |
| `silent-failure-hunter` | Hunts silent failures, broad catch blocks, unjustified fallbacks, missing error logging. | No (advisory) |
| `type-design-analyzer` | Rates encapsulation, invariant expression/usefulness/enforcement of new types, 1-10 each. | No (advisory) |
| `comment-analyzer` | Checks comment accuracy vs. code and flags comment rot. | No (advisory) |
| `pr-test-analyzer` | Behavioral test-coverage gaps, criticality-rated 1-10. | No (advisory) |
| `code-simplifier` | Simplifies recently-changed code, preserving behavior. | **Yes** |
| `review-pr` | Orchestrator: delegates to the applicable reviewers as **subagents** and merges their findings into one prioritized report. | No |

## Install

### Recommended: as a Copilot CLI plugin

Register this repo as a marketplace, then install the plugin. Copilot then manages updates and removal for you:

```sh
copilot plugin marketplace add costajohnt/pr-review-lenses
copilot plugin install pr-review-toolkit@pr-review-lenses
```

Update later with `copilot plugin update pr-review-toolkit`; remove with `copilot plugin uninstall pr-review-toolkit`.

### Alternative: install script (no plugin system)

One-liner, copies the agents into `~/.copilot/agents/`:

```sh
curl -fsSL https://raw.githubusercontent.com/costajohnt/pr-review-lenses/main/install.sh | bash
```

Or clone and run it:

```sh
git clone https://github.com/costajohnt/pr-review-lenses.git
cd pr-review-lenses
./install.sh          # user-level: ~/.copilot/agents  (every repo on your machine)
./install.sh --repo   # repo-level: ./.github/agents    (commit into one project)
```

### Manual

```sh
cp plugins/pr-review-toolkit/agents/*.agent.md ~/.copilot/agents/
```

## Use

In an interactive Copilot CLI session:

```
/agent                      # pick an agent from the list
```

Or invoke by name in a prompt: `Use the silent-failure-hunter agent on my staged changes.`

Or non-interactively:

```sh
copilot --agent code-reviewer  -p "Review my unstaged changes"
copilot --agent review-pr      -p "Review this branch against main"
copilot --agent review-pr      -p "Review only tests and error handling"
```

The agents read the diff themselves (`git diff` by default; `git diff main...HEAD` for a branch/PR).

## Repo layout

```
.github/plugin/marketplace.json     # makes the repo a Copilot CLI marketplace
.github/workflows/ci.yml            # CI: JSON validity, shellcheck, agent frontmatter
plugins/pr-review-toolkit/
  plugin.json                       # the plugin manifest
  agents/*.agent.md                 # the 7 agents (Copilot CLI format)
  agents-opencode/*.md              # the same 7 agents (opencode format)
install.sh                          # non-plugin fallback installer
```

## Notes

- **Subagent orchestration.** `review-pr` has the `agent` tool in its frontmatter, which lets it delegate to the other agents as subagents (each getting a fresh, isolated context). That's the closest equivalent to the Claude plugin's parallel `Task` fan-out.
- **Advisory vs. editing.** Every reviewer except `code-simplifier` only reports findings. `code-simplifier` actually rewrites code, so `review-pr` never runs it automatically - it only recommends it.
- **Project guidelines.** The originals were written for one specific codebase (Sentry/Statsig/`errorIds.ts`). These ports are genericized to defer to whatever your repo provides: `AGENTS.md`, `.github/copilot-instructions.md`, `CLAUDE.md`, `CONTRIBUTING.md`, or configured linters.
- **Restricting tools.** Reviewers use `tools: ["read", "search", "shell"]`. The prompts tell them to use shell only for `git diff`, but Copilot CLI's `shell` entry is unrestricted, so that limit is prompt text, not enforcement. Tighten or loosen per your comfort; omitting `tools` entirely grants all tools.

## opencode

The same five advisory lenses, `code-simplifier`, and the `review-pr` orchestrator are also shipped in [opencode](https://opencode.ai) agent format under `plugins/pr-review-toolkit/agents-opencode/`. Same personas, different frontmatter: opencode uses a `mode` field and a `permission:` block (`edit`, `webfetch`, a `bash` allow/deny map, and `task` for delegation) instead of Copilot's `tools` array.

Permissions per lens:

- The five advisory reviewers (`code-reviewer`, `silent-failure-hunter`, `type-design-analyzer`, `comment-analyzer`, `pr-test-analyzer`) run with `edit: deny` so they can only report.
- `code-simplifier` runs with `edit: allow` since it rewrites code in place.
- The five advisory reviewers (and `review-pr`) allow only read-only git commands (`git diff`, `git log`, `git show`, `git status`, `git branch` in list mode, `git ls-files`); any other shell command falls through to `"*": ask`. The allow patterns are space-anchored (`"git diff *"`, not `"git diff*"`) so `git difftool` does not match; `--output=<file>` and any command containing a shell operator (`;`, `|`, `&`, `>`, `<`, `$(`, backtick, newline) are set to `ask`, since opencode matches patterns against the whole command string. `git grep` is not allowed because its `-O` / `--open-files-in-pager` flags exec a program and cannot be reliably excluded by pattern; the built-in `grep` tool covers search. opencode resolves overlapping bash patterns with last-match-wins in config order, which is why every block lists its catch-all `"*"` first.
- `code-simplifier` allows shell generally but denies `git push`, `gh pr`, `gh api`, and `rm -rf`.
- The six lenses use `mode: all`, so you can Tab to any one directly or have the orchestrator delegate to it.

`review-pr` is the orchestrator (`mode: primary`). opencode primary agents invoke subagents via the Task tool, so it delegates to the applicable advisory lenses and aggregates their findings into one prioritized report, same as the Copilot version. Its `permission.task` block allows the five advisory reviewers, and gates `code-simplifier` behind `ask` (it edits, so it is never auto-run during review).

To use them, copy the files into your project's `.opencode/agent/` directory (or the global `~/.config/opencode/agent/`), then select the agent in an opencode session:

```sh
cp plugins/pr-review-toolkit/agents-opencode/*.md .opencode/agent/
```

These agents need a model that supports tool use (they run `git diff` and, for `review-pr`, the Task tool). If your provider routes to a non-tool model you'll see `No endpoints found that support tool use`; pick a tool-capable model, e.g.:

```sh
opencode run --agent review-pr -m openrouter/anthropic/claude-haiku-4.5 "Review my unstaged diff"
```

Verified against opencode 1.18.4: `review-pr` runs `git diff`, delegates to the applicable advisory lenses via the Task tool, and aggregates one prioritized report.

## Disclaimer

This is an independent, community project. It is not built by, affiliated with, or endorsed by Anthropic, GitHub, Microsoft, or the opencode team. It ports Anthropic's open-source `pr-review-toolkit` and packages the result for the GitHub Copilot CLI and opencode. "Claude", "GitHub Copilot", and "opencode" are trademarks of their respective owners; they are used here only to describe compatibility.

## License

Apache License 2.0. This is a derivative work of the `pr-review-toolkit` plugin from Anthropic's [claude-plugins-official](https://github.com/anthropics/claude-plugins-official) (also Apache 2.0). See `LICENSE` for the full text and `NOTICE` for attribution and a summary of changes.
