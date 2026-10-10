#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eeuo pipefail

trap exit SIGINT SIGTERM

################################################################################
# Local developer toolchain check. No sign-in or cloud operations.
__usage="
    -x  check-deps  Check installed developer tools (default).
    -h             Show help.
"

usage() {
  printf 'usage: %s [options]\n%s\n' "${0##*/}" "$__usage"
}

print_header() {
  printf '\nDeveloper toolchain\n==========================================\n'
}

log() {
  printf '[%s] %s\n' "$(date +"%r")" "$*"
}

do_check_deps() {
  local tool
  for tool in bash az bicep dotnet copilot git gh node npm python3 jq rg curl ssh sshd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log "Required tool is missing: $tool" >&2
      return 1
    fi
  done
  az version || return $?
  bicep --version || return $?
  dotnet --version || return $?
  copilot --version || return $?
  git --version || return $?
  gh --version || return $?
  node --version || return $?
  npm --version || return $?
  python3 --version || return $?
  python3 -m venv --help >/dev/null || return $?
  jq --version || return $?
  rg --version || return $?
  log "Toolchain ready. No sign-in or deployment. Start with ./run.sh -h."
}

exec_case() {
  case "$1" in
    check-deps) do_check_deps ;;
    *) usage >&2; return 1 ;;
  esac
}

main() {
  local opt action=check-deps
  while getopts ':hx:' opt; do
    case "$opt" in
      h) usage; return 0 ;;
      x) action=$OPTARG ;;
      *) usage >&2; return 1 ;;
    esac
  done
  shift "$((OPTIND - 1))"
  [[ $# = 0 ]] || { usage >&2; return 1; }
  print_header || return $?
  exec_case "$action" || return $?
}

main "$@" || exit $?
exit 0
