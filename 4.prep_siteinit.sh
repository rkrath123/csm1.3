#!/bin/sh


ls -1 ${PITDATA}/prep
sed -i 's/csm-version: 1.2/csm-version: 1.3/g' ${PITDATA}/prep/system_config.yaml
cd ${PITDATA}/prep && csi config init
cat ${PITDATA}/prep/${SYSTEM_NAME}/system_config.yaml

csi version


echo "check all the enviornment variable before site init"
echo -e "CSM_PATH=${CSM_PATH}\nCSM_RELEASE=${CSM_RELEASE}\nPITDATA=${PITDATA}\nSYSTEM_NAME=${SYSTEM_NAME}"
echo " Create and Initialize site-init Directory" 

SITE_INIT=${PITDATA}/prep/site-init
mkdir -pv ${SITE_INIT} 
${CSM_PATH}/shasta-cfg/meta/init.sh ${SITE_INIT}
cd "${SITE_INIT}"

echo "Create Baseline System Customizations"

yq merge -xP -i ${SITE_INIT}/customizations.yaml <(yq prefix -P "${PITDATA}/prep/${SYSTEM_NAME}/customizations.yaml" spec)
yq write -i ${SITE_INIT}/customizations.yaml spec.wlm.cluster_name "${SYSTEM_NAME}"
cp -v ${SITE_INIT}/customizations.yaml ${SITE_INIT}/customizations.yaml.prepassword
echo "Edit customization.yaml" 
cat ${SITE_INIT}/customizations.yaml



sed -i 's/{"Cray": {"Username": "root", "Password": "XXXX"}}/{"Cray": {"Username": "root", "Password": "initial0"}}/g' customizations.yaml
sed -i 's/{"SNMPUsername": "testuser", "SNMPAuthPassword": "XXXX", "SNMPPrivPassword": "XXXX"}/{"SNMPUsername": "testuser", "SNMPAuthPassword": "testpass1", "SNMPPrivPassword": "testpass2"}/g' customizations.yaml
sed -i 's/{"Username": "admn", "Password": "XXXX"}/{"Username": "admn", "Password": "admn"}/g' customizations.yaml
sed -i 's/{"Username": "root", "Password": "XXXX"}/{"Username": "root", "Password": "initial0"}/g' customizations.yaml

diff ${SITE_INIT}/customizations.yaml ${SITE_INIT}/customizations.yaml.prepassword


yq read ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray_reds_credentials.generate.data[*].args.value' | jq
yq read ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray_meds_credentials.generate.data[0].args.value' | jq
yq read ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray_hms_rts_credentials.generate.data[*].args.value' | jq

echo "Federate Keycloak with an upstream LDAP server."
LDAP=dcldap2.us.cray.com
PORT=636

echo "Load the openjdk container image."
${CSM_PATH}/hack/load-container-image.sh artifactory.algol60.net/csm-docker/stable/docker.io/library/openjdk:11-jre-slim

echo "Get the issuer certificate"
openssl s_client -showcerts -connect ${LDAP}:${PORT} </dev/null
openssl s_client -showcerts -nameopt RFC2253 -connect ${LDAP}:${PORT} </dev/null 2>/dev/null | grep issuer= | sed -e 's/^issuer=//'
openssl s_client -showcerts -nameopt RFC2253 -connect ${LDAP}:${PORT} </dev/null 2>/dev/null |
          awk '/s:emailAddress=dcops@hpe.com,CN=Data Center,OU=HPC\/MCS,O=HPE,ST=WI,C=US/,/END CERTIFICATE/' |
          awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > cacert.pem
		  
cat cacert.pem

podman run --rm -v "$(pwd):/data" \
        artifactory.algol60.net/csm-docker/stable/docker.io/library/openjdk:11-jre-slim keytool \
        -importcert -trustcacerts -file /data/cacert.pem -alias cra-data-center-ca \
        -keystore /data/certs.jks -storepass password -noprompt
		
base64 certs.jks > certs.jks.b64

cat <<EOF | yq w - 'data."certs.jks"' "$(<certs.jks.b64)" | \
    yq r -j - | ${SITE_INIT}/utils/secrets-encrypt.sh | \
    yq w -f - -i ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray-keycloak'
{
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
    "name": "keycloak-certs",
    "namespace": "services",
    "creationTimestamp": null
  },
  "data": {}
}
EOF


yq write -i ${SITE_INIT}/customizations.yaml \
         'spec.kubernetes.sealed_secrets.keycloak_users_localize.generate.data.(args.name==ldap_connection_url).args.value' \
         "ldaps://${LDAP}"
		 
yq read ${SITE_INIT}/customizations.yaml spec.kubernetes.sealed_secrets.keycloak_users_localize
yq write -i ${SITE_INIT}/customizations.yaml spec.kubernetes.services.cray-keycloak-users-localize.ldapSearchBase 'dc=dcldap,dc=dit'

yq write -s - -i ${SITE_INIT}/customizations.yaml <<EOF
- command: update
  path: spec.kubernetes.services.cray-keycloak-users-localize.localRoleAssignments
  value:
  - {"group": "employee", "role": "admin", "client": "shasta"}
  - {"group": "employee", "role": "admin", "client": "cray"}
  - {"group": "craydev", "role": "admin", "client": "shasta"}
  - {"group": "craydev", "role": "admin", "client": "cray"}
  - {"group": "shasta_admins", "role": "admin", "client": "shasta"}
  - {"group": "shasta_admins", "role": "admin", "client": "cray"}
  - {"group": "shasta_users", "role": "user", "client": "shasta"}
  - {"group": "shasta_users", "role": "user", "client": "cray"}
EOF

yq read ${SITE_INIT}/customizations.yaml spec.kubernetes.services.cray-keycloak-users-localize
echo " Generate Sealed Secrets"

${CSM_PATH}/hack/load-container-image.sh artifactory.algol60.net/csm-docker/stable/docker.io/zeromq/zeromq:v4.0.5
"${SITE_INIT}/utils/secrets-reencrypt.sh" \
    "${SITE_INIT}/customizations.yaml" \
    "${SITE_INIT}/certs/sealed_secrets.key" \
    "${SITE_INIT}/certs/sealed_secrets.crt"
${SITE_INIT}/utils/secrets-seed-customizations.sh ${SITE_INIT}/customizations.yaml



#Prepopulate LiveCD daemons configuration and NCN artifacts
cd ${PITDATA}
/root/bin/pit-init.sh

export IPMI_PASSWORD=initial0
cd $HOME && /root/bin/set-sqfs-links.sh
csi pit validate --livecd-preflight


echo " user need to deploy management node if the aboover this having no issue "
exit 

