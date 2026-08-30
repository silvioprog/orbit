<p align="center">
  <img src="./orbit-logo.svg" alt="Orbit" width="180">
</p>

# Orbit

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-2ea44f?style=flat-square)](https://docs.claude.com/en/docs/claude-code/plugins) [![Graphify](https://img.shields.io/badge/Graphify-Optional-2ea44f?style=flat-square)](https://github.com/Graphify-Labs/graphify) [![License](https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square)](./LICENSE) [![Tests](https://img.shields.io/github/actions/workflow/status/silvioprog/orbit/tests.yml?branch=main&style=flat-square&label=Tests)](https://github.com/silvioprog/orbit/actions/workflows/tests.yml)

Orbit is a small, generic orchestration plugin for Claude Code: one command, `/orbit:cycle`, owns a task from understanding through an independent review. It delegates to cheap read-only exploration, focused implementation, and independent review subagents, orienting with a local code graph when Graphify is available.

## Prerequisites

- Claude Code.
- Native task tools. Orbit tracks its work in Claude Code's native task list, which the current Opus 4.8, Sonnet 5, Fable 5, and Mythos 5 families expose only when Claude Code is launched with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Orbit cannot set this startup variable itself.
- Optional but recommended: Graphify, for local code-graph orientation. Install with `brew install uv` then `uv tool install graphifyy`. Orbit works in both regular Git repositories and Git worktrees, each worktree getting its own external graph cache, and runs normally without Graphify.

## Install

```
/plugin marketplace add silvioprog/orbit
/plugin install orbit@orbit
```

Orbit ships versionless, so Claude tracks it by Git commit. Update it from a normal shell:

```
claude plugin marketplace update orbit
claude plugin update orbit@orbit
```

The first command refreshes the marketplace catalog; the second updates the installed cached plugin. In an already-open Claude Code session, apply the new version with `/reload-plugins`; restarting Claude Code is only an alternative, not a requirement.

## Use

```
/orbit:cycle <task, ticket URL, or instruction>
```

To run one of your own skills instead of Orbit's loop, name it first; Orbit dispatches it and preserves the skill's own behavior:

```
/orbit:cycle <skill-name> <args>
/loop /orbit:cycle <skill-name> <args>
```

`/loop` is Claude's own repeat and Orbit does not replace it.

## Configuration

Global defaults live at `~/.orbit/config.json`, created on first run. A trusted `.orbit/config.json` in a repository overrides them for that repo (repository over global over bundled; missing keys inherit the lower level). Supported keys are `graphify.enabled`, `coverage.requireNewCode`, and per-role Claude model aliases (`haiku`, `sonnet`, `opus`, `fable`).

On update, startup adds any new configuration keys to your global `~/.orbit/config.json` without ever overwriting your existing values. A changed bundled default value is not forced onto a config file you already have, because Orbit cannot tell an old copied default from a value you chose on purpose; adjust such a value yourself if you want the new default.

Graph building and subagent model/effort are enforced mechanically (the graph helper runs on every `/orbit:cycle`, and each agent pins its model and effort in frontmatter); requirement coverage and the optional new-code coverage rule are completion rules Orbit follows, not runtime-enforced hooks.

## Unattended runs

For genuinely unattended use (including `/loop /orbit:cycle`), Orbit ships plugin hooks that keep the loop from stalling on a permission dialog. While a session that was started by `/orbit:cycle` or `/loop /orbit:cycle` is active, the hooks deny any permission request without interrupting the turn and deny `AskUserQuestion`, then return control to Claude with instructions to retry through a native `Read`, `Glob`, or `Grep`, a statically scoped command using explicit paths or `git -C`, or a genuine `Blocked:` result. This does not make a denied operation succeed and it never approves anything: it turns an unattended stall into a normal denial. The hooks store only per-session activation state under the plugin's own data directory, take effect only for active Orbit sessions, and clear when the run finishes with `Done.` or the session ends, so ordinary Claude Code permission behavior in other sessions is unchanged.

## Uninstall

```
/plugin uninstall orbit@orbit
/plugin marketplace remove orbit
```

Orbit keeps its config and external code graphs under `~/.orbit`; remove them with `rm -rf ~/.orbit`.

## License

Orbit is available under the [MIT License](./LICENSE).
