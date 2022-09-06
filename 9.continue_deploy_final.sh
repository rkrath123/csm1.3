
#!/bin/sh
export USERNAME=root
export IPMI_PASSWORD=initial0


echo  "Deploy final NCN continue"
echo  "Enable NCN disk wiping safeguard"
mkdir -pv /mnt/livecd /mnt/rootfs /mnt/sqfs && \
    mount -v /metal/bootstrap/cray-pre-install-toolkit-*.iso /mnt/livecd/ && \
    mount -v /mnt/livecd/LiveOS/squashfs.img /mnt/sqfs/ && \
    mount -v /mnt/sqfs/LiveOS/rootfs.img /mnt/rootfs/ && \
    cp -pv /mnt/rootfs/usr/bin/csi /tmp/csi && \
    /tmp/csi version && \
    umount -vl /mnt/sqfs /mnt/rootfs /mnt/livecd
export TOKEN=$(curl -k -s -S -d grant_type=client_credentials -d client_id=admin-client \
                -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
                https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token | jq -r '.access_token')
/tmp/csi handoff bss-update-param --set metal.no-wipe=1



echo" Remove the default NTP pool"
sed -i "s/^! pool pool\.ntp\.org.*//" /etc/chrony.conf



echo" Configure DNS and NTP on each BMC"



system_platform=`ipmitool mc info | grep "Hewlett Packard Enterprise"  | cut -d ':' -f 2`


if [[ $system_platform == 'Hewlett Packard Enterprise' ]]
then
ipmitool mc info | grep "Hewlett Packard Enterprise" || echo "Not HPE hardware -- SKIP these steps"
readarray BMCS < <(grep mgmt /etc/hosts | awk '{print $NF}' | grep -v m001 | sort -u | tr '\n' ' ')
for BMC in ${BMCS[@]}; do echo ${BMC}; done
NMN_DNS=$(kubectl get services -n services -o wide | grep cray-dns-unbound-udp-nmn | awk '{ print $4 }'); echo ${NMN_DNS}

HMN_DNS=$(kubectl get services -n services -o wide | grep cray-dns-unbound-udp-hmn | awk '{ print $4 }'); echo ${HMN_DNS}
for BMC in ${BMCS[@]}; do
    echo "${BMC}: Disabling DHCP and configure NTP on the BMC using data from unbound service"
    /opt/cray/csm/scripts/node_management/set-bmc-ntp-dns.sh ilo -H "${BMC}" -S -n
    echo
    echo "${BMC}: Configuring DNS on the BMC using data from unbound"
    /opt/cray/csm/scripts/node_management/set-bmc-ntp-dns.sh ilo -H "${BMC}" -D "${NMN_DNS},${HMN_DNS}" -d
    echo
    echo "${BMC}: Showing settings"
    /opt/cray/csm/scripts/node_management/set-bmc-ntp-dns.sh ilo -H "${BMC}" -s
    echo
done ; echo "Configuration completed on all NCN BMCs"

fi





echo " Start Configure Administrative Access"

echo "Configure cray CLI"



cray init --hostname api-gw-service-nmn.local # enter vers and diet.pepsi automation needed



echo " Set BMC management Role"
  # check for running and completed
RESULT=`kubectl -n services get pods | grep smd | grep -v "Completed\|Running"`
#echo $RESULT
if  [ -z "$RESULT" ]

then
    echo "pods are  running properly"
else
    echo "pods - $RESULT  not running properly"
exit
fi



BMCList=$(cray hsm state components list --role Management --type Node --format json | jq -r .Components[].ID | \
             sed 's/n[0-9]*//' | tr '\n' ',' | sed 's/.$//')
echo ${BMCList}
cray hsm state components bulkRole update --role Management --component-ids "${BMCList}"



echo " lock management Nodes"
/opt/cray/csm/scripts/admin_access/lock_management_nodes.py



echo " Running NCN personalization"


echo " Configure the root password and SSH keys in Vault"


/usr/share/doc/csm/scripts/operations/configuration/write_root_secrets_to_vault.py


echo " Perform NCN personaization script"


/usr/share/doc/csm/scripts/operations/configuration/apply_csm_configuration.sh
