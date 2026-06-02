#!/usr/bin/env bash
set -euo pipefail

# Get OCI IAM information for API_User created by:
# https://github.com/1in4sec/public_scripts/blob/main/oracle_apiuser_role.sh
#
# The source script defaults to:
#   user_name=API_User
#   group_name=Group_for_API_User
#   policy_name=Policy_for_API_User
#   api_key_file=./api_public.pem
#
# Usage:
#   ./get_oci_user_info.sh [oci_config_file] [target_user_name_or_ocid]
#
# Examples:
#   ./get_oci_user_info.sh ~/.oci/config
#   ./get_oci_user_info.sh ./api_user_oci.config
#   ./get_oci_user_info.sh ~/.oci/config API_User
#   ./get_oci_user_info.sh ~/.oci/config ocid1.user.oc1..xxxxx
#
# Environment overrides:
#   OCI_CONFIG_FILE       OCI config file path. Default: first arg or ~/.oci/config
#   OCI_PROFILE           OCI config profile. Default: DEFAULT
#   OCI_TARGET_USER_NAME  User name to find. Default: API_User
#   OCI_TARGET_USER_ID    User OCID to inspect. Overrides name lookup
#   OCI_GROUP_NAME        API group name. Default: Group_for_API_User
#   OCI_POLICY_NAME       API policy name. Default: Policy_for_API_User
#   OCI_OUTPUT_FORMAT     OCI output format. Default: json

usage() {
  sed -n '1,29p' "$0" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

warn() {
  echo "Warning: $*" >&2
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

expand_path() {
  local path="$1"
  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

config_value() {
  local key="$1"

  awk -v profile="$PROFILE" -v key="$key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*(#|;|$)/ {
      next
    }

    /^[[:space:]]*\[/ {
      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\].*$/, "", section)
      in_profile = (trim(section) == profile)
      next
    }

    in_profile {
      line = $0
      equals = index(line, "=")
      if (equals == 0) {
        next
      }

      found_key = trim(substr(line, 1, equals - 1))
      if (found_key == key) {
        print trim(substr(line, equals + 1))
        exit
      }
    }
  ' "$CONFIG_FILE"
}

normalize_oci_value() {
  local value="$1"
  case "$value" in
    "" | "null" | "None") return 0 ;;
    *) printf '%s\n' "$value" ;;
  esac
}

oci_raw() {
  local output

  if output="$("${OCI_BASE[@]}" "$@" 2>/dev/null)"; then
    printf '%s\n' "$output"
  fi
}

print_section() {
  printf '\n== %s ==\n' "$1"
}

run_oci_required() {
  local title="$1"
  shift

  print_section "$title"
  "${OCI_BASE[@]}" --output "$OUTPUT_FORMAT" "$@"
}

run_oci_optional() {
  local title="$1"
  shift

  print_section "$title"
  if ! "${OCI_BASE[@]}" --output "$OUTPUT_FORMAT" "$@"; then
    warn "Could not fetch ${title}. Check IAM permissions for this user."
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CONFIG_FILE="${OCI_CONFIG_FILE:-${1:-$HOME/.oci/config}}"
PROFILE="${OCI_PROFILE:-DEFAULT}"
OUTPUT_FORMAT="${OCI_OUTPUT_FORMAT:-json}"
GROUP_NAME="${OCI_GROUP_NAME:-Group_for_API_User}"
POLICY_NAME="${OCI_POLICY_NAME:-Policy_for_API_User}"
TARGET_ARG="${2:-}"
TARGET_USER_OCID="${OCI_TARGET_USER_ID:-}"
TARGET_USER_NAME="${OCI_TARGET_USER_NAME:-API_User}"

if [[ -n "$TARGET_ARG" ]]; then
  if [[ "$TARGET_ARG" == ocid1.user.* ]]; then
    TARGET_USER_OCID="$TARGET_ARG"
  else
    TARGET_USER_NAME="$TARGET_ARG"
  fi
fi

CONFIG_FILE="$(expand_path "$CONFIG_FILE")"
[[ -r "$CONFIG_FILE" ]] || die "OCI config file is not readable: $CONFIG_FILE"

need_command oci

AUTH_USER_OCID="$(config_value user)"
TENANCY_OCID="$(config_value tenancy)"
REGION="$(config_value region)"
FINGERPRINT="$(config_value fingerprint)"
KEY_FILE="$(config_value key_file)"

[[ -n "$AUTH_USER_OCID" ]] || die "Missing 'user' in profile [$PROFILE]"
[[ -n "$TENANCY_OCID" ]] || die "Missing 'tenancy' in profile [$PROFILE]"
[[ -n "$REGION" ]] || die "Missing 'region' in profile [$PROFILE]"
[[ -n "$FINGERPRINT" ]] || die "Missing 'fingerprint' in profile [$PROFILE]"
[[ -n "$KEY_FILE" ]] || die "Missing 'key_file' in profile [$PROFILE]"

EXPANDED_KEY_FILE="$(expand_path "$KEY_FILE")"
if [[ ! -r "$EXPANDED_KEY_FILE" ]]; then
  warn "key_file from config is not readable: $KEY_FILE"
fi

OCI_BASE=(oci --config-file "$CONFIG_FILE" --profile "$PROFILE" --region "$REGION")

if [[ -z "$TARGET_USER_OCID" ]]; then
  TARGET_USER_OCID="$(
    normalize_oci_value "$(
      oci_raw iam user list \
        --compartment-id "$TENANCY_OCID" \
        --name "$TARGET_USER_NAME" \
        --query 'data[0].id' \
        --raw-output
    )"
  )"
fi

if [[ -z "$TARGET_USER_OCID" && "$TARGET_USER_NAME" == "API_User" ]]; then
  warn "Could not find API_User by name. Falling back to 'user' from OCI config."
  TARGET_USER_OCID="$AUTH_USER_OCID"
fi

[[ -n "$TARGET_USER_OCID" ]] || die "Could not resolve target user: $TARGET_USER_NAME"

GROUP_ID="$(
  normalize_oci_value "$(
    oci_raw iam group list \
      --compartment-id "$TENANCY_OCID" \
      --name "$GROUP_NAME" \
      --query 'data[0].id' \
      --raw-output
  )"
)"

POLICY_ID="$(
  normalize_oci_value "$(
    oci_raw iam policy list \
      --compartment-id "$TENANCY_OCID" \
      --name "$POLICY_NAME" \
      --query 'data[0].id' \
      --raw-output
  )"
)"

print_section "OCI profile and API user targets"
cat <<EOF
config_file:      $CONFIG_FILE
profile:          $PROFILE
region:           $REGION
tenancy:          $TENANCY_OCID
auth_user:        $AUTH_USER_OCID
target_user_name: $TARGET_USER_NAME
target_user_id:   $TARGET_USER_OCID
group_name:       $GROUP_NAME
group_id:         ${GROUP_ID:-not found}
policy_name:      $POLICY_NAME
policy_id:        ${POLICY_ID:-not found}
fingerprint:      $FINGERPRINT
key_file:         $KEY_FILE
EOF

run_oci_required \
  "User details: $TARGET_USER_NAME" \
  iam user get \
  --user-id "$TARGET_USER_OCID"

run_oci_optional \
  "Groups for user: $TARGET_USER_NAME" \
  iam user list-groups \
  --compartment-id "$TENANCY_OCID" \
  --user-id "$TARGET_USER_OCID" \
  --all

if [[ -n "$GROUP_ID" ]]; then
  run_oci_optional \
    "Group details: $GROUP_NAME" \
    iam group get \
    --group-id "$GROUP_ID"

  run_oci_optional \
    "Users in group: $GROUP_NAME" \
    iam group list-users \
    --compartment-id "$TENANCY_OCID" \
    --group-id "$GROUP_ID" \
    --all
else
  warn "Group not found by name: $GROUP_NAME"
fi

run_oci_optional \
  "Policy list by name: $POLICY_NAME" \
  iam policy list \
  --compartment-id "$TENANCY_OCID" \
  --name "$POLICY_NAME" \
  --all

if [[ -n "$POLICY_ID" ]]; then
  run_oci_optional \
    "Policy details: $POLICY_NAME" \
    iam policy get \
    --policy-id "$POLICY_ID"
else
  warn "Policy not found by name: $POLICY_NAME"
fi

run_oci_optional \
  "API signing keys for user: $TARGET_USER_NAME" \
  iam user api-key list \
  --user-id "$TARGET_USER_OCID" \
  --all
