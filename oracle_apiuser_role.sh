#!/bin/bash
# Create an API service user with restricted permissions (no IAM user management).
# Intended for use in OCI Cloud Shell.

# Colors
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

# Configuration
export compartment_id=""     # Tenancy OCID
export group_name="Group_for_Api_used"    # IAM group name
export group_des="API access group with restricted permissions (no IAM user management)"    # Group description
export policy_name="Policy_for_Api_used"   # IAM policy name
export policy_des="Policy granting limited resource management for API usage"    # Policy description
export policy_file="file://statements.json" # Policy statements file
export user_name="User_for_Api_used"    # IAM user name
export user_des="Service user for API access with restricted permissions"    # User description
export user_email="xxxxxx@domain.com"   # Required if type=new
export type="new"       # Console type: new | old
export ignore_error="0"      # Continue on error (1=true)

while [[ $# -ge 1 ]]; do
 case $1 in
 -c | --compartment_id )
  shift
  compartment_id="$1"
  shift
  ;;
 -g | --group_name )
  shift
  group_name="$1"
  shift
  ;;
 -gd | --group_des )
  shift
  group_des="$1"
  shift
  ;;
 -p | --policy_name )
  shift
  policy_name="$1"
  shift
  ;;
 -pd | --policy_des )
  shift
  policy_des="$1"
  shift
  ;;
 -u | --user_name )
  shift
  user_name="$1"
  shift
  ;;
 -ud | --user_des )
  shift
  user_des="$1"
  shift
  ;;
 -ue | --user_email )
  shift
  user_email="$1"
  shift
  ;;
 -t | --type )
  shift
  type="$1"
  shift
  ;;
 --ignore_error )
  shift
  ignore_error="1"
  ;;
 -h | --help )
  echo -ne "Usage: bash $(basename $0) [options]\n\
\033[33m\033[04m-c\033[0m\t\tTenancy OCID (auto-detected if omitted)\n\
\033[33m\033[04m-g\033[0m\t\tGroup name\n\
\033[33m\033[04m-gd\033[0m\t\tGroup description\n\
\033[33m\033[04m-p\033[0m\t\tPolicy name\n\
\033[33m\033[04m-pd\033[0m\t\tPolicy description\n\
\033[33m\033[04m-pf\033[0m\t\tPolicy statements file (default: file://statements.json)\n\
\033[33m\033[04m-u\033[0m\t\tUser name\n\
\033[33m\033[04m-ud\033[0m\t\tUser description\n\
\033[33m\033[04m-ue\033[0m\t\tUser email (required if type=new)\n\
\033[33m\033[04m-t\033[0m\t\tConsole type: new | old (default: old)\n\
\033[33m\033[04m--ignore_error\033[0m\tContinue execution on errors\n\
\033[33m\033[04m-h\033[0m\t\tHelp\n\n\
Example: bash $(basename $0) -ue user@example.com -t new --ignore_error\n"
  exit 1;
  ;;
 * )
  echo -e "${RED}Invalid argument: $1${RESET}"
  exit 1;
  ;;
 esac
done

# Validate input
if [ "$type" == "new" ]; then
 if [ -z "$user_email" ]; then
  echo -e "${RED}User email is required when type=new${RESET}"
  exit 1
 fi
fi

# Generate policy statements
if [ "$type" == "new" ]; then
 echo "[
 \"Allow group 'Default'/'$group_name' to manage instance-family in tenancy\",
 \"Allow group 'Default'/'$group_name' to manage volume-family in tenancy\",
 \"Allow group 'Default'/'$group_name' to manage virtual-network-family in tenancy\",
 \"Allow group 'Default'/'$group_name' to read all-resources in tenancy\"
 ]" > statements.json
else 
 echo "[
 \"Allow group $group_name to manage instance-family in tenancy\",
 \"Allow group $group_name to manage volume-family in tenancy\",
 \"Allow group $group_name to manage virtual-network-family in tenancy\",
 \"Allow group $group_name to read all-resources in tenancy\"
 ]" > statements.json
fi

# Helper: validate OCI CLI response
function check() {
 if echo "$1" | grep -q "ServiceError"; then
  err_msg=$(echo "$1" | sed -n 's/.*"message": "\(.*\)",/\1/p')
  echo -e "${RED}ERROR: $err_msg${RESET}"
  if [ "$ignore_error" == "0" ]; then
   exit 1
  fi
 else
  echo -e "${GREEN}$2${RESET}"
 fi
}

# Resolve tenancy OCID
compartment_id=$(oci iam availability-domain list --query 'data[0]."compartment-id"' --raw-output)
echo -e "${GREEN}Tenancy OCID: $compartment_id${RESET}"

# Remove existing group (if any)
group_id_old=$(oci iam group list --compartment-id $compartment_id --name $group_name --query 'data[0]."id"' --raw-output)
if [ -z "$group_id_old" ]; then
 echo -e "${GREEN}No existing group found${RESET}"
else
 group_old_result=$(oci iam group delete --group-id $group_id_old --force 2>&1)
 check "$group_old_result" "Existing group deleted"
fi

# Create group
group_result=$(oci iam group create --compartment-id $compartment_id --name $group_name --description "$group_des" 2>&1)
check "$group_result" "Group created"
group_id=$(echo $group_result | jq -r '.data.id')

# Remove existing policy (if any)
policy_id_old=$(oci iam policy list --compartment-id $compartment_id --name $policy_name --query 'data[0]."id"' --raw-output)
if [ -z "$policy_id_old" ]; then
 echo -e "${GREEN}No existing policy found${RESET}"
else
 policy_old_result=$(oci iam policy delete --policy-id $policy_id_old --force 2>&1)
 check "$policy_old_result" "Existing policy deleted"
fi

# Create policy
policy_result=$(oci iam policy create --compartment-id $compartment_id --description "$policy_des" --name $policy_name --statements $policy_file 2>&1)
check "$policy_result" "Policy created"

# Create or reuse user
user_id_old=$(oci iam user list --compartment-id $compartment_id --name $user_name --query 'data[0]."id"' --raw-output)
if [ -z "$user_id_old" ]; then
 if [ -z "$user_email" ]; then
  user_result=$(oci iam user create --name $user_name --description "$user_des" --compartment-id $compartment_id 2>&1)
 else
  user_result=$(oci iam user create --name $user_name --description "$user_des" --compartment-id $compartment_id --email $user_email 2>&1)
 fi
 check "$user_result" "User created"
 user_id=$(echo $user_result | jq -r '.data.id')
else
 user_id=$user_id_old
 echo -e "${GREEN}User already exists (skipped)${RESET}"
fi

# Add user to group
add_result=$(oci iam group add-user --group-id $group_id --user-id $user_id 2>&1)
check "$add_result" "User added to group\n\nNext step: add an API key to user $user_name (no login required)"
