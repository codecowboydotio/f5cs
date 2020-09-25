#!/bin/bash
api_url='api.cloudservices.f5.com'
api_version='v1'
debug='false'
HEADERS=()
HEADERS[0]='Content-Type: application/json'
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
  echo "-d delete unused certificates (brutal)"
  echo "-u username"
  exit 1;
}

while getopts 'u:d?h' c
do
  case $c in
    u) set_var username $OPTARG ;;
    d) delete=true ;;
    h|?) usage ;; 
  esac
done

###############
#Get the user to enter username and password. 
#We will use these as variables for the curl requests.
###############

[ -z "$username" ] && usage username

read -s -p "Please enter your password " password

[ -z "$password" ] && usage password

###############
# Send a login event. 
# This event will give us back an access token that will need to be provided as a header for the rest of the session.
###############
full_json_access_token=$(curl -s -d "{\"username\":\"${username}\", \"password\":\"${password}\"}" -H "${HEADERS[0]}" -X POST https://api.cloudservices.f5.com/v1/svc-auth/login)

access_token=$(echo $full_json_access_token | jq -r '.access_token')


###############
# Add a new header to our array to include our newly returned access token
###############
HEADERS[1]="Authorization: Bearer ${access_token}"


###############
# From now on we will need to include both headers as part of our curl request.
# There is probably a case for ${HEADERS[*]} here.
###############
full_user_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-account/user)


###############
# Start compiling the key elements that are required to be used for a create request.
# The primary user id is required - the assumption here is that the user logging in is the primary account owner.
# If the user is a linked account, then this value will need to be discovered and passed in some way.
# Currently the only way to do that is to hard code it.
# I will work on fixing this to handle linked accounts at a later date.
#
# Other items needed for a create request are the catalogue_id and service_type parameters. 
# In essence these could be hard coded, but I decided to discover them to cater for the event that they may change in the future.
# This also allows a future iteration of this script to simply pass in the name of the service and discover the catalog_id dynamically.
#
# Take note of the jq select funtions. They can be used as examples for other requests should you want to extend this script.
###############
primary_user_id=$(echo $full_user_info | jq -r '.primary_account_id')

get_certs=$( curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-certificates/certificates/$primary_user_id)
echo $get_certs | jq -r '.certificates[]' | jq -r '.id' > $0.txt

if [ "$delete" == "true" ]
then
  while read certid; do
    echo -n $certid
    do_del=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X DELETE https://$api_url/$api_version/svc-certificates/$certid)
    echo "  $do_del"
  done < $0.txt
else
  cat $0.txt
fi

