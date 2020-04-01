#!/bin/bash
api_url='api.cloudservices.f5.com'
api_version='v1'
HEADERS=()
HEADERS[0]='Content-Type: application/json'

# exit codes
# 1 - usage
# 3 - no SUB found for domain
# 4 - no cert found
# 5 - cert file not found or not accessible.


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
  echo "-c certficate file"
  echo "-k key file"
  echo "-n chain file"
  echo "-t keep tempfiles"
  echo "-v verbose output"
  echo "-z VERY verbose output"
  exit 1;
}

format_cert() {
 local inputfile=$1
 while IFS= read -r line
 do
   echo -n "$line\n"
 done < $inputfile
}


###############
# The import cert function checks for the key and certificate files to make sure they exist and are readable.
# The function calls the "format_cert" function to format the certificate properly for the JSON payload.
# Essentially each line of the certificate needs to have a "\n" on the end when we PUT / POST it
###############
import_cert() {
if [ -n $cert_file ]
then 
  if [ -f $cert_file ]
  then
    NEW_CERT=$(format_cert $cert_file)
  else
    echo "$cert_file does not exist, or is not accessible"
    exit 5;
  fi
fi
if [ -f $key_file ]
then
  NEW_KEY=$(format_cert $key_file)
else
  echo "$key_file does not exist, or is not accessible"
  exit 5;
fi
if [ "$chain_file" != "none" ]
then
  if [ -f $chain_file ]
  then
    NEW_CHAIN=$(format_cert $chain_file)
  else
    echo "$chain_file does not exist, or is not accessible"
    exit 5;
  fi
else
  echo "No chain file passed as part of certificate"
fi

# Create certificate in cloud services 


[[ "$verbose" == "true" ]] && echo "Creating Certificate"

create_cert=$(curl -s -d "{\"account_id\":\"${primary_user_id}\", \"certificate\":\"${NEW_CERT}\", \"private_key\":\"${NEW_KEY}\", \"certificate_chain\":\"${NEW_CHAIN}\"}" -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X POST https://$api_url/$api_version/svc-certificates/certificates)

[[ "$very_verbose" == "true" ]] && echo "CREATE CERTIFICATE OUTPUT: $create_cert"

NEW_CERT_ID=$(echo $create_cert | jq -r '.id')
}

while getopts 'c:k:u:d:n:tvz?h' c
do
  case $c in
    d) set_var domain $OPTARG ;;
    u) set_var username $OPTARG ;;
    c) set_var cert_file $OPTARG ;;
    k) set_var key_file $OPTARG ;;
    n) set_var chain_file $OPTARG ;;
    t) keep_tempfiles=true ;;
    v) verbose=true ;;
    z) very_verbose=true ;;
    h|?) usage ;; 
  esac
done


###############
# Copy the template json file to the actual
###############

cp eap.template eap.json


###############
# Get the user to enter username and password. 
# We will use these as variables for the curl requests.
###############
[ -z "$domain" ] && usage domain
[ -z "$username" ] && usage username
#[ -z "$password" ] && usage password
[ -z $cert_file ] && usage cert_file
[ -z $key_file ] && usage key_file
[ -z $chain_file ] && chain_file=none
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

[[ "$verbose" == "true" ]] && echo "Getting Account Information"
full_user_info=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-account/user)

[[ "$very_verbose" == "true" ]] && echo "ACCOUNT INFORMATION: $full_user_info"

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



###############
# Get all subscriptions
# This helps me seach and do some validation.
# Could probably also have used the limiter ?type but I felt like using jq some more.
###############
[[ "$verbose" == "true" ]] && echo "Getting Subscription Information"
list_subscriptions=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-subscription/subscriptions?account_id=$primary_user_id)
[[ "$very_verbose" == "true" ]] && echo "SUBSCRIPTION INFO: $list_subscriptions"


###############
# This was super fun to do
# Use the list of subscriptions that I receved above
# Use jq to select one of type "waf" with a domain that matches our target domain.
# Pass all of this information into an array via the use of "readarray".
# Then I split each item that I've pulled out of the JSON into variables, so that I can access each variable individually.
# I could leave them in the array, but so my brain didn't melt, I decided to put them into individual variables.
# It was at this point I decided to randomly continue captializing my global variables - just for extra confusion.
# I then use the variables to perform some basic validation that a subscription with the domain and so on exist.
# Again I could have done this with jq, but for readability and 'just because' I decided to use variables.
###############
readarray -t arr < <(echo $list_subscriptions | jq -r --arg dom "$domain" '.subscriptions[] | select(.service_type=="waf" and .configuration.details.fqdn==$dom) | .subscription_id, .configuration.waf_service.application.https.tls.certificate_id, .service_type')

SUB_ID="${arr[0]}"
ASSOCIATED_CERT_SUB="${arr[1]}"
SERVICE_TYPE="${arr[2]}"

if [ -z $SUB_ID ]
then
  echo "$domain does not exist"
  exit 3;
fi

if [ $ASSOCIATED_CERT_SUB == "null" ]
then
  echo "$domain does not currently have a certificate associated with it"
  exit 4;
fi


###############
# Import the cert and key
# TODO: extend function to handle a chain
###############
[[ "$verbose" == "true" ]] && echo "Importing Certificate and Key"
import_cert $cert_file $key_file $chain_file

echo
echo "Original certificate ID: $ASSOCIATED_CERT_SUB"
echo "New certificate ID: $NEW_CERT_ID"
echo

###############
# This section grabs my current sub - probably redundant as I already have the information in another variable.
# I then walk through searching for the tokens that I need in order to build out a body that I send as part of an update request.
# For an update request I need the service_instance_name, service_type (I did re-use that) and the new body.
###############
tempfile=$(mktemp)
tempfile2=$(mktemp)
jsonfile=$(mktemp)
[[ "$verbose" == "true" ]] && echo "Getting Individual Subscription"
curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" -X GET https://$api_url/$api_version/svc-subscription/subscriptions/$SUB_ID | jq . > $tempfile
[[ "$very_verbose" == "true" ]] && echo "INDIVIDUAL SUBSCRIPTION: `cat $tempfile`"

[[ "$verbose" == "true" ]] && echo "Getting Service Instance Name"
SERVICE_INSTANCE_NAME=$(jq -r '.service_instance_name' $tempfile)

[[ "$verbose" == "true" ]] && echo "Updating Certificate Name"
jq --arg new_cert_id "$NEW_CERT_ID" '.configuration.waf_service.application.https.tls.certificate_id = $new_cert_id' $tempfile > $tempfile2

###############
# This section creates the JSON payload for my request.
# The examples I looked at to do this have a JSON body that is similar to that of the 'JSON' section in the portal.
# This is less than the information returned from the "GET SubscriptionService" API in that it's a sub-section of this.
# It's also not quite enough to just PUT this information into an API request 
# You need additional fields. (service_instance_name and _service_type) as examples.
# The jq snippet below builds out the outer sections of waf_service and configuration that are required as part of the PUT request.
# It also puts in service_instance_name and service_type that are also required. 
###############
[[ "$verbose" == "true" ]] && echo "Creating JSON payload for update request"
jq -r --arg service_type "$eap_service_type" --arg service_instance_name "$SERVICE_INSTANCE_NAME" '.configuration.waf_service | {waf_service: .} | {service_type: $service_type, service_instance_name: $service_instance_name, configuration: .}' $tempfile2 > $jsonfile
[[ "$very_verbose" == "true" ]] && echo "JSON PAYLOAD: `cat $jsonfile`"


###############
# Let's update the service instance with the correct information and new certificate. 
###############
[[ "$verbose" == "true" ]] && echo "Updating Subscription with new certificate"
update_command=$(curl -s -H "${HEADERS[0]}" -H "${HEADERS[1]}" --data "@${jsonfile}" -X PUT https://$api_url/$api_version/svc-subscription/subscriptions/$SUB_ID)
[[ "$very_verbose" == "true" ]] && echo "UPDATE OUTPUT: $update_command"

###############
# Clean up all my temporary files - be a good citizen!
###############
if [ "$keep_tempfiles" == "true" ]
then
  echo "Leaving tempfiles in place"
  echo "tempfile is $tempfile"
  echo "tempfile2 is $tempfile2"
  echo "jsonfile is $jsonfile"
else
  echo "Cleaning up temporary files"
  rm -rf $tempfile $tempfile2 $jsonfile
fi
