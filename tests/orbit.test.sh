#!/usr/bin/env sh
set -u

script_dir="$(cd "$(dirname "$0")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
helper="${ORBIT_HELPER:-$root_dir/claude/bin/orbit-graph.sh}"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

dsum() { find "$1" -type f -exec shasum {} \; 2>/dev/null | sort | shasum | cut -d' ' -f1; }

make_repo() {
  r="$1"
  mkdir -p "$r/src"
  printf 'def alpha(x):\n    return x + 1\n' > "$r/src/a.py"
  ( cd "$r" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}

fake_valid() {
  cat > "$1/graphify" <<'SH'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$out/graphify-out/cache"
printf '{"nodes":[{"id":"n1"}],"links":[]}\n' > "$out/graphify-out/graph.json"
printf '{"files":{"src/a.py":"h1"}}\n' > "$out/graphify-out/manifest.json"
printf 'n1\n' > "$out/graphify-out/cache/nodes.idx"
exit 0
SH
  chmod +x "$1/graphify"
}
fake_zero_nograph() {
  printf '#!/bin/sh\nexit 0\n' > "$1/graphify"
  chmod +x "$1/graphify"
}
fake_nonzero() {
  printf '#!/bin/sh\nexit 7\n' > "$1/graphify"
  chmod +x "$1/graphify"
}
fake_invalid() {
  cat > "$1/graphify" <<'SH'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$out/graphify-out"
printf 'not json {{{\n' > "$out/graphify-out/graph.json"
exit 0
SH
  chmod +x "$1/graphify"
}

if [ ! -f "$helper" ]; then no "helper exists at $helper"; printf '\n%s passed, %s failed\n' "$pass" "$fail"; exit 1; fi
sh -n "$helper" && ok "helper passes sh -n" || no "helper passes sh -n"

repo="$work/repo"; make_repo "$repo"
bin="$work/bin"; mkdir -p "$bin"; fake_valid "$bin"
oh="$work/orbit"

out="$( cd "$repo" && ORBIT_HOME="$oh" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"
case "$out" in
  "$oh"/graphs/*/graphify-out/graph.json) ok "valid extractor prints external graph path" ;;
  *) no "valid extractor prints external graph path (got: $out)" ;;
esac
[ -f "$out" ] && ok "graph.json exists at printed path" || no "graph.json exists at printed path"
[ -d "$repo/graphify-out" ] && no "no graphify-out written into repo" || ok "no graphify-out written into repo"

gdir="$(dirname "$(dirname "$out")")"
live="$gdir/graphify-out"
sum_before="$(dsum "$live")"
manifest_before="$(cat "$live/manifest.json" 2>/dev/null)"
cache_before="$(cat "$live/cache/nodes.idx" 2>/dev/null)"

fake_zero_nograph "$bin"
outz="$( cd "$repo" && ORBIT_HOME="$oh" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"; rcz=$?
[ -z "$outz" ] && ok "zero-exit no-graph extractor prints no path" || no "zero-exit no-graph extractor prints no path (got: $outz)"
[ "$rcz" -ne 0 ] && ok "zero-exit no-graph extractor returns nonzero" || no "zero-exit no-graph extractor returns nonzero"
[ "$(dsum "$live")" = "$sum_before" ] && ok "zero-exit no-graph extractor preserves live byte-for-byte" || no "zero-exit no-graph extractor preserves live byte-for-byte"
[ "$(cat "$live/manifest.json" 2>/dev/null)" = "$manifest_before" ] && ok "zero-exit no-graph extractor preserves manifest sentinel" || no "zero-exit no-graph extractor preserves manifest sentinel"
[ "$(cat "$live/cache/nodes.idx" 2>/dev/null)" = "$cache_before" ] && ok "zero-exit no-graph extractor preserves cache sentinel" || no "zero-exit no-graph extractor preserves cache sentinel"

fake_nonzero "$bin"
out2="$( cd "$repo" && ORBIT_HOME="$oh" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"; rc2=$?
[ -z "$out2" ] && ok "nonzero extractor prints no path" || no "nonzero extractor prints no path (got: $out2)"
[ "$rc2" -ne 0 ] && ok "nonzero extractor returns nonzero" || no "nonzero extractor returns nonzero"
[ "$(dsum "$live")" = "$sum_before" ] && ok "nonzero extractor preserves live graph byte-for-byte" || no "nonzero extractor preserves live graph byte-for-byte"

fake_invalid "$bin"
out3="$( cd "$repo" && ORBIT_HOME="$oh" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"; rc3=$?
[ -z "$out3" ] && ok "invalid-json extractor prints no path" || no "invalid-json extractor prints no path (got: $out3)"
[ "$rc3" -ne 0 ] && ok "invalid-json extractor returns nonzero" || no "invalid-json extractor returns nonzero"
[ "$(dsum "$live")" = "$sum_before" ] && ok "invalid-json extractor preserves live graph byte-for-byte" || no "invalid-json extractor preserves live graph byte-for-byte"

leftover="$(find "$gdir" -maxdepth 1 -name '.staging.*' -o -maxdepth 1 -name '.prev.*' 2>/dev/null)"
[ -z "$leftover" ] && ok "no leftover staging or prev directories" || no "no leftover staging or prev directories"

fake_valid "$bin"
oh2="$work/orbit2"
printf '{"graphify":{"enabled":false}}\n' > "$work/global_off.json"
mkdir -p "$oh2"; cp "$work/global_off.json" "$oh2/config.json"
out4="$( cd "$repo" && ORBIT_HOME="$oh2" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"
[ -z "$out4" ] && ok "graphify.enabled=false skips extraction" || no "graphify.enabled=false skips extraction (got: $out4)"

repo2="$work/repo2"; make_repo "$repo2"
mkdir -p "$repo2/.orbit"; printf '{"graphify":{"enabled":true}}\n' > "$repo2/.orbit/config.json"
oh3="$work/orbit3"; mkdir -p "$oh3"; printf '{"graphify":{"enabled":false}}\n' > "$oh3/config.json"
out5="$( cd "$repo2" && ORBIT_HOME="$oh3" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"
[ -n "$out5" ] && ok "repo config enabled=true overrides global false" || no "repo config enabled=true overrides global false"

printf '{"graphify":{"enabled":false}}\n' > "$repo2/.orbit/config.json"
printf '{"graphify":{"enabled":true}}\n' > "$oh3/config.json"
out6="$( cd "$repo2" && ORBIT_HOME="$oh3" PATH="$bin:$PATH" sh "$helper" 2>/dev/null )"
[ -z "$out6" ] && ok "repo config enabled=false overrides global true" || no "repo config enabled=false overrides global true"

for j in "$root_dir/.claude-plugin/marketplace.json" "$root_dir/claude/.claude-plugin/plugin.json" "$root_dir/claude/config/config.default.json"; do
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" 2>/dev/null; then ok "valid json: ${j#$root_dir/}"; else no "valid json: ${j#$root_dir/}"; fi
done

cmd_dir="$root_dir/claude/commands"
[ -f "$cmd_dir/cycle.md" ] && ok "command cycle.md exists" || no "command cycle.md exists"
[ ! -e "$cmd_dir/work.md" ] && ok "command work.md is gone" || no "command work.md is gone"
head -n1 "$cmd_dir/cycle.md" 2>/dev/null | grep -q '^---$' && ok "command cycle.md has frontmatter" || no "command cycle.md has frontmatter"
grep -q '/orbit:cycle' "$root_dir/README.md" && ok "README documents /orbit:cycle command" || no "README documents /orbit:cycle command"

grep -qF 'select:TaskCreate' "$cmd_dir/cycle.md" && ok "cycle.md loads TaskCreate via ToolSearch select" || no "cycle.md loads TaskCreate via ToolSearch select"
grep -qF 'select:TaskUpdate' "$cmd_dir/cycle.md" && ok "cycle.md loads TaskUpdate via ToolSearch select" || no "cycle.md loads TaskUpdate via ToolSearch select"
grep -qF 'select:TaskList' "$cmd_dir/cycle.md" && ok "cycle.md loads TaskList via ToolSearch select" || no "cycle.md loads TaskList via ToolSearch select"
grep -qi 'ONE task per call' "$cmd_dir/cycle.md" && ok "cycle.md states one task per call" || no "cycle.md states one task per call"
grep -qF 'Blocked: restart Claude Code with CLAUDE_CODE_ENABLE_TODO_TOOLS=1.' "$cmd_dir/cycle.md" && ok "cycle.md has the todo-tools blocked message" || no "cycle.md has the todo-tools blocked message"
grep -qF 'CLAUDE_CODE_ENABLE_TODO_TOOLS=1' "$root_dir/README.md" && ok "README documents CLAUDE_CODE_ENABLE_TODO_TOOLS" || no "README documents CLAUDE_CODE_ENABLE_TODO_TOOLS"

agent_dir="$root_dir/claude/agents"
grep -qF 'CLAUDE.md' "$cmd_dir/cycle.md" && grep -qF 'AGENTS.md' "$cmd_dir/cycle.md" && ok "cycle.md recognizes CLAUDE.md and AGENTS.md" || no "cycle.md recognizes CLAUDE.md and AGENTS.md"
grep -qF 'does not exist, continue normally' "$cmd_dir/cycle.md" && ok "cycle.md treats missing AGENTS.md as non-blocking" || no "cycle.md treats missing AGENTS.md as non-blocking"
grep -qi 'orchestration-only' "$cmd_dir/cycle.md" && ok "cycle.md forbids coordinator-side repository writes" || no "cycle.md forbids coordinator-side repository writes"
grep -qF 'reviewer brief you write must carry' "$cmd_dir/cycle.md" && ok "cycle.md requires instruction paths in every subagent brief" || no "cycle.md requires instruction paths in every subagent brief"
grep -qF 'repository instruction files named in your brief' "$agent_dir/orbit-implementer.md" && ok "orbit-implementer must read applicable instruction files" || no "orbit-implementer must read applicable instruction files"
grep -qi 'untracked files' "$agent_dir/orbit-reviewer.md" && ok "orbit-reviewer obtains the full changed-file set including untracked" || no "orbit-reviewer obtains the full changed-file set including untracked"
grep -qF 'read them directly' "$agent_dir/orbit-reviewer.md" && ok "orbit-reviewer reads applicable instruction files directly" || no "orbit-reviewer reads applicable instruction files directly"
grep -qF 'check every changed file against' "$agent_dir/orbit-reviewer.md" && ok "orbit-reviewer checks changed files against scoped instructions" || no "orbit-reviewer checks changed files against scoped instructions"

colon=":"
old_ref="orbit${colon}work"
old_dash="orbit-""work"
if ! git -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  no "stale-reference checks require a valid git worktree"
else
  stale_content="$(git -C "$root_dir" grep -iIl -e "$old_ref" -e "$old_dash" -- .)"; grc=$?
  if [ "$grc" -gt 1 ]; then
    no "no stale orbit command reference remains (git grep failed rc=$grc)"
  elif [ -n "$stale_content" ]; then
    no "no stale orbit command reference remains ($stale_content)"
  else
    ok "no stale orbit command reference remains"
  fi
  files_out="$(git -C "$root_dir" ls-files)"; lrc=$?
  if [ "$lrc" -ne 0 ]; then
    no "no stale orbit command filename remains (git ls-files failed rc=$lrc)"
  else
    stale_name="$(printf '%s\n' "$files_out" | grep -i -e "$old_ref" -e "$old_dash" || true)"
    if [ -n "$stale_name" ]; then
      no "no stale orbit command filename remains ($stale_name)"
    else
      ok "no stale orbit command filename remains"
    fi
  fi
fi

cyc="$cmd_dir/cycle.md"
readme="$root_dir/README.md"
impl="$agent_dir/orbit-implementer.md"

fm="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f {print}' "$cyc")"
printf '%s\n' "$fm" | grep -qF 'disallowed-tools: AskUserQuestion' && ok "cycle.md frontmatter disables AskUserQuestion" || no "cycle.md frontmatter disables AskUserQuestion"
printf '%s\n' "$fm" | grep -qF 'argument-hint' && ok "cycle.md frontmatter still declares argument-hint" || no "cycle.md frontmatter still declares argument-hint"
if printf '%s\n' "$fm" | grep -qF 'AskUserQuestion'; then ok "AskUserQuestion suppression lives in the frontmatter, not only prose"; else no "AskUserQuestion suppression lives in the frontmatter, not only prose"; fi
grep -qF 'ask the user to choose in prose' "$cyc" && ok "cycle.md forbids asking equivalent questions in prose" || no "cycle.md forbids asking equivalent questions in prose"
grep -qF 'turning it into a question for the user' "$cyc" && ok "cycle.md declines product-preference findings without asking" || no "cycle.md declines product-preference findings without asking"

grep -qF 'before you load or dispatch any explicit skill' "$cyc" && ok "native-task gate precedes explicit skill execution" || no "native-task gate precedes explicit skill execution"
grep -qF 'run a `Bash` command' "$cyc" && ok "native-task gate precedes model-initiated Bash" || no "native-task gate precedes model-initiated Bash"
gate_ln="$(grep -n '^## Native task list' "$cyc" | head -n1 | cut -d: -f1)"
skill_ln="$(grep -n '^## Explicit skill dispatch' "$cyc" | head -n1 | cut -d: -f1)"
if [ -n "$gate_ln" ] && [ -n "$skill_ln" ] && [ "$gate_ln" -lt "$skill_ln" ]; then ok "native-task section precedes explicit skill dispatch section"; else no "native-task section precedes explicit skill dispatch section"; fi

grep -qF 'do not recreate it and do not add duplicate tasks' "$cyc" && ok "loop fire reuses the native list" || no "loop fire reuses the native list"
grep -qF 'reuses the existing native list' "$cyc" && ok "loop fire does not duplicate tasks" || no "loop fire does not duplicate tasks"

grep -qF 'runs inline in this main session' "$cyc" && ok "scheduler-owning skills run inline" || no "scheduler-owning skills run inline"
grep -qF 'Do not send it to a background' "$cyc" && ok "loop-owning skills stay out of background subagents" || no "loop-owning skills stay out of background subagents"
grep -qF 'ScheduleWakeup' "$cyc" && ok "cycle.md names ScheduleWakeup as session-owned" || no "cycle.md names ScheduleWakeup as session-owned"
grep -qF 'An ordinary one-shot skill keeps subagent routing' "$cyc" && ok "ordinary skills keep subagent routing" || no "ordinary skills keep subagent routing"
grep -qF 'general-purpose' "$cyc" && ok "ordinary skill routing still uses a general-purpose subagent" || no "ordinary skill routing still uses a general-purpose subagent"
grep -qF 'not by its name' "$cyc" && ok "skill routing decides by need not by name" || no "skill routing decides by need not by name"

grep -qi 'shadow-monitor' "$cyc" && ok "cycle.md forbids shadow-monitoring the inline skill" || no "cycle.md forbids shadow-monitoring the inline skill"
grep -qF 'reproduce its query, trigger, or termination logic' "$cyc" && ok "cycle.md forbids reconstructing the skill protocol" || no "cycle.md forbids reconstructing the skill protocol"
grep -qF 'task ID you merely remember' "$cyc" && ok "cycle.md forbids stopping with a remembered task ID" || no "cycle.md forbids stopping with a remembered task ID"
grep -qF 'confirm through `TaskList` that the exact task still exists' "$cyc" && ok "cycle.md verifies a task is live before stopping" || no "cycle.md verifies a task is live before stopping"

grep -qF 'ambiguous relative recursive command' "$cyc" && ok "cycle.md forbids cd-then-relative-recursive commands" || no "cycle.md forbids cd-then-relative-recursive commands"
grep -qF 'git -C <root>' "$cyc" && ok "cycle.md requires resolved absolute paths or git -C" || no "cycle.md requires resolved absolute paths or git -C"
grep -qF 'producing no evidence' "$cyc" && ok "cycle.md treats a denied or failed command as no evidence" || no "cycle.md treats a denied or failed command as no evidence"
grep -qF 'never proof that' "$cyc" && ok "cycle.md rejects inferring absence from a failure" || no "cycle.md rejects inferring absence from a failure"
grep -qF 'command-discipline rules below' "$cyc" && ok "cycle.md carries command discipline into every brief" || no "cycle.md carries command discipline into every brief"

grep -qF 'git -C <root>' "$impl" && ok "orbit-implementer follows command discipline" || no "orbit-implementer follows command discipline"
grep -qF 'producing no evidence' "$impl" && ok "orbit-implementer treats a denied command as no evidence" || no "orbit-implementer treats a denied command as no evidence"

grep -qF 'claude plugin marketplace update orbit' "$readme" && ok "README documents the shell marketplace update" || no "README documents the shell marketplace update"
grep -qF 'claude plugin update orbit@orbit' "$readme" && ok "README documents the shell plugin update" || no "README documents the shell plugin update"
grep -qF '/reload-plugins' "$readme" && ok "README documents /reload-plugins for in-session apply" || no "README documents /reload-plugins for in-session apply"
grep -qF 'only an alternative, not a requirement' "$readme" && ok "README marks a restart as optional" || no "README marks a restart as optional"
if grep -qF '/plugin update orbit@orbit' "$readme"; then no "README drops the in-session /plugin update form"; else ok "README drops the in-session /plugin update form"; fi
if grep -qF 'restart Claude Code to apply' "$readme"; then no "README drops the restart-to-apply requirement"; else ok "README drops the restart-to-apply requirement"; fi

cfg_helper="$root_dir/claude/bin/orbit-config.sh"
bundled_default="$root_dir/claude/config/config.default.json"

[ -f "$cfg_helper" ] && ok "config helper exists" || no "config helper exists"
sh -n "$cfg_helper" && ok "config helper passes sh -n" || no "config helper passes sh -n"

cfg1="$work/cfg1"
ORBIT_HOME="$cfg1" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
if [ -f "$cfg1/config.json" ] && cmp -s "$bundled_default" "$cfg1/config.json"; then ok "config first run creates a byte-for-byte copy of bundled defaults"; else no "config first run creates a byte-for-byte copy of bundled defaults"; fi

cfgiso="$work/cfgiso"; fakehome="$work/fakehome"; mkdir -p "$fakehome"
HOME="$fakehome" ORBIT_HOME="$cfgiso" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
if [ -f "$cfgiso/config.json" ] && [ ! -e "$fakehome/.orbit/config.json" ]; then ok "config helper writes under ORBIT_HOME and never under HOME/.orbit"; else no "config helper writes under ORBIT_HOME and never under HOME/.orbit"; fi

cp "$cfg1/config.json" "$work/cfg1.save"
ORBIT_HOME="$cfg1" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
cmp -s "$cfg1/config.json" "$work/cfg1.save" && ok "config re-run with nothing missing is a byte-for-byte no-op" || no "config re-run with nothing missing is a byte-for-byte no-op"

cfg2="$work/cfg2"; mkdir -p "$cfg2"
bun2="$work/bundled2.json"
printf '%s\n' '{"graphify":{"enabled":true,"newkey":"x"},"coverage":{"requireNewCode":false},"roles":{"exploration":"haiku","implementation":"sonnet"},"added":{"deep":{"leaf":1}}}' > "$bun2"
printf '%s\n' '{"graphify":{"enabled":false},"roles":{"implementation":"opus"},"user":{"keepNull":null,"keepFalse":false,"keepEmpty":"","keepArr":[1,2]}}' > "$cfg2/config.json"
ORBIT_HOME="$cfg2" sh "$cfg_helper" "$bun2" >/dev/null 2>&1
merged_ok="$(python3 - "$cfg2/config.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
good = (
    d["graphify"]["enabled"] is False and
    d["graphify"]["newkey"] == "x" and
    d["coverage"]["requireNewCode"] is False and
    d["roles"]["implementation"] == "opus" and
    d["roles"]["exploration"] == "haiku" and
    d["added"]["deep"]["leaf"] == 1 and
    d["user"]["keepNull"] is None and
    d["user"]["keepFalse"] is False and
    d["user"]["keepEmpty"] == "" and
    d["user"]["keepArr"] == [1, 2]
)
print("yes" if good else "no")
PY
)"
[ "$merged_ok" = "yes" ] && ok "config merge adds missing keys and preserves customized/falsy/null/array values" || no "config merge adds missing keys and preserves customized/falsy/null/array values"
strict_json="$(python3 - "$cfg2/config.json" <<'PY' 2>&1
import json, sys
def reject(token):
    raise ValueError(token)
json.loads(open(sys.argv[1], encoding="utf-8").read(), parse_constant=reject)
print("ok")
PY
)"
[ "$strict_json" = "ok" ] && ok "merged config is strict, standard JSON" || no "merged config is strict, standard JSON"

cfg7="$work/cfg7"
bad_bundled="$work/bad_bundled.json"; printf '%s\n' '{"value": NaN}' > "$bad_bundled"
ORBIT_HOME="$cfg7" sh "$cfg_helper" "$bad_bundled" >/dev/null 2>&1; rc7=$?
[ "$rc7" -ne 0 ] && ok "invalid bundled JSON (NaN) returns nonzero" || no "invalid bundled JSON (NaN) returns nonzero"
[ ! -e "$cfg7/config.json" ] && ok "invalid bundled JSON creates no target" || no "invalid bundled JSON creates no target"

cfg8="$work/cfg8"; mkdir -p "$cfg8"; printf '%s\n' '{"value": Infinity}' > "$cfg8/config.json"; cp "$cfg8/config.json" "$work/cfg8.save"
ORBIT_HOME="$cfg8" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
cmp -s "$cfg8/config.json" "$work/cfg8.save" && ok "invalid existing JSON (Infinity) stays byte-for-byte unchanged" || no "invalid existing JSON (Infinity) stays byte-for-byte unchanged"

cfg3="$work/cfg3"; mkdir -p "$cfg3"; printf 'not json {{{\n' > "$cfg3/config.json"
cp "$cfg3/config.json" "$work/cfg3.save"
ORBIT_HOME="$cfg3" sh "$cfg_helper" "$bundled_default" 2>"$work/cfg3.err" >/dev/null
cmp -s "$cfg3/config.json" "$work/cfg3.save" && ok "malformed global config is preserved byte-for-byte" || no "malformed global config is preserved byte-for-byte"
grep -qi 'malformed' "$work/cfg3.err" && ok "malformed global config emits a warning" || no "malformed global config emits a warning"

fb="$work/fakebin"; mkdir -p "$fb"
for t in sh mkdir cp mv rm mktemp; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$fb/$t"; done
cfg4="$work/cfg4"; mkdir -p "$cfg4"; printf '{"a":9}\n' > "$cfg4/config.json"; cp "$cfg4/config.json" "$work/cfg4.save"
PATH="$fb" ORBIT_HOME="$cfg4" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
cmp -s "$cfg4/config.json" "$work/cfg4.save" && ok "no-parser preserves an existing config without merging" || no "no-parser preserves an existing config without merging"
cfg5="$work/cfg5"
PATH="$fb" ORBIT_HOME="$cfg5" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1
if [ -f "$cfg5/config.json" ] && cmp -s "$bundled_default" "$cfg5/config.json"; then ok "no-parser copies bundled defaults on first run"; else no "no-parser copies bundled defaults on first run"; fi

fbfail="$work/fakebin_mktempfail"; mkdir -p "$fbfail"
for t in sh mkdir cp mv rm; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$fbfail/$t"; done
printf '#!/bin/sh\nexit 1\n' > "$fbfail/mktemp"; chmod +x "$fbfail/mktemp"
cfg9="$work/cfg9"
PATH="$fbfail" ORBIT_HOME="$cfg9" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1; rc9=$?
[ "$rc9" -ne 0 ] && ok "no-parser with failing mktemp returns nonzero" || no "no-parser with failing mktemp returns nonzero"
[ ! -e "$cfg9/config.json" ] && ok "no-parser with failing mktemp creates no target" || no "no-parser with failing mktemp creates no target"

cfg6="$work/cfg6"; mkdir -p "$cfg6"; printf '{"a":1}\n' > "$cfg6/config.json"; cp "$cfg6/config.json" "$work/cfg6.save"
chmod 555 "$cfg6" 2>/dev/null
if ( : > "$cfg6/.wprobe" ) 2>/dev/null; then
  rm -f "$cfg6/.wprobe" 2>/dev/null
  chmod 755 "$cfg6" 2>/dev/null
  ok "write-failure check skipped: this user/filesystem can write a mode-555 dir, so permission-based failure is environment-dependent"
else
  ORBIT_HOME="$cfg6" sh "$cfg_helper" "$bundled_default" >/dev/null 2>&1; rc6=$?
  chmod 755 "$cfg6" 2>/dev/null
  [ "$rc6" -ne 0 ] && ok "config write failure before rename returns nonzero" || no "config write failure before rename returns nonzero"
  cmp -s "$cfg6/config.json" "$work/cfg6.save" && ok "config write failure preserves the original byte-for-byte" || no "config write failure preserves the original byte-for-byte"
  leftover6="$(find "$cfg6" -maxdepth 1 -name '.config.*' 2>/dev/null)"
  [ -z "$leftover6" ] && ok "config write failure leaves no temp file behind" || no "config write failure leaves no temp file behind"
fi

guard="$root_dir/claude/bin/orbit-guard.sh"
hooks_json="$root_dir/claude/hooks/hooks.json"

[ -f "$guard" ] && ok "guard helper exists" || no "guard helper exists"
[ -x "$guard" ] && ok "guard helper is executable" || no "guard helper is executable"
sh -n "$guard" && ok "guard helper passes sh -n" || no "guard helper passes sh -n"

if grep -in -e 'allow' -e 'updatedPermissions' -e 'approve' "$guard" >/dev/null 2>&1; then
  no "guard source never mentions allow, updatedPermissions, or approve"
else
  ok "guard source never mentions allow, updatedPermissions, or approve"
fi

run_guard() { printf '%s' "$3" | CLAUDE_PLUGIN_DATA="$1" sh "$guard" "$2"; }
marker_present() { [ -f "$1/sessions/$2" ]; }

deny_ok() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
    o = d["hookSpecificOutput"]
    blob = json.dumps(d).lower()
    good = (
        o["hookEventName"] == "PermissionRequest"
        and o["decision"]["behavior"] == "deny"
        and o["decision"]["interrupt"] is False
        and bool(o["decision"].get("message"))
        and "allow" not in blob
        and "updatedpermissions" not in blob
    )
    print("yes" if good else "no")
except Exception:
    print("no")
PY
}
ask_deny_ok() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
    o = d["hookSpecificOutput"]
    good = (
        o["hookEventName"] == "PreToolUse"
        and o["permissionDecision"] == "deny"
        and bool(o.get("permissionDecisionReason"))
        and "allow" not in json.dumps(d).lower()
    )
    print("yes" if good else "no")
except Exception:
    print("no")
PY
}
retry_ok() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
    o = d["hookSpecificOutput"]
    good = o["hookEventName"] == "PermissionDenied" and o["retry"] is True and "allow" not in json.dumps(d).lower()
    print("yes" if good else "no")
except Exception:
    print("no")
PY
}

gA="$work/guardA"; mkdir -p "$gA"
run_guard "$gA" user-prompt-expansion '{"session_id":"sA","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"orbit:cycle","command_args":"fix it","prompt":"/orbit:cycle fix it"}' >/dev/null 2>&1
marker_present "$gA" sA && ok "direct /orbit:cycle activates the guard" || no "direct /orbit:cycle activates the guard"

gL="$work/guardL"; mkdir -p "$gL"
run_guard "$gL" user-prompt-expansion '{"session_id":"sL","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"loop","command_args":"/orbit:cycle 42","prompt":"/loop /orbit:cycle 42"}' >/dev/null 2>&1
marker_present "$gL" sL && ok "/loop /orbit:cycle activates the guard" || no "/loop /orbit:cycle activates the guard"

gN="$work/guardN"; mkdir -p "$gN"
run_guard "$gN" user-prompt-expansion '{"session_id":"sN1","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"commit","command_args":"talk about orbit:cycle here","prompt":"/commit"}' >/dev/null 2>&1
marker_present "$gN" sN1 && no "unrelated slash command does not activate" || ok "unrelated slash command does not activate"
run_guard "$gN" user-prompt-expansion '{"session_id":"sN2","hook_event_name":"UserPromptExpansion","expansion_type":"mcp_prompt","command_name":"orbit:cycle","command_args":"x","prompt":"x"}' >/dev/null 2>&1
marker_present "$gN" sN2 && no "mcp_prompt named orbit:cycle does not activate" || ok "mcp_prompt named orbit:cycle does not activate"

out_inactive="$(run_guard "$gN" permission-request '{"session_id":"sN3","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' 2>/dev/null)"
[ -z "$out_inactive" ] && ok "inactive PermissionRequest emits no decision" || no "inactive PermissionRequest emits no decision"

out_deny="$(run_guard "$gA" permission-request '{"session_id":"sA","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"grep -r x ."}}' 2>/dev/null)"
[ "$(deny_ok "$out_deny")" = yes ] && ok "active PermissionRequest returns deny with interrupt false and no allow" || no "active PermissionRequest returns deny with interrupt false and no allow"

out_sub="$(run_guard "$gA" permission-request '{"session_id":"sA","agent_id":"agent-7","agent_type":"orbit-explorer","hook_event_name":"PermissionRequest","tool_name":"Grep","tool_input":{}}' 2>/dev/null)"
[ "$(deny_ok "$out_sub")" = yes ] && ok "active subagent PermissionRequest is denied using the same session state" || no "active subagent PermissionRequest is denied using the same session state"

out_other="$(run_guard "$gA" permission-request '{"session_id":"sOther","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' 2>/dev/null)"
[ -z "$out_other" ] && ok "a different session is unaffected by an active session marker" || no "a different session is unaffected by an active session marker"

out_ask="$(run_guard "$gA" pre-tool-use '{"session_id":"sA","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{},"tool_use_id":"t1"}' 2>/dev/null)"
[ "$(ask_deny_ok "$out_ask")" = yes ] && ok "active AskUserQuestion is denied via PreToolUse" || no "active AskUserQuestion is denied via PreToolUse"
out_ask_other="$(run_guard "$gA" pre-tool-use '{"session_id":"sA","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{},"tool_use_id":"t2"}' 2>/dev/null)"
[ -z "$out_ask_other" ] && ok "active PreToolUse leaves non-AskUserQuestion tools untouched" || no "active PreToolUse leaves non-AskUserQuestion tools untouched"
out_ask_inactive="$(run_guard "$gN" pre-tool-use '{"session_id":"sN4","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{},"tool_use_id":"t3"}' 2>/dev/null)"
[ -z "$out_ask_inactive" ] && ok "inactive AskUserQuestion is left untouched" || no "inactive AskUserQuestion is left untouched"

out_retry="$(run_guard "$gA" permission-denied '{"session_id":"sA","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{},"tool_use_id":"t4","reason":"denied"}' 2>/dev/null)"
[ "$(retry_ok "$out_retry")" = yes ] && ok "active PermissionDenied returns retry true" || no "active PermissionDenied returns retry true"
out_retry_inactive="$(run_guard "$gN" permission-denied '{"session_id":"sN5","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{},"tool_use_id":"t5","reason":"x"}' 2>/dev/null)"
[ -z "$out_retry_inactive" ] && ok "inactive PermissionDenied emits no decision" || no "inactive PermissionDenied emits no decision"

gB="$work/guardBlocked"; mkdir -p "$gB"
run_guard "$gB" user-prompt-expansion '{"session_id":"sB","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"orbit:cycle","command_args":"x","prompt":"/orbit:cycle x"}' >/dev/null 2>&1
run_guard "$gB" stop '{"session_id":"sB","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Blocked: need database credentials"}' >/dev/null 2>&1
marker_present "$gB" sB && ok "Blocked: keeps the guard active" || no "Blocked: keeps the guard active"
run_guard "$gB" stop '{"session_id":"sB","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done."}' >/dev/null 2>&1
marker_present "$gB" sB && no "Done. clears the guard activation" || ok "Done. clears the guard activation"
out_after_done="$(run_guard "$gB" permission-request '{"session_id":"sB","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' 2>/dev/null)"
[ -z "$out_after_done" ] && ok "a cleared session returns to normal permission behavior" || no "a cleared session returns to normal permission behavior"

gE="$work/guardEnd"; mkdir -p "$gE"
run_guard "$gE" user-prompt-expansion '{"session_id":"sE","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"orbit:cycle","command_args":"x","prompt":"/orbit:cycle x"}' >/dev/null 2>&1
run_guard "$gE" session-end '{"session_id":"sE","hook_event_name":"SessionEnd","reason":"clear"}' >/dev/null 2>&1
marker_present "$gE" sE && no "SessionEnd clears the guard activation" || ok "SessionEnd clears the guard activation"

gH="$work/guardHostile"; mkdir -p "$gH"
out_bad="$(run_guard "$gH" user-prompt-expansion '{"session_id":"../../evil","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"orbit:cycle","command_args":"x","prompt":"x"}' 2>/dev/null)"
escaped="$(find "$work" -name evil 2>/dev/null)"
if [ -z "$out_bad" ] && [ -z "$escaped" ] && [ ! -d "$gH/sessions" ]; then ok "a traversal session id creates no state and emits no decision"; else no "a traversal session id creates no state and emits no decision"; fi
out_slash="$(run_guard "$gH" permission-request '{"session_id":"a/b","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' 2>/dev/null)"
[ -z "$out_slash" ] && ok "a session id with a slash never approves" || no "a session id with a slash never approves"
out_empty="$(run_guard "$gH" permission-request '{"session_id":"","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' 2>/dev/null)"
[ -z "$out_empty" ] && ok "an empty session id never approves" || no "an empty session id never approves"

gM="$work/guardMalformed"; mkdir -p "$gM"
out_malf="$(run_guard "$gM" permission-request 'not json {{{' 2>/dev/null; echo "rc=$?")"
case "$out_malf" in rc=0) ok "malformed hook JSON is ignored and exits zero" ;; *) no "malformed hook JSON is ignored and exits zero" ;; esac
out_malf2="$(run_guard "$gM" permission-request 'not json {{{' 2>/dev/null)"
[ -z "$out_malf2" ] && ok "malformed hook JSON emits no decision" || no "malformed hook JSON emits no decision"
out_nan="$(run_guard "$gA" permission-request '{"session_id":"sA","value":NaN}' 2>/dev/null)"
[ -z "$out_nan" ] && ok "non-standard JSON constants never approve even for an active session" || no "non-standard JSON constants never approve even for an active session"

out_nodata="$(printf '%s' '{"session_id":"sX","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}' | env -u CLAUDE_PLUGIN_DATA sh "$guard" permission-request 2>/dev/null)"
out_nodata_rc="$(printf '%s' '{"session_id":"sX"}' | env -u CLAUDE_PLUGIN_DATA sh "$guard" permission-request >/dev/null 2>&1; echo "$?")"
if [ -z "$out_nodata" ] && [ "$out_nodata_rc" = 0 ]; then ok "guard without plugin data dir exits zero with no decision"; else no "guard without plugin data dir exits zero with no decision"; fi

[ -f "$hooks_json" ] && ok "plugin hooks.json exists at the auto-discovered path" || no "plugin hooks.json exists at the auto-discovered path"
hooks_ok="$(python3 - "$hooks_json" "$guard" <<'PY'
import json, os, sys
def reject(t): raise ValueError(t)
try:
    d = json.loads(open(sys.argv[1], encoding="utf-8").read(), parse_constant=reject)
except Exception:
    print("no"); sys.exit(0)
guard = sys.argv[2]
events = set(d.get("hooks", {}).keys())
need = {"UserPromptExpansion", "PermissionRequest", "PreToolUse", "PermissionDenied", "Stop", "SessionEnd"}
ok = need.issubset(events)
for ev, entries in d.get("hooks", {}).items():
    for entry in entries:
        for h in entry.get("hooks", []):
            if h.get("type") != "command":
                ok = False
            if "${CLAUDE_PLUGIN_ROOT}/bin/orbit-guard.sh" not in h.get("command", ""):
                ok = False
pre = d["hooks"]["PreToolUse"][0].get("matcher")
if pre != "AskUserQuestion":
    ok = False
if not (os.path.isfile(guard) and os.access(guard, os.X_OK)):
    ok = False
print("yes" if ok else "no")
PY
)"
[ "$hooks_ok" = yes ] && ok "hooks.json parses, covers each event, and references only the shipped executable guard" || no "hooks.json parses, covers each event, and references only the shipped executable guard"

noop_guard="$work/noop_guard.sh"; printf '#!/bin/sh\nexit 0\n' > "$noop_guard"; chmod +x "$noop_guard"
always_deny="$work/always_deny.sh"
printf '%s\n' '#!/bin/sh' 'printf %s "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"interrupt\":false}}}"' > "$always_deny"
chmod +x "$always_deny"

nc="$work/nc"; mkdir -p "$nc/sessions"; : > "$nc/sessions/ncS"
nc_out="$(printf '%s' '{"session_id":"ncS","tool_name":"Bash","tool_input":{}}' | CLAUDE_PLUGIN_DATA="$nc" sh "$noop_guard" permission-request 2>/dev/null)"
if [ "$(deny_ok "$nc_out")" = yes ]; then no "negative control: a guard that never denies is caught by the deny assertion"; else ok "negative control: a guard that never denies is caught by the deny assertion"; fi

nc2="$work/nc2"; mkdir -p "$nc2/sessions"
nc2_out="$(printf '%s' '{"session_id":"inactiveS","tool_name":"Bash","tool_input":{}}' | CLAUDE_PLUGIN_DATA="$nc2" sh "$always_deny" permission-request 2>/dev/null)"
if [ -n "$nc2_out" ]; then ok "negative control: a guard without session isolation is caught by the isolation assertion"; else no "negative control: a guard without session isolation is caught by the isolation assertion"; fi

nc3="$work/nc3"; mkdir -p "$nc3/sessions"; : > "$nc3/sessions/doneS"
printf '%s' '{"session_id":"doneS","last_assistant_message":"Done."}' | CLAUDE_PLUGIN_DATA="$nc3" sh "$noop_guard" stop >/dev/null 2>&1
if [ -f "$nc3/sessions/doneS" ]; then ok "negative control: a guard that never clears on Done. is caught by the cleanup assertion"; else no "negative control: a guard that never clears on Done. is caught by the cleanup assertion"; fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
