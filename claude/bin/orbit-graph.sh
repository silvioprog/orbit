#!/usr/bin/env sh
set -eu

orbit_home="${ORBIT_HOME:-$HOME/.orbit}"
graphs_dir="$orbit_home/graphs"

log() { printf 'orbit-graph: %s\n' "$1" >&2; }

command -v git >/dev/null 2>&1 || { log "git not found; using normal exploration"; exit 3; }
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || { log "not inside a git worktree; using normal exploration"; exit 3; }
root="$(cd "$root" 2>/dev/null && pwd -P)" || { log "cannot resolve worktree root"; exit 3; }

graphify_on() {
  for cfg in "$root/.orbit/config.json" "$orbit_home/config.json"; do
    [ -f "$cfg" ] || continue
    val="$(tr -d '\n' < "$cfg" 2>/dev/null | sed -n 's/.*"graphify"[[:space:]]*:[[:space:]]*{[^}]*"enabled"[[:space:]]*:[[:space:]]*\([a-zA-Z]*\).*/\1/p' | head -n1)"
    [ -n "$val" ] || continue
    [ "$val" != "false" ]
    return
  done
  return 0
}
graphify_on || { log "graphify disabled by config; using normal exploration"; exit 3; }

command -v graphify >/dev/null 2>&1 || { log "graphify not installed; using normal exploration"; exit 3; }

common_dir="$(git rev-parse --git-common-dir 2>/dev/null || echo '')"
case "$common_dir" in
  /*) : ;;
  '') : ;;
  *) common_dir="$( (cd "$root" && cd "$common_dir" && pwd -P) 2>/dev/null || echo "$common_dir")" ;;
esac
root_commit="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n1 || echo '')"

id_input="$root
$common_dir
$root_commit"
if command -v shasum >/dev/null 2>&1; then
  wid="$(printf '%s' "$id_input" | shasum -a 256 | cut -c1-16)"
elif command -v sha256sum >/dev/null 2>&1; then
  wid="$(printf '%s' "$id_input" | sha256sum | cut -c1-16)"
else
  log "no sha256 tool; using normal exploration"; exit 3
fi
[ -n "$wid" ] || { log "empty worktree id; using normal exploration"; exit 3; }

gdir="$graphs_dir/$wid"
live="$gdir/graphify-out"
graph="$live/graph.json"
staging="$gdir/.staging.$$"
prev="$gdir/.prev.$$"

safe_rm() {
  case "$1" in
    "$gdir"/.staging.*|"$gdir"/.prev.*) : ;;
    *) return 0 ;;
  esac
  case "$1" in
    *..*) return 0 ;;
  esac
  rm -rf "$1"
}

valid_graph() {
  [ -s "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$1" >/dev/null 2>&1
  else
    log "no JSON parser (python3 or node) available; using normal exploration"
    return 1
  fi
}

mkdir -p "$gdir"
for d in "$gdir"/.staging.* "$gdir"/.prev.*; do
  if [ -e "$d" ]; then safe_rm "$d"; fi
done

safe_rm "$staging"
mkdir -p "$staging"
if [ -d "$live" ]; then
  cp -R "$live" "$staging/graphify-out" 2>/dev/null || { safe_rm "$staging"; log "cannot seed staging; using normal exploration"; exit 3; }
  rm -f "$staging/graphify-out/graph.json"
fi

if ( cd "$staging" && graphify extract "$root" --code-only --out "$staging" ) >"$gdir/extract.log" 2>&1 && valid_graph "$staging/graphify-out/graph.json"; then
  safe_rm "$prev"
  if [ -d "$live" ]; then
    if ! mv "$live" "$prev"; then
      safe_rm "$staging"
      log "extraction unavailable; using normal exploration (see $gdir/extract.log)"
      exit 3
    fi
  fi
  if mv "$staging/graphify-out" "$live"; then
    safe_rm "$prev"
    safe_rm "$staging"
    printf '%s\n' "$graph"
    exit 0
  fi
  if [ -d "$prev" ]; then
    mv "$prev" "$live" 2>/dev/null || true
  fi
fi

safe_rm "$staging"
log "extraction unavailable; using normal exploration (see $gdir/extract.log)"
exit 3
