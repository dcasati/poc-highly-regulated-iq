#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eeuo pipefail

trap exit SIGINT SIGTERM

################################################################################
# Local developer toolchain check. No sign-in or cloud operations.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
__usage="
    -x  check-deps  Check deployment tools (default).
        check-app   Also check application and diagram authoring tools.
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

check_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log "Required tool is missing: $tool" >&2
      return 1
    fi
  done
}

do_check_deps() {
  local bicep_dir="${AZURE_CONFIG_DIR:-${HOME}/.azure}/bin"
  if ! command -v bicep >/dev/null 2>&1 && [[ -x "$bicep_dir/bicep" ]]; then
    export PATH="$bicep_dir:$PATH"
  fi
  check_tools bash az bicep jq || return $?
  az version --output none || return $?
  bicep --version || return $?
  jq --version || return $?
  log "Deployment tools ready. No sign-in or deployment."
}

do_check_app() {
  do_check_deps || return $?
  check_tools dotnet python3 git || return $?
  dotnet --version || return $?
  git --version || return $?
  python3 --version || return $?
  python3 -m venv --help >/dev/null || return $?
  python3 -c 'import runpy, sys; runpy.run_path(sys.argv[1])["measured_font"](22)' \
    "$SCRIPT_DIR/../docs/diagrams/generate-private-document-review.py" || return $?
  log "Application and diagram tools ready. Copilot, gh, rg and SSH tools are optional."
}

exec_case() {
  case "$1" in
    check-deps) do_check_deps ;;
    check-app) do_check_app ;;
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
