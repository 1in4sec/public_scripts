#!/bin/bash
# Create an API service user with restricted permissions (no IAM user management).
# Intended for OCI Cloud Shell usage.

# Colors
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

# Configuration
export compartment_id=""
export group_name="Group_for_Api_used"
export group_des="API access group with restricted permissions (no IAM user management)"
export policy_name="Policy_for_Api_used"
export policy_des="Policy granting limited resource management for API usage"
export policy_file="file://statements.json"
export user_name="User_for_Api_used"
export user_des="Service user for API access with restricted permissions"
export user_email="xxxxxx@domain.com"
export type="new"
export ignore_error="0"
export api_key_file="./api_public.pem"   # Path to public key file

while [[ $# -ge 1 ]]; do
 case $1 in
 -c | --compartment_id )
  shift; compartment_id="$1"; shift ;;
 -g | --group_name )
  shift; group_name="$1"; shift ;;
 -gd | --group_des )
  shift; group_des="$1"; shift ;;
 -p | --policy_name )
  shift; policy_name="$1"; shift ;;
 -pd | --policy_des )
  shift; policy_des="$1"; shift ;;
 -u | --user_name )
  shift; user_name="$1"; shift ;;
 -ud | --user_des )
  shift; user_des="$1"; shift ;;
 -ue | --user_email )
  shift; user_email="$1"; shift ;;
 -t | --type )
  shift; type="$1"; shift ;;
 -kf | --key_file )
  shift; api_key_file="$1"; shift ;;
 --ignore_error )
  shift; ignore_error="1" ;;
 -h | --help )
  echo "Usage: bash $(basename $0) [options]"
  exit 1 ;;
 * )
  echo -e "${RED}Invalid argument: $1${RESET}"
  exit 1 ;;
 esac
done

# Validate input
if [ "$type" == "new" ] && [ -z "$user_email" ]; then
 echo -e "${RED}User email is required when type=new${RESET}"
 exit 1
fi

# Generate policy statements
if [ "$type" == "new" ]; then
 cat > statements.json <<EOF
[
 "Allow group 'Default'/'$group_name' to manage instance-family in tenancy",
 "Allow group 'Default'/'$group_name' to manage volume-family in tenancy",
 "Allow group 'Default'/'$group_name' to manage virtual-network-family in tenancy",
 "Allow group 'Default'/'$group_name' to read all-resources in tenancy"
]
EOF
else
 cat > statements.json <<EOF
[
 "Allow group $group_name to manage instance-family in tenancy",
 "Allow group $group_name to manage volume-family in tenancy",
 "Allow group $group_name to manage virtual-network-family in tenancy",
 "Allow group $group_name to read all-resources in tenancy"
]
EOF
fi

# Helper function
function check() {
 if printf '%s' "$1" | grep -q "ServiceError"; then
  err_msg=$(printf '%s' "$1" | sed -n 's/.*"message": "\(.*\)".*/\1/p')
  echo -e "${RED}ERROR: $err_msg${RESET}"
  [ "$ignore_error" == "0" ] && exit 1
 else
  echo -e "${GREEN}$2${RESET}"
 fi
}

# Get tenancy OCID
compartment_id=$(oci iam availability-domain list \
  --query 'data[0]."compartment-id"' \
  --raw-output)

echo -e "${GREEN}Tenancy OCID: $compartment_id${RESET}"

# Delete existing group
group_id_old=$(oci iam group list \
  --compartment-id $compartment_id \
  --name $group_name \
  --query 'data[0]."id"' \
  --raw-output)

if [ -z "$group_id_old" ]; then
 echo -e "${GREEN}No existing group found${RESET}"
else
 group_old_result=$(oci iam group delete --group-id $group_id_old --force --output json)
 check "$group_old_result" "Existing group deleted"
fi

# Create group
group_result=$(oci iam group create \
  --compartment-id $compartment_id \
  --name $group_name \
  --description "$group_des" \
  --output json)

check "$group_result" "Group created"

group_id=$(printf '%s' "$group_result" | jq -er '.data.id')

# Delete existing policy
policy_id_old=$(oci iam policy list \
  --compartment-id $compartment_id \
  --name $policy_name \
  --query 'data[0]."id"' \
  --raw-output)

if [ -z "$policy_id_old" ]; then
 echo -e "${GREEN}No existing policy found${RESET}"
else
 policy_old_result=$(oci iam policy delete --policy-id $policy_id_old --force --output json)
 check "$policy_old_result" "Existing policy deleted"
fi

# Create policy
policy_result=$(oci iam policy create \
  --compartment-id $compartment_id \
  --description "$policy_des" \
  --name $policy_name \
  --statements $policy_file \
  --output json)

check "$policy_result" "Policy created"

# Create or reuse user
user_id_old=$(oci iam user list \
  --compartment-id $compartment_id \
  --name $user_name \
  --query 'data[0]."id"' \
  --raw-output)

if [ -z "$user_id_old" ]; then
 if [ -z "$user_email" ]; then
  user_result=$(oci iam user create \
    --name $user_name \
    --description "$user_des" \
    --compartment-id $compartment_id \
    --output json)
 else
  user_result=$(oci iam user create \
    --name $user_name \
    --description "$user_des" \
    --compartment-id $compartment_id \
    --email $user_email \
    --output json)
 fi

 check "$user_result" "User created"

 user_id=$(printf '%s' "$user_result" | jq -er '.data.id')
else
 user_id=$user_id_old
 echo -e "${GREEN}User already exists (skipped)${RESET}"
fi

# Add user to group
add_result=$(oci iam group add-user \
  --group-id $group_id \
  --user-id $user_id \
  --output json)

check "$add_result" "User added to group"

# Upload API key (optional)
if [ -n "$api_key_file" ]; then
 if [ ! -f "$api_key_file" ]; then
  echo -e "${RED}API key file not found: $api_key_file${RESET}"
  exit 1
 fi

 echo -e "${GREEN}Uploading API key...${RESET}"

 api_key_result=$(oci iam user api-key upload \
   --user-id $user_id \
   --key-file "$api_key_file" \
   --output json)

 check "$api_key_result" "API key uploaded successfully"
else
 echo -e "${GREEN}No API key file provided, skipping upload${RESET}"
fi

echo -e "${GREEN}Setup completed successfully${RESET}"
