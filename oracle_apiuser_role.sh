#!/bin/bash
# Add a user who does not have user management permissions and can only manage instances, storage, and network
# Execute in Cloud Shell
# Colors
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"
# 参数
export compartment_id=""     # Tenant OCID
export group_name="Group_for_Api_used"    # Group name
export group_des="This user group is for API use, with restricted permissions to prevent API from performing user-related operations"    # Group description
export policy_name="Policy_for_Api_used"   # Policy name
export policy_des="This policy is for API use, with restricted permissions to prevent API from performing user-related operations"    # Policy description
export policy_file="file://statements.json" # Policy statement file
export user_name="User_for_Api_used"    # User name
export user_des="This user is for API use, with restricted permissions to prevent API from performing user-related operations"    # User description
export user_email="xxxxxx@domain.com"   # User email (required when type is 'new')
export type="new"       # Control panel type: new or old
export ignore_error="0"      # Ignore errors
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
  echo -ne "Usage: bash $(basename $0) [options]\n\033[33m\033[04m-c\033[0m\t\tTenant OCID, default自动retrieve\n\033[33m\033[04m-g\033[0m\t\tGroup name, defaultCore-Admins\n\033[33m\033[04m-gd\033[0m\t\tGroup description, defaultCore-Admins\n\033[33m\033[04m-p\033[0m\t\tPolicy name, defaultCore-Admins\n\033[33m\033[04m-pd\033[0m\t\tPolicy description, defaultCore-Admins\n\033[33m\033[04m-pf\033[0m\t\tPolicy statement file, defaultfile://statements.json\n\033[33m\033[04m-u\033[0m\t\tUser name, defaultCore-Admin\n\033[33m\033[04m-ud\033[0m\t\tUser description, defaultCore-Admin\n\033[33m\033[04m-ue\033[0m\t\t用户邮箱, 当type为new时required, defaultxx@domain.sssss\n\033[33m\033[04m-t\033[0m\t\t控制面板类型, new或者old, defaultold\n\033[33m\033[04m--ignore_error\033[0m\tIgnore errors返回信息\n\033[33m\033[04m-h\033[0m\t\tHelp\n\nExample: bash $(basename $0) -ue xx@xx.com -t new --ignore_error \n"
  exit 1;
  ;;
 * )
  echo -e "${RED}Invalid parameter: $1${RESET}"
  exit 1;
  ;;
 esac
 done
# 检查参数
if [ "$type" == "new" ]; then
 if [ "$user_email" == "" ]; then
 echo -e "${RED}User email cannot be empty${RESET}"
 exit 1
 fi
fi
# Policy statements
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
 \"Allow group $group_name to manage virtual-network-family in tenancy\"
 \"Allow group $group_name to read all-resources in tenancy\"
 ]" > statements.json
fi
# Check command execution result
function check() {
 if echo "$1" | grep -q "ServiceError"; then
 err_msg=$(echo "$1" | sed -n 's/.*"message": "\(.*\)",/\1/p')
 echo -e "${RED}Command execution failed：$err_msg${RESET}"
 if [ "$ignore_error" == "0" ]; then
  exit 1
 fi
 else
 echo -e "${GREEN}$2${RESET}"
 fi
}
# retrieveTenant OCID
compartment_id=$(oci iam availability-domain list --query 'data[0]."compartment-id"' --raw-output)
echo -e "${GREEN}Tenant OCID: $compartment_id ${RESET}"
# delete已有组
group_id_old=$(oci iam  group list --compartment-id $compartment_id --name $group_name --query 'data[0]."id"' --raw-output)
if [ "$group_id_old" == "" ]; then
 echo -e "${GREEN}No need to delete existing group"
else
 group_old_result=$(oci iam group delete --group-id $group_id_old --force 2>&1)
 check "$group_old_result" "Existing group deleted successfully"
fi
# create组
group_result=$(oci iam group create --compartment-id $compartment_id --name $group_name --description $group_des 2>&1)
check "$group_result" "Group created successfully"
group_id=$(echo $group_result | jq -r '.data.id')
# delete已有策略
policy_id_old=$(oci iam policy list --compartment-id $compartment_id --name $policy_name --query 'data[0]."id"' --raw-output)
if [ "$policy_id_old" == "" ]; then
 echo -e "${GREEN}No existing policy, skipping deletion"
else
 policy_old_result=$(oci iam policy delete --policy-id $policy_id_old --force 2>&1)
 check "$policy_old_result" "Existing policy deleted successfully"
fi
# create策略
policy_result=$(oci iam policy create --compartment-id $compartment_id --description $policy_des --name $policy_name --statements $policy_file 2>&1)
check "$policy_result" "Policy created successfully"
# create用户
user_id_old=$(oci iam user list --compartment-id $compartment_id --name $user_name --query 'data[0]."id"' --raw-output)
if [ "$user_id_old" == "" ]; then
 if [ "$user_email" == "" ]; then
  user_result=$(oci iam user create --name $user_name --description $user_des --compartment-id $compartment_id 2>&1)
 else
  user_result=$(oci iam user create --name $user_name --description $user_des --compartment-id $compartment_id --email $user_email 2>&1)
 fi
 check "$user_result" "User created successfully"
 user_id=$(echo $user_result | jq -r '.data.id')
else
 #user_old_result=$(oci iam user delete --user-id $user_id_old --force 2>&1)
 user_id=$user_id_old
 echo -e "${GREEN}User already exists, skipping creation"
fi
# 将用户add到组
add_result=$(oci iam group add-user --group-id $group_id --user-id $user_id 2>&1)
check "$add_result" "User successfully added to group\n\nYou can later manually add an API key to the user $user_name 中add API密钥 (无需登录该用户)"
