#!/usr/bin/env sh
set -u

event="${1:-}"
data_dir="${CLAUDE_PLUGIN_DATA:-}"

[ -n "$event" ] || exit 0
[ -n "$data_dir" ] || exit 0

if command -v python3 >/dev/null 2>&1; then
  ORBIT_GUARD_EVENT="$event" python3 /dev/fd/3 3<<'PY'
import json, os, re, sys, tempfile

event = os.environ.get("ORBIT_GUARD_EVENT", "")
data_dir = os.environ.get("CLAUDE_PLUGIN_DATA", "")

SESSION_RE = re.compile(r"\A[A-Za-z0-9._-]{1,200}\Z")

DENY_MESSAGE = (
    "Orbit is running unattended and cannot show a permission prompt, so this request was denied and produced "
    "no evidence. Do not repeat the same command and do not infer the result it would have returned. Retry with the "
    "native Read, Glob, or Grep tool, or a statically scoped command using explicit paths or `git -C <root>`. If no "
    "authorized route exists, stop with a genuine `Blocked:` result naming the exact missing access."
)

ASK_MESSAGE = (
    "Orbit does not ask the user during a run. Decide from evidence in priority order: explicit ticket requirements, "
    "attachments and authoritative evidence already available, repository instructions, existing product and code "
    "behavior, then the smallest reversible change that satisfies the written requirement. Record the assumption on "
    "the active task and continue; reserve `Blocked:` for a genuinely unresolvable access or safety decision."
)


def reject_constant(token):
    raise ValueError("non-standard JSON constant")


def load_strict(text):
    return json.loads(text, parse_constant=reject_constant)


def valid_session(value):
    if not isinstance(value, str) or value in (".", ".."):
        return False
    return bool(SESSION_RE.match(value))


def sessions_dir():
    return os.path.join(data_dir, "sessions")


def marker_path(session_id):
    return os.path.join(sessions_dir(), session_id)


def is_active(session_id):
    try:
        return os.path.isfile(marker_path(session_id))
    except Exception:
        return False


def activate(session_id):
    try:
        directory = sessions_dir()
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".marker.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(json.dumps({"session_id": session_id, "active": True}) + "\n")
            os.replace(tmp, marker_path(session_id))
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    except Exception:
        pass


def deactivate(session_id):
    try:
        os.remove(marker_path(session_id))
    except Exception:
        pass


def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj))
    except Exception:
        pass


def triggers(command_name, command_args):
    if not isinstance(command_name, str):
        return False
    name = command_name.lstrip("/")
    if name == "orbit:cycle":
        return True
    if name == "loop" and isinstance(command_args, str):
        parts = command_args.strip().split()
        if parts and parts[0].lstrip("/") == "orbit:cycle":
            return True
    return False


def main():
    payload = load_strict(sys.stdin.read())
    if not isinstance(payload, dict):
        return
    session_id = payload.get("session_id")
    if not valid_session(session_id):
        return

    if event == "user-prompt-expansion":
        if payload.get("expansion_type") == "slash_command" and triggers(
            payload.get("command_name"), payload.get("command_args")
        ):
            activate(session_id)
        return

    if event == "permission-request":
        if is_active(session_id):
            emit(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": DENY_MESSAGE,
                            "interrupt": False,
                        },
                    }
                }
            )
        return

    if event == "pre-tool-use":
        if payload.get("tool_name") == "AskUserQuestion" and is_active(session_id):
            emit(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": ASK_MESSAGE,
                    }
                }
            )
        return

    if event == "permission-denied":
        if is_active(session_id):
            emit({"hookSpecificOutput": {"hookEventName": "PermissionDenied", "retry": True}})
        return

    if event == "stop":
        if is_active(session_id):
            message = payload.get("last_assistant_message")
            if isinstance(message, str) and message.strip() == "Done.":
                deactivate(session_id)
        return

    if event == "session-end":
        deactivate(session_id)
        return


try:
    main()
except Exception:
    pass
PY
elif command -v node >/dev/null 2>&1; then
  ORBIT_GUARD_EVENT="$event" node /dev/fd/3 3<<'JS'
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const event = process.env.ORBIT_GUARD_EVENT || "";
const dataDir = process.env.CLAUDE_PLUGIN_DATA || "";

const SESSION_RE = /^[A-Za-z0-9._-]{1,200}$/;

const DENY_MESSAGE =
  "Orbit is running unattended and cannot show a permission prompt, so this request was denied and produced " +
  "no evidence. Do not repeat the same command and do not infer the result it would have returned. Retry with the " +
  "native Read, Glob, or Grep tool, or a statically scoped command using explicit paths or `git -C <root>`. If no " +
  "authorized route exists, stop with a genuine `Blocked:` result naming the exact missing access.";

const ASK_MESSAGE =
  "Orbit does not ask the user during a run. Decide from evidence in priority order: explicit ticket requirements, " +
  "attachments and authoritative evidence already available, repository instructions, existing product and code " +
  "behavior, then the smallest reversible change that satisfies the written requirement. Record the assumption on " +
  "the active task and continue; reserve `Blocked:` for a genuinely unresolvable access or safety decision.";

function loadStrict(text) {
  return JSON.parse(text);
}

function validSession(value) {
  if (typeof value !== "string" || value === "." || value === "..") return false;
  return SESSION_RE.test(value);
}

function sessionsDir() {
  return path.join(dataDir, "sessions");
}

function markerPath(sessionId) {
  return path.join(sessionsDir(), sessionId);
}

function isActive(sessionId) {
  try {
    return fs.statSync(markerPath(sessionId)).isFile();
  } catch (exc) {
    return false;
  }
}

function activate(sessionId) {
  try {
    const directory = sessionsDir();
    fs.mkdirSync(directory, { recursive: true });
    const tmp = path.join(directory, ".marker." + process.pid + "." + crypto.randomBytes(6).toString("hex") + ".tmp");
    try {
      fs.writeFileSync(tmp, JSON.stringify({ session_id: sessionId, active: true }) + "\n", {
        encoding: "utf8",
        mode: 0o600,
        flag: "wx",
      });
      fs.renameSync(tmp, markerPath(sessionId));
    } catch (exc) {
      try {
        fs.unlinkSync(tmp);
      } catch (ignore) {}
    }
  } catch (exc) {}
}

function deactivate(sessionId) {
  try {
    fs.unlinkSync(markerPath(sessionId));
  } catch (exc) {}
}

function emit(obj) {
  try {
    process.stdout.write(JSON.stringify(obj));
  } catch (exc) {}
}

function triggers(commandName, commandArgs) {
  if (typeof commandName !== "string") return false;
  const name = commandName.replace(/^\/+/, "");
  if (name === "orbit:cycle") return true;
  if (name === "loop" && typeof commandArgs === "string") {
    const parts = commandArgs.trim().split(/\s+/).filter(Boolean);
    if (parts.length && parts[0].replace(/^\/+/, "") === "orbit:cycle") return true;
  }
  return false;
}

function main() {
  const payload = loadStrict(fs.readFileSync(0, "utf8"));
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) return;
  const sessionId = payload.session_id;
  if (!validSession(sessionId)) return;

  if (event === "user-prompt-expansion") {
    if (payload.expansion_type === "slash_command" && triggers(payload.command_name, payload.command_args)) {
      activate(sessionId);
    }
    return;
  }

  if (event === "permission-request") {
    if (isActive(sessionId)) {
      emit({
        hookSpecificOutput: {
          hookEventName: "PermissionRequest",
          decision: { behavior: "deny", message: DENY_MESSAGE, interrupt: false },
        },
      });
    }
    return;
  }

  if (event === "pre-tool-use") {
    if (payload.tool_name === "AskUserQuestion" && isActive(sessionId)) {
      emit({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ASK_MESSAGE,
        },
      });
    }
    return;
  }

  if (event === "permission-denied") {
    if (isActive(sessionId)) {
      emit({ hookSpecificOutput: { hookEventName: "PermissionDenied", retry: true } });
    }
    return;
  }

  if (event === "stop") {
    if (isActive(sessionId)) {
      const message = payload.last_assistant_message;
      if (typeof message === "string" && message.trim() === "Done.") {
        deactivate(sessionId);
      }
    }
    return;
  }

  if (event === "session-end") {
    deactivate(sessionId);
    return;
  }
}

try {
  main();
} catch (exc) {}
JS
fi
exit 0
