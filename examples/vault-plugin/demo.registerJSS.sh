#!/bin/bash

#ibmcloud plugin install cloud-object-storage
export PLUGIN="vault-plugin-auth-ti-jwt"

## create help menu:
helpme()
{
  cat <<HELPMEHELPME

Syntax: ${0} <token> <vault_addr>
Where:
  token      - vault root token to setup the plugin
  vault_addr - vault address in format http://vault.server:8200

HELPMEHELPME
}

setupVault()
{
  echo "Root Token: ${ROOT_TOKEN}"
  vault login ${ROOT_TOKEN}
  # remove any previously set VAULT_TOKEN, that overrides ROOT_TOKEN in Vault client
  export VAULT_TOKEN=

  # Obtain the CSR from vTPM. Connect to any container deployed in `trusted-identity`
  # namespace and get it using `curl http://vtpm-service:8012/getCSR` vtpm.csr

  #vault write pki/root/sign-intermediate csr=@vtpm.csr format=pem_bundle ttl=43800h

  vault write pki/root/sign-intermediate csr=@vtpm.csr format=pem_bundle ttl=43800h -format=json > out
  CERT=$(cat out | jq -r '.["data"].certificate' | grep -v '\-\-\-')
  CHAIN=$(cat out | jq -r '.["data"].issuing_ca' | grep -v '\-\-\-')
  echo "[\"${CERT}\",\"${CHAIN}\"]" > x5c

  cat x5c

  # Take both output certificates, comma separated move to JSS as 'x5c' format:
  # based on spec: https://tools.ietf.org/html/rfc7515#appendix-B
  # ["MIIE3jCCA8agAwIBAgICAwEwDQYJKoZIhvcNAQEFBQAwYzELMAkGA1UEBhMCVVM
  #   ...
  #   H0aBsXBTWVU+4=","MIIE+zCC....wCW/POuZ6lcg5Ktz885hZo+L7tdEy8W9ViH0Pd"]
  }

if [ ! "$1" == "" ] ; then
  export ROOT_TOKEN=$1
fi
if [ ! "$2" == "" ] ; then
  export VAULT_ADDR=$2
fi

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] ; then
  helpme
#check if token exists:
elif [[ "$ROOT_TOKEN" == "" || "$VAULT_ADDR" == "" ]] ; then
  echo "ROOT_TOKEN or VAULT_ADDR not set"
  helpme
else
  setupVault $1 $2
fi
