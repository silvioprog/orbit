#!/usr/bin/env sh
set -u

orbit_home="${ORBIT_HOME:-$HOME/.orbit}"
bundled="${1:-}"
target="$orbit_home/config.json"

log() { printf 'orbit-config: %s\n' "$1" >&2; }

[ -n "$bundled" ] || { log "no bundled config path given"; exit 2; }
[ -f "$bundled" ] || { log "bundled config not found: $bundled"; exit 2; }
mkdir -p "$orbit_home" 2>/dev/null || { log "cannot create $orbit_home"; exit 1; }

if command -v python3 >/dev/null 2>&1; then
  ORBIT_CONFIG_BUNDLED="$bundled" ORBIT_CONFIG_TARGET="$target" python3 - <<'PY'
import json, os, sys, tempfile

bundled_path = os.environ["ORBIT_CONFIG_BUNDLED"]
target_path = os.environ["ORBIT_CONFIG_TARGET"]

def log(msg):
    sys.stderr.write("orbit-config: %s\n" % msg)

def die(msg, code):
    log(msg)
    sys.exit(code)

def reject_constant(token):
    raise ValueError("non-standard JSON constant: %s" % token)

def strict_loads(text):
    return json.loads(text, parse_constant=reject_constant)

def atomic_write(path, text):
    directory = os.path.dirname(path) or "."
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".config.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp, path)
    except Exception as exc:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        die("failed to write config: %s" % exc, 1)

try:
    with open(bundled_path, "r", encoding="utf-8") as handle:
        raw_bundled = handle.read()
    bundled = strict_loads(raw_bundled)
except Exception:
    die("bundled config is not valid JSON: %s" % bundled_path, 2)

if not isinstance(bundled, dict):
    die("bundled config is not a JSON object: %s" % bundled_path, 2)

if not os.path.exists(target_path):
    atomic_write(target_path, raw_bundled)
    sys.exit(0)

try:
    with open(target_path, "r", encoding="utf-8") as handle:
        existing = strict_loads(handle.read())
except Exception:
    die("existing global config is malformed; preserving it and skipping upgrade", 0)

if not isinstance(existing, dict):
    die("existing global config is not a JSON object; preserving it and skipping upgrade", 0)

added = {"changed": False}

def merge(dst, src):
    for key in src:
        if key not in dst:
            dst[key] = src[key]
            added["changed"] = True
        elif isinstance(dst[key], dict) and isinstance(src[key], dict):
            merge(dst[key], src[key])

merged = strict_loads(json.dumps(existing, allow_nan=False))
merge(merged, bundled)

if not added["changed"]:
    sys.exit(0)

try:
    out = json.dumps(merged, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    strict_loads(out)
except Exception:
    die("generated config failed validation; keeping existing config", 1)
atomic_write(target_path, out)
sys.exit(0)
PY
  exit $?
elif command -v node >/dev/null 2>&1; then
  ORBIT_CONFIG_BUNDLED="$bundled" ORBIT_CONFIG_TARGET="$target" node - <<'JS'
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const bundledPath = process.env.ORBIT_CONFIG_BUNDLED;
const targetPath = process.env.ORBIT_CONFIG_TARGET;

function log(msg) { process.stderr.write("orbit-config: " + msg + "\n"); }
function die(msg, code) { log(msg); process.exit(code); }
function isObject(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }

function atomicWrite(dest, text) {
  const directory = path.dirname(dest) || ".";
  const tmp = path.join(directory, ".config." + process.pid + "." + crypto.randomBytes(6).toString("hex") + ".tmp");
  try {
    fs.writeFileSync(tmp, text, { encoding: "utf8", mode: 0o600, flag: "wx" });
    fs.renameSync(tmp, dest);
  } catch (exc) {
    try { fs.unlinkSync(tmp); } catch (ignore) {}
    die("failed to write config: " + exc.message, 1);
  }
}

let rawBundled;
let bundled;
try {
  rawBundled = fs.readFileSync(bundledPath, "utf8");
  bundled = JSON.parse(rawBundled);
} catch (exc) {
  die("bundled config is not valid JSON: " + bundledPath, 2);
}
if (!isObject(bundled)) die("bundled config is not a JSON object: " + bundledPath, 2);

if (!fs.existsSync(targetPath)) {
  atomicWrite(targetPath, rawBundled);
  process.exit(0);
}

let existing;
try {
  existing = JSON.parse(fs.readFileSync(targetPath, "utf8"));
} catch (exc) {
  die("existing global config is malformed; preserving it and skipping upgrade", 0);
}
if (!isObject(existing)) die("existing global config is not a JSON object; preserving it and skipping upgrade", 0);

let changed = false;
function merge(dst, src) {
  for (const key of Object.keys(src)) {
    if (!Object.prototype.hasOwnProperty.call(dst, key)) {
      dst[key] = src[key];
      changed = true;
    } else if (isObject(dst[key]) && isObject(src[key])) {
      merge(dst[key], src[key]);
    }
  }
}

const merged = JSON.parse(JSON.stringify(existing));
merge(merged, bundled);

if (!changed) process.exit(0);

const out = JSON.stringify(merged, null, 2) + "\n";
try {
  JSON.parse(out);
} catch (exc) {
  die("generated config failed validation; keeping existing config", 1);
}
atomicWrite(targetPath, out);
process.exit(0);
JS
  exit $?
else
  if [ -f "$target" ]; then
    log "no JSON parser (python3 or node); preserving existing config and skipping upgrade"
    exit 0
  fi
  tmp="$(mktemp "$orbit_home/.config.XXXXXX" 2>/dev/null)" || { log "no JSON parser and mktemp failed; leaving config unchanged"; exit 1; }
  [ -n "$tmp" ] || { log "no JSON parser and mktemp produced no path; leaving config unchanged"; exit 1; }
  if cp "$bundled" "$tmp" 2>/dev/null && mv "$tmp" "$target" 2>/dev/null; then
    exit 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  log "no JSON parser and could not install bundled defaults"
  exit 1
fi
