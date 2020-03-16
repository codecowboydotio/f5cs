#!/bin/bash

api_url='api.cloudservices.f5.com'
api_version='v1'
aws_region='ap-southeast-2'
debug='false'
#cert_id='cert-aa6sBXoygP'
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
  echo "-d domain name"
  echo "-u username"
  echo "-p password"
  echo "-c cert id"
  exit 1;
}

while getopts 'c:u:d:?h' c
do
  case $c in
    d) set_var domain $OPTARG ;;
    u) set_var username $OPTARG ;;
    c) set_var cert_id $OPTARG ;;
    h|?) usage ;; 
  esac
done


###############
# Copy the template json file to the actual
###############

cp eap.template eap.json


###############
#Get the user to enter username and password. 
#We will use these as variables for the curl requests.
###############
read -s -p "Please enter your password " password

[ -z "$cert_id" ] && usage cert_id
[ -z "$domain" ] && usage domain
[ -z "$username" ] && usage username
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
full_catalogue_items=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-catalog/catalogs)
eap_catalog_id=$(echo $full_catalogue_items | jq -r '.Catalogs[] | select(true) | select(.name|test("Essential App Protect")) | .catalog_id')
eap_service_type=$(echo $full_catalogue_items | jq -r '.Catalogs[] | select(true) | select(.name|test("Essential App Protect")) | .service_type')

tempfile=$(mktemp)
jq --arg dom "$domain" '.configuration.waf_service.application.fqdn = $dom' eap.json > $tempfile && mv $tempfile eap.json
jq --arg serv_typ "$eap_service_type" '.service_type = $serv_typ' eap.json > $tempfile && mv $tempfile eap.json
jq --arg acct_id "$primary_user_id" '.account_id = $acct_id' eap.json > $tempfile && mv $tempfile eap.json
jq --arg cert "$cert_id" '.configuration.waf_service.application.https.tls.certificate_id = $cert' eap.json > $tempfile && mv $tempfile eap.json
jq --arg dom "$domain" '.configuration.waf_service.application.waf_regions.aws."ap-southeast-2".endpoint.dns_name = $dom' eap.json > $tempfile && mv $tempfile eap.json
jq --arg svc_i_nm "$domain" '.service_instance_name = $svc_i_nm' eap.json > $tempfile && mv $tempfile eap.json
jq --arg cat_id "$eap_catalog_id" '.catalog_id = $cat_id' eap.json > $tempfile

create_service_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" --data "@${tempfile}" -X POST https://$api_url/$api_version/svc-subscription/subscriptions)
new_sub_id=$(echo $create_service_info | jq -r '.subscription_id')
echo "A New subscription has been created $new_sub_id"

activate_new_sub=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}"  -X POST https://$api_url/$api_version/svc-subscription/subscriptions/"${new_sub_id}"/activate)
#sleep 10
new_sub_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}"  -X GET https://$api_url/$api_version/svc-subscription/subscriptions/"${new_sub_id}")
cname=$(echo $new_sub_info | jq -r '.configuration.details.CNAMEValue')
echo "CNAME: $cname"

rm $tempfile
