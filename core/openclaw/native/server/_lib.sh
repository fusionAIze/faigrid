#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

is_linux(){
  [[ "$(uname -s)" == "Linux" ]]
}

require_root(){
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (sudo)."
}

detect_pm(){
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  die "unsupported distro (expected Debian/Ubuntu with apt-get)."
}

ensure_user_group(){
  local user="$1" group="$2" home="$3"
  need id
  need useradd
  need groupadd

  if ! getent group "${group}" >/dev/null 2>&1; then
    groupadd --system "${group}"
  fi
  if ! id -u "${user}" >/dev/null 2>&1; then
    useradd --system --gid "${group}" --home-dir "${home}" --create-home --shell /usr/sbin/nologin "${user}"
  fi
  install -d -m 0750 -o "${user}" -g "${group}" "${home}"
}

random_token(){
  need openssl
  openssl rand -hex 16
}

write_file_root_openclaw_0640(){
  local path="$1"
  install -d -m 0750 -o root -g openclaw "$(dirname "${path}")"
  install -m 0640 -o root -g openclaw /dev/null "${path}"
}
