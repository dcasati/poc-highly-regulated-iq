#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eeuo pipefail

trap 'exit 130' SIGINT
trap 'exit 143' SIGTERM

################################################################################
# Private review Bicep deployment. Authentication is managed by the operator.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
TEMPLATE_FILE=${TEMPLATE_FILE:-infra/bicep/main.bicep}
PARAMETERS_FILE=${PARAMETERS_FILE:-}
LOCATION=${LOCATION:-}
DEPLOYMENT_SCOPE=${DEPLOYMENT_SCOPE:-subscription}
RESOURCE_GROUP=${RESOURCE_GROUP:-}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-private-review}

# Use only the operator's installed Bicep; never download tools or write config.
export AZURE_BICEP_USE_BINARY_FROM_PATH=true
export AZURE_BICEP_CHECK_VERSION=false
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no

__usage='
    -x  check-deps | build | what-if | install | show
    -h  Show help.

Actions:
    check-deps  Check installed Azure CLI, Bicep and jq (no sign-in).
                Bicep may be on PATH or in the existing Azure CLI bin directory.
    build       Compile and validate the selected template locally, without output.
                Also validate PARAMETERS_FILE when supplied; never write JSON.
    what-if     Preview resource changes (resource IDs only; no property values).
    install     Run what-if, then require one explicit "yes" before deployment.
    show        Show deployment name and provisioning state only.

Environment:
    TEMPLATE_FILE     Default: infra/bicep/main.bicep
    PARAMETERS_FILE   Required for what-if/install: ignored local .bicepparam file
    LOCATION          Required explicitly for what-if/install/show
    DEPLOYMENT_SCOPE  subscription (default) | group
    RESOURCE_GROUP    Required only for group scope; must already exist
    DEPLOYMENT_NAME   Default: private-review

Relative paths are resolved from the repository, not the current directory.
No config files are sourced. Authenticate/select your subscription separately.
LOCATION selects subscription deployment metadata location; the parameter file
must independently select approved resource/model processing locations.
Review template permissions, stage controls and what-if before approving.
This runner never creates a group separately, deletes resources, grants roles,
registers providers, enrolls Tailscale or changes consent.

Example:
    LOCATION=canadacentral PARAMETERS_FILE=infra/bicep/local.bicepparam \
      ./run.sh -x what-if
'

usage() {
  printf 'usage: %s [options]\n%s\n' "${0##*/}" "$__usage"
}

print_header() {
  printf '\nPrivate review Bicep deployment\n==========================================\n'
  printf 'Subscription:   %s\n' "$SUBSCRIPTION_ID"
  printf 'Scope:          %s\nLocation:       %s\n' "$DEPLOYMENT_SCOPE" "$LOCATION"
  printf 'Resource group: %s\nDeployment:     %s\n' "$RESOURCE_GROUP" "$DEPLOYMENT_NAME"
  printf 'Template:       %s\nParameters:     %s\n\n' "$TEMPLATE_FILE" "$PARAMETERS_FILE"
}

log() {
  local timestamp
  timestamp=$(date '+%r') || return 1
  printf '[%s] %s\n' "$timestamp" "$*"
}

fail() {
  log "Error: $*" >&2
  return 1
}

do_check_deps() {
  local tool bicep_dir="${AZURE_CONFIG_DIR:-${HOME}/.azure}/bin"
  if ! command -v bicep >/dev/null 2>&1 && [[ -x "$bicep_dir/bicep" ]]; then
    export PATH="$bicep_dir:$PATH"
  fi
  for tool in az bicep jq; do
    command -v "$tool" >/dev/null 2>&1 || {
      fail "Required tool missing: $tool. Install it explicitly before retrying."
      return 1
    }
  done
  az version --output none || return $?
  bicep --version >/dev/null || return $?
  jq --version >/dev/null || return $?
  log "Azure CLI, Bicep and jq are available; no sign-in performed."
}

validate_config() {
  case "$DEPLOYMENT_SCOPE" in
    subscription)
      [[ -z "$RESOURCE_GROUP" ]] || {
        fail "RESOURCE_GROUP is only valid with DEPLOYMENT_SCOPE=group."
        return 1
      }
      ;;
    group)
      [[ -n "$RESOURCE_GROUP" ]] || {
        fail "RESOURCE_GROUP is required for group scope."
        return 1
      }
      ;;
    *)
      fail "DEPLOYMENT_SCOPE must be subscription or group."
      return 1
      ;;
  esac
  [[ "$TEMPLATE_FILE" = /* ]] || TEMPLATE_FILE="$SCRIPT_DIR/$TEMPLATE_FILE"
  [[ "$TEMPLATE_FILE" = *.bicep && -f "$TEMPLATE_FILE" && -r "$TEMPLATE_FILE" ]] || {
    fail "TEMPLATE_FILE must be a readable .bicep file."
    return 1
  }
  if [[ -n "$PARAMETERS_FILE" ]]; then
    [[ "$PARAMETERS_FILE" = /* ]] || PARAMETERS_FILE="$SCRIPT_DIR/$PARAMETERS_FILE"
    [[ "$PARAMETERS_FILE" = *.bicepparam && -f "$PARAMETERS_FILE" && -r "$PARAMETERS_FILE" ]] || {
      fail "PARAMETERS_FILE must be a readable local .bicepparam file."
      return 1
    }
  fi
}

compile_inputs() {
  local schema
  COMPILED_TEMPLATE=$(bicep build "$TEMPLATE_FILE" --stdout --no-restore) || return $?
  schema=$(printf '%s' "$COMPILED_TEMPLATE" | jq -er '."$schema"') || return $?
  case "$DEPLOYMENT_SCOPE:$schema" in
    subscription:https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#) ;;
    group:https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#) ;;
    *)
      fail "Template target scope does not match DEPLOYMENT_SCOPE=$DEPLOYMENT_SCOPE."
      return 1
      ;;
  esac
  COMPILED_PARAMETERS=
  if [[ -n "$PARAMETERS_FILE" ]]; then
    COMPILED_PARAMETERS=$(bicep build-params "$PARAMETERS_FILE" \
      --bicep-file "$TEMPLATE_FILE" --stdout --no-restore) || return $?
  fi
}

do_build() {
  do_check_deps || return $?
  validate_config || return $?
  compile_inputs || return $?
  log "Bicep compilation and target scope checks passed; no files written."
}

prepare_deployment() {
  [[ "$LOCATION" =~ ^[a-z][a-z0-9]+$ ]] || {
    fail "Set LOCATION explicitly to an Azure region identifier (for example canadacentral)."
    return 1
  }
  [[ -n "$PARAMETERS_FILE" ]] || {
    fail "Set PARAMETERS_FILE explicitly to your local .bicepparam file."
    return 1
  }
  do_build || return $?
  resolve_subscription || return $?
  DEPLOYMENT_ARGS=(--subscription "$SUBSCRIPTION_ID" --name "$DEPLOYMENT_NAME")
  if [[ "$DEPLOYMENT_SCOPE" = subscription ]]; then
    CLI_SCOPE=sub
    DEPLOYMENT_ARGS+=(--location "$LOCATION")
  else
    CLI_SCOPE=group
    az group show --subscription "$SUBSCRIPTION_ID" \
      --name "$RESOURCE_GROUP" --output none || return $?
    DEPLOYMENT_ARGS+=(--resource-group "$RESOURCE_GROUP")
  fi
  DEPLOYMENT_ARGS+=(--template-file "$TEMPLATE_FILE" --parameters "$PARAMETERS_FILE")
}

resolve_subscription() {
  SUBSCRIPTION_ID=$(az account show --query id --output tsv) || return $?
  [[ "$SUBSCRIPTION_ID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
    fail "Azure CLI did not return a valid selected subscription ID."
    return 1
  }
}

do_what_if() {
  prepare_deployment || return $?
  print_header || return $?
  az deployment "$CLI_SCOPE" what-if "${DEPLOYMENT_ARGS[@]}" \
    --result-format ResourceIdOnly || return $?
}

do_install() {
  local answer reviewed_template reviewed_parameters
  do_what_if || return $?
  reviewed_template=$COMPILED_TEMPLATE
  reviewed_parameters=$COMPILED_PARAMETERS
  printf '\nApprove the successful what-if for the exact scope/template/parameters above?\nType yes to deploy: ' || return $?
  IFS= read -r answer || {
    fail "Confirmation was not received; nothing deployed."
    return 1
  }
  [[ "$answer" = yes ]] || {
    fail "Deployment not approved; nothing deployed."
    return 1
  }
  compile_inputs || return $?
  [[ "$COMPILED_TEMPLATE" = "$reviewed_template" && "$COMPILED_PARAMETERS" = "$reviewed_parameters" ]] || {
    fail "Inputs changed after what-if; rerun install and review again."
    return 1
  }
  az deployment "$CLI_SCOPE" create "${DEPLOYMENT_ARGS[@]}" --output none || return $?
  log "Deployment completed. Readiness is not verified by deployment success."
}

do_show() {
  [[ "$LOCATION" =~ ^[a-z][a-z0-9]+$ ]] || {
    fail "Set LOCATION explicitly to an Azure region identifier (for example canadacentral)."
    return 1
  }
  do_build || return $?
  resolve_subscription || return $?
  local scope=sub args=(--subscription "$SUBSCRIPTION_ID" --name "$DEPLOYMENT_NAME")
  if [[ "$DEPLOYMENT_SCOPE" = group ]]; then
    scope=group
    args+=(--resource-group "$RESOURCE_GROUP")
  fi
  az deployment "$scope" show "${args[@]}" \
    --query '{name:name,state:properties.provisioningState}' --output table || return $?
}

exec_case() {
  case "$1" in
    check-deps) do_check_deps ;;
    build) do_build ;;
    what-if) do_what_if ;;
    install) do_install ;;
    show) do_show ;;
    *) usage >&2; return 1 ;;
  esac
}

################################################################################
main() {
  local opt action= help=false
  while getopts ':hx:' opt; do
    case "$opt" in
      h) help=true ;;
      x)
        [[ -z "$action" && -n "$OPTARG" ]] || { usage >&2; return 1; }
        action=$OPTARG
        ;;
      *) usage >&2; return 1 ;;
    esac
  done
  shift "$((OPTIND - 1))"
  [[ $# = 0 ]] || { usage >&2; return 1; }
  if [[ "$help" = true ]]; then
    [[ -z "$action" ]] || { usage >&2; return 1; }
    usage
    return $?
  fi
  [[ -n "$action" ]] || { usage >&2; return 1; }
  exec_case "$action" || return $?
}

main "$@" || exit $?
exit 0
