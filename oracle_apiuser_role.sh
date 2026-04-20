#!/bin/bash
set -e

# ==============================
# OCI API User Setup Script
# ==============================
# Creates:
# - Group
# - Policy
# - User (API_User)
# - Adds user to group
# ==============================

# ===== Colors =====
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

# ===== Defaults =====
compartment_id=""
group_name="API_Group"
group_des="API restricted group (no user-management permissions)"

policy_name="API_Policy"
policy_des="API restricted policy (no user-management permissions)"
policy_file="statements.json"

user_name="API_User"
user_des="API user for automation (restricted permissions)"
user_email=""

type="new"
ignore_error=0

# ===== Logging =====
log_success() { echo -e "${GREEN}✔ $1${RESET}"; }
log_error()   { echo -e "${RED}✖ $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠ $1${RESET}"; }

# ===== Command Runner =====
run_cmd() {
  output=$(eval "$1" 2>&1) || {
    log_error "$output"
    [[ "$ignore_error" == "0" ]] && exit 1
  }
  echo "$output"
}

# ===== Help =====
show_help() {
  echo "Usage: $0 [options]"
  echo "-c   compartment_id"
  echo "-g   group_name"
  echo "-p   policy_name"
  echo "-u   user_name"
  echo "-ue  user_email (required if type=new)"
  echo "-t   type (new|old)"
  echo "--ignore_error"
  exit 0
}

# ===== Parse Arguments =====
while [[ $# -gt 0 ]]; do
  case $1 in
    -c) compartment_id="$2"; shift 2 ;;
    -g) group_name="$2"; shift 2 ;;
    -p) policy_name="$2"; shift 2 ;;
    -u) user_name="$2"; shift 2 ;;
    -ue) user_email="$2"; shift 2 ;;
    -t) type="$2"; shift 2 ;;
    --ignore_error) ignore_error=1; shift ;;
    -h) show_help ;;
    *) log_error "Invalid argument: $1"; exit 1 ;;
  esac
done

# ===== Validation =====
if [[ "$type" == "new" && -z "$user_email" ]]; then
  log_error "User email is required when type=new"
  exit 1
fi

# ===== Get Compartment ID =====
if [[ -z "$compartment_id" ]]; then
  compartment_id=$(oci iam availability-domain list \
    --query 'data[0]."compartment-id"' --raw-output)
fi

log_success "Compartment ID: $compartment_id"

# ===== Generate Policy =====
cat > "$policy_file" <<EOF
[
  "Allow group '$group_name' to manage instance-family in tenancy",
  "Allow group '$group_name' to manage volume-family in tenancy",
  "Allow group '$group_name' to manage virtual-network-family in tenancy",
  "Allow group '$group_name' to read all-resources in tenancy"
]
EOF

log_success "Policy file created"

# ===== Delete Existing Group =====
group_id=$(oci iam group list \
  --compartment-id "$compartment_id" \
  --name "$group_name" \
  --query 'data[0].id' --raw-output)

if [[ -n "$group_id" ]]; then
  run_cmd "oci iam group delete --group-id $group_id --force"
  log_success "Old group deleted"
fi

# ===== Create Group =====
group_result=$(run_cmd "oci iam group create \
  --compartment-id $compartment_id \
  --name \"$group_name\" \
  --description \"$group_des\"")

group_id=$(echo "$group_result" | jq -r '.data.id')
log_success "Group created"

# ===== Delete Existing Policy =====
policy_id=$(oci iam policy list \
  --compartment-id "$compartment_id" \
  --name "$policy_name" \
  --query 'data[0].id' --raw-output)

if [[ -n "$policy_id" ]]; then
  run_cmd "oci iam policy delete --policy-id $policy_id --force"
  log_success "Old policy deleted"
fi

# ===== Create Policy =====
run_cmd "oci iam policy create \
  --compartment-id $compartment_id \
  --name \"$policy_name\" \
  --description \"$policy_des\" \
  --statements file://$policy_file"

log_success "Policy created"

# ===== Create or Reuse User =====
user_id=$(oci iam user list \
  --compartment-id "$compartment_id" \
  --name "$user_name" \
  --query 'data[0].id' --raw-output)

if [[ -z "$user_id" ]]; then
  if [[ -n "$user_email" ]]; then
    user_result=$(run_cmd "oci iam user create \
      --name \"$user_name\" \
      --description \"$user_des\" \
      --compartment-id $compartment_id \
      --email $user_email")
  else
    user_result=$(run_cmd "oci iam user create \
      --name \"$user_name\" \
      --description \"$user_des\" \
      --compartment-id $compartment_id")
  fi

  user_id=$(echo "$user_result" | jq -r '.data.id')
  log_success "User created"
else
  log_warn "User already exists → reuse"
fi

# ===== Add User to Group =====
run_cmd "oci iam group add-user \
  --group-id $group_id \
  --user-id $user_id"

log_success "User added to group"

# ===== Done =====
echo -e "\n${GREEN}Done!${RESET}"
echo -e "User: ${YELLOW}$user_name${RESET}"
echo -e "You can now add API keys to this user (no login required)."
