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

