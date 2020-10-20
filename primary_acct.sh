#!/bin/bash
api_url='api.cloudservices.f5.com'
api_version='v1'
HEADERS=()
HEADERS[0]='Content-Type: application/json'

# exit codes
# 1 - usage
# 3 - no SUB found for domain
# 4 - no cert found


set_var() {
  local varname=$1
  shift
  eval "$varname=\"$@\""
}

usage() {
  if [ $# -gt 0 ]
  then
    local varname=$1
    echo "$varname is missing"
    echo
  fi
  echo "-h This message"
  echo "-u username"
  echo "-v verbose output"
  echo "-z VERY verbose output"
  exit 1;
}

get_user_info()
{
[[ "$verbose" == "true" ]] && echo "Getting Account Information"
full_user_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-account/user)

[[ "$very_verbose" == "true" ]] && echo "ACCOUNT INFORMATION: $full_user_info"

readarray -t user < <(echo $full_user_info | jq -r '.id, .first_name, .last_name, .email')

user_id="${user[0]}"
first_name="${user[1]}"
last_name="${user[2]}"
email="${user[3]}"


}

get_membership_info()
{
[[ "$verbose" == "true" ]] && echo "Getting Membership Information"
membership_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-account/users/$user_id/memberships)

[[ "$very_verbose" == "true" ]] && echo "ACCOUNT INFORMATION: $membership_info"


readarray -t memberships < <(echo $membership_info | jq -c '.memberships[] | [.account_id, .account_name, .role_name, .level]')

#account_id="${memberships[0]}"
#first_name="${memberships[1]}"
#last_name="${memberships[2]}"
#email="${memberships[3]}"

}

while getopts 'u:vz?h' c
do
  case $c in
    u) set_var username $OPTARG ;;
    v) verbose=true ;;
    z) very_verbose=true ;;
    h|?) usage ;; 
  esac
done


###############
# Get the user to enter username and password. 
# We will use these as variables for the curl requests.
###############
[ -z "$username" ] && usage username
read -s -p "Please enter your password " password
echo


###############
# Send a login event. 
# This event will give us back an access token that will need to be provided as a header for the rest of the session.
###############
[[ "$verbose" == "true" ]] && echo "Performing login"

full_json_access_token=$(curl -s -d "{\"username\":\"${username}\", \"password\":\"${password}\"}" -H "${HEADERS[0]}" -X POST https://api.cloudservices.f5.com/v1/svc-auth/login)

access_token=$(echo $full_json_access_token | jq -r '.access_token')

[[ "$very_verbose" == "true" ]] && echo "ACCESS_TOKEN: $access_token"

###############
# Add a new header to our array to include our newly returned access token
###############
HEADERS[1]="Authorization: Bearer ${access_token}"


###############
# From now on we will need to include both headers as part of our curl request.
# There is probably a case for ${HEADERS[*]} here.
###############

get_user_info

echo "User Info"
echo "---------"
#echo "User id: $user_id"
echo "Name   : $first_name $last_name"
echo "Email  : $email"

get_membership_info

echo ; echo
echo "Memberships"
echo "-------------"
echo $membership_info | jq -c '.memberships[] | [.account_id, .account_name, .role_name, .level]' | column -t -s'[],"'
