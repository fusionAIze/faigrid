#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - grid-worker environment library (reusable)
# ==============================================================================
# Sourced, never executed. This library holds the machine-independent parts of a
# grid-worker inference setup so that the next worker does not have to be
# discovered again:
#
#   * resolve an engine binary to an ABSOLUTE path even when the calling session
#     has a minimal, non-interactive PATH (the absolute-path trap);
#   * read the inference api-key from an env file and FAIL CLOSED when the file
#     is missing, unreadable, the variable is absent or the value is empty;
#   * build the llama.cpp server command line with the key exported as an
#     environment variable and never as an argv flag, optionally wrapped in
#     caffeinate, and fail closed when a required input is unset;
#   * probe the HTTP inference endpoint rather than a CLI presence check;
#   * a pidfile-based liveness helper for a service that must outlive a session.
#
# Nothing in this file names a host, an address, a user, a model file, a key
# value or a machine hostname. Every host-specific input arrives through a
# WORKER_* environment variable, so the same code is correct on any worker.
#
# Bash 3.2 compatible (macOS): no associative arrays, no mapfile, no indirect
# ${!var}. Usage:
#   source worker/lib/worker-env.sh
# ==============================================================================

# --- Logging ------------------------------------------------------------------
worker_log()  { printf '[grid-worker] %s\n' "$*"; }
worker_warn() { printf '[grid-worker] WARN: %s\n' "$*" >&2; }
worker_err()  { printf '[grid-worker] ERROR: %s\n' "$*" >&2; }

# --- Engine resolution (the absolute-path requirement) ------------------------
# A non-interactive session (sshd forced command, launchd, cron) loads no login
# profile, so Homebrew's /opt/homebrew/bin and a user's ~/.local/bin are absent
# from PATH. Relying on `command` alone finds the engine interactively and fails
# on the forced-command path - the trap that was hit twice on this round.
#
# Resolution order:
#   1. WORKER_LLAMA_SERVER_BIN (explicit override for the llama.cpp engine)
#   2. PATH                    (when the session does load a profile)
#   3. WORKER_BIN_DIRS         (well-known absolute directories)
# Prints the absolute path on success, nothing and non-zero when not found.
worker_resolve_bin() {
  local name="$1" override candidate dirs old_ifs found
  [ -n "$name" ] || { worker_err "worker_resolve_bin: no binary name given"; return 1; }

  override=""
  case "$name" in
    llama-server) override="${WORKER_LLAMA_SERVER_BIN:-}" ;;
  esac

  if [ -n "$override" ] && [ -x "$override" ]; then
    printf '%s\n' "$override"
    return 0
  fi

  found="$(command -v "$name" 2>/dev/null || true)"
  case "$found" in
    /*) printf '%s\n' "$found"; return 0 ;;
  esac

  dirs="${WORKER_BIN_DIRS:-/opt/homebrew/bin:/usr/local/bin:${HOME:-/nonexistent}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
  old_ifs="$IFS"; IFS=:
  for candidate in $dirs; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate/$name" ]; then
      IFS="$old_ifs"
      printf '%s\n' "$candidate/$name"
      return 0
    fi
  done
  IFS="$old_ifs"

  return 1
}

# The llama.cpp engine is a generic worker engine (GO-010 made it first-class in
# the installer). Resolve its server binary the same way for every worker.
worker_llama_server_bin() {
  worker_resolve_bin llama-server
}

# --- api-key source (fail-closed read) ----------------------------------------
# The api-key is read from a key=value env file whose path is supplied by the
# caller. The code has NO default path: where the file lives and who may read it
# is machine-specific (here an envctl cluster file on a 600 file), so it must
# arrive as configuration. What is generic is the read and its failure mode.
worker_api_key_file() { printf '%s\n' "${WORKER_API_KEY_FILE:-}"; }
worker_api_key_var()  { printf '%s\n' "${WORKER_API_KEY_VAR:-LLAMA_API_KEY}"; }

# Read $WORKER_API_KEY_VAR from $WORKER_API_KEY_FILE, export it under that name
# and return 0. FAILS CLOSED - returns non-zero without exporting anything - when:
#   * WORKER_API_KEY_FILE is empty,
#   * the file does not exist or is not readable,
#   * the variable is absent or its value is empty.
# The key value is never printed. The caller must treat non-zero as "do not
# start"; see worker_start_llama_server.
worker_read_api_key() {
  local file var line key value found
  file="$(worker_api_key_file)"
  var="$(worker_api_key_var)"

  if [ -z "$file" ]; then
    worker_err "api-key file path is empty; set WORKER_API_KEY_FILE"
    return 1
  fi
  if [ ! -f "$file" ]; then
    worker_err "api-key file not found: ${file}; set WORKER_API_KEY_FILE"
    return 1
  fi
  if [ ! -r "$file" ]; then
    worker_err "api-key file is not readable: ${file}"
    return 1
  fi

  found=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    line="${line#export }"
    key="${line%%=*}"
    # Trim trailing whitespace from the key.
    key="${key%"${key##*[![:space:]]}"}"
    if [ "$key" = "$var" ]; then
      value="${line#*=}"
      value="${value%$'\r'}"
      case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
      esac
      found="$value"
      break
    fi
  done < "$file"

  if [ -z "$found" ]; then
    worker_err "api-key '${var}' is missing or empty in ${file} - refusing to start"
    return 1
  fi

  export "$var=$found"
  return 0
}

# --- caffeinate (generic on macOS) --------------------------------------------
# A laptop that sleeps drops the endpoint; caffeinate -dimsu holds it awake for
# as long as the wrapped process runs. auto => enabled only on Darwin when the
# binary is present, so the same code is inert on a Linux worker.
worker_caffeinate_enabled() {
  case "${WORKER_CAFFEINATE:-auto}" in
    1|yes|true|on)  return 0 ;;
    0|no|false|off) return 1 ;;
  esac
  [ "$(uname -s)" = "Darwin" ] && command -v caffeinate >/dev/null 2>&1
}

worker_caffeinate_prefix() {
  if worker_caffeinate_enabled; then
    printf 'caffeinate -dimsu'
  fi
}

# --- llama.cpp server command -------------------------------------------------
worker_model_path() { printf '%s\n' "${WORKER_MODEL_PATH:-}"; }

# Build the llama.cpp server argv. The key is NOT part of it: llama-server reads
# LLAMA_API_KEY from the environment, while an --api-key flag would be visible
# to any local user through `ps`. Fails closed when the engine or model is unset.
worker_print_llama_command() {
  local bin model prefix parts
  bin="$(worker_llama_server_bin)" || {
    worker_err "llama-server not found on PATH or in WORKER_BIN_DIRS"
    return 1
  }
  model="$(worker_model_path)"
  if [ -z "$model" ]; then
    worker_err "WORKER_MODEL_PATH is not set - refusing to build the command"
    return 1
  fi

  prefix="$(worker_caffeinate_prefix)"
  parts="$bin --host ${WORKER_BIND_ADDR:-0.0.0.0} --port ${WORKER_PORT:-8080} --model $model --ctx-size ${WORKER_CTX_SIZE:-4096} --parallel ${WORKER_PARALLEL:-1} -ngl ${WORKER_NGL:-99}"
  if [ -n "$prefix" ]; then
    printf '%s %s\n' "$prefix" "$parts"
  else
    printf '%s\n' "$parts"
  fi
}

# Start the server, failing closed BEFORE anything binds: no key, no server.
# exec replaces the calling shell, which is what a start script wants.
worker_start_llama_server() {
  local bin model
  worker_read_api_key || {
    worker_err "refusing to start the inference server without an api-key"
    return 1
  }
  bin="$(worker_llama_server_bin)" || {
    worker_err "llama-server not found on PATH or in WORKER_BIN_DIRS"
    return 1
  }
  model="$(worker_model_path)"
  if [ -z "$model" ]; then
    worker_err "WORKER_MODEL_PATH is not set - refusing to start"
    return 1
  fi

  if worker_caffeinate_enabled; then
    exec caffeinate -dimsu "$bin" \
      --host "${WORKER_BIND_ADDR:-0.0.0.0}" --port "${WORKER_PORT:-8080}" \
      --model "$model" --ctx-size "${WORKER_CTX_SIZE:-4096}" \
      --parallel "${WORKER_PARALLEL:-1}" -ngl "${WORKER_NGL:-99}"
  else
    exec "$bin" \
      --host "${WORKER_BIND_ADDR:-0.0.0.0}" --port "${WORKER_PORT:-8080}" \
      --model "$model" --ctx-size "${WORKER_CTX_SIZE:-4096}" \
      --parallel "${WORKER_PARALLEL:-1}" -ngl "${WORKER_NGL:-99}"
  fi
}

# --- health check (HTTP, not CLI presence) ------------------------------------
# verify.sh used to check only `ollama list`/`lms status`. A CLI can be present
# and the endpoint dead, which is the failure this probe catches.
worker_health_url() {
  printf '%s\n' "${WORKER_HEALTH_URL:-http://127.0.0.1:${WORKER_PORT:-8080}/v1/models}"
}

# Returns 0 when the endpoint answers any 2xx, non-zero (and names the URL) when
# it does not, so a caller can fail loudly instead of reporting a CLI as "up".
worker_health_check() {
  local url
  url="$(worker_health_url)"
  if ! command -v curl >/dev/null 2>&1; then
    worker_err "curl not found - cannot probe the inference endpoint at ${url}"
    return 1
  fi
  if curl -fsS --max-time "${WORKER_HEALTH_TIMEOUT:-5}" -o /dev/null "$url" 2>/dev/null; then
    worker_log "inference endpoint answered: ${url}"
    return 0
  fi
  worker_err "inference endpoint did NOT answer: ${url}"
  return 1
}

# --- service durability (liveness building block) -----------------------------
# The durable mechanism on this worker is host-specific (an sshd forced command
# that restarts the server on every connection). What generalises is knowing
# whether the server is still alive from a pidfile.
worker_pidfile_path() {
  printf '%s\n' "${WORKER_PIDFILE:-${TMPDIR:-/tmp}/grid-worker-inference.pid}"
}

worker_service_running() {
  local pidfile pid
  pidfile="$(worker_pidfile_path)"
  [ -f "$pidfile" ] || return 1
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null
}
