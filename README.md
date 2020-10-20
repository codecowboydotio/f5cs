# F5 Cloud Services Examples 

# eap.sh:

This is a shell script to create a service within the F5 cloud services EAP product.
The script will create a new application endpoint and output the domain name and the CNAME required for DNS update.
It's self contained, and usage instructions are given by running without arguments.

# eap_rotate_cert.sh:

Shell script to rotate certificate for an EAP service.
The certificate and key must already be in the correct format - no conversaions are performed.

# primary_acct.sh:

This is a utility that will tell you all of the accounts a user is linked to.
This is useful when you need to identify another account that you want to operate on.
The account ID can be used as input for rotate certificates.

Example output:

Memberships
-------------
    a-aarR7     my-acct                      owner
    a-aarWA     F5 Cloud Services Demo       privileged-user
    a-aaRED     DNS Division                 owner
    a-aaGHU     F5 Demo Account              limited-user

# f5cs-dnslb.yml

This is a playbook to create and delete DNS LB objects within F5 Cloud services.
The playbook uses the F5 collection available here: https://github.com/f5devcentral/f5-ansible-cloudservices

Primarily this playbook is used by me for setting up cloud services DNS LB for demos.

There are a number of variables and techniques to make this playbook work.

## Blocks

I have used blocks in the playbook so that the same playbook can be used for various actions.
The blocks are bounded by a variable called run_type

## Variables

* **run_type:** This variable is used to determine the action that you want to take.
  * create       : Creates a DNS LB A record, pool and endpoint
    * foo
  * delete       : Deletes a DNS LB (specified by zone name)
  * create-cname : Creates a DLS LB CNAME record

* ansible_user             : F5CS username (usually an email)
* ansible_httpapi_password : Your F5CS password

```
ansible-playbook f5cs-dnslb.yml -e "ansible_httpapi_password=$pass zone_name=zone.org endpoint_name=server1 lbr_name=www endpoint_ip=1.2.3.4 pool_name=pool1 debug=true  run_type=create"
```
