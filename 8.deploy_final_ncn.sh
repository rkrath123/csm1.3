#!/bin/sh


RESULT=`kubectl get pods -A | grep -e ceph -e cray-bss -e cray-dhcp-kea -e cray-dns-unbound -e cray-ipxe -e cray-sls -e cray-tftp | grep -v "Completed\|Running"`
#echo $RESULT
if  [ -z "$RESULT" ]

then
    echo "pods cray-bss -e cray-dhcp-kea -e cray-dns-unbound -e cray-ipxe -e cray-sls -e cray-tftp  running properly"
else
    echo "pods - $RESULT  not running properly"
exit
fi

echo "Upload SLS file."
csi upload-sls-file --sls-file "${PITDATA}/prep/${SYSTEM_NAME}/sls_input_file.json"

echo "Upload NCN boot artifacts into S3."
set -o pipefail
kubernetes_rootfs="$(readlink -f /var/www/ncn-m002/rootfs)" &&
kubernetes_initrd="$(readlink -f /var/www/ncn-m002/initrd.img.xz)"  &&
kubernetes_kernel="$(readlink -f /var/www/ncn-m002/kernel)"  &&
kubernetes_version="$(basename ${kubernetes_rootfs} .squashfs | awk -F '-' '{print $NF}')" &&
ceph_rootfs="$(readlink -f /var/www/ncn-s001/rootfs)" &&
ceph_initrd="$(readlink -f /var/www/ncn-s001/initrd.img.xz)" &&
ceph_kernel="$(readlink -f /var/www/ncn-s001/kernel)" &&
ceph_version="$(basename ${ceph_rootfs} .squashfs | awk -F '-' '{print $NF}')" &&
cray artifacts create boot-images "k8s/${kubernetes_version}/rootfs" "${kubernetes_rootfs}" &&
cray artifacts create boot-images "k8s/${kubernetes_version}/initrd" "${kubernetes_initrd}" &&
cray artifacts create boot-images "k8s/${kubernetes_version}/kernel" "${kubernetes_kernel}" &&
cray artifacts create boot-images "ceph/${ceph_version}/rootfs" "${ceph_rootfs}" &&
cray artifacts create boot-images "ceph/${ceph_version}/initrd" "${ceph_initrd}" &&
cray artifacts create boot-images "ceph/${ceph_version}/kernel" "${ceph_kernel}" && echo SUCCESS


echo " Get a token to use for authenticated communication with the gateway."
export TOKEN=$(curl -k -s -S -d grant_type=client_credentials -d client_id=admin-client \
                -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
                https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token | jq -r '.access_token')


echo "Upload the data.json file to BSS, the cloud-init data source."
kubernetes_rootfs="$(readlink -f /var/www/ncn-m002/rootfs)" &&
ceph_rootfs="$(readlink -f /var/www/ncn-s001/rootfs)" &&
csi handoff bss-metadata \
    --data-file "${PITDATA}/configs/data.json" \
    --kubernetes-file "${kubernetes_rootfs}" \
    --storage-ceph-file "${ceph_rootfs}" && echo SUCCESS

echo " Patch the metadata for the Ceph nodes to have the correct run commands."
python3 /usr/share/doc/csm/scripts/patch-ceph-runcmd.py
csi handoff bss-update-cloud-init --set meta-data.dns-server="10.92.100.225 10.94.100.225" --limit Global


echo "setting boot order and trimming boot order"
system_platform=`ipmitool fru | grep "Board Mfg" | tail -n 1  | awk '{print $4}'`

if [[ $system_platform == 'Gigabyte' ]]
then
efibootmgr | grep -iP '(pxe ipv?4.*adapter)' | tee /tmp/bbs1
efibootmgr | grep -i cray | tee /tmp/bbs2
efibootmgr -o $(cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | tr -t '\n' ',' | sed 's/,$//') | grep -i bootorder
cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | xargs -r -t -i efibootmgr -b {} -a
efibootmgr | grep -ivP '(pxe ipv?4.*)' | grep -iP '(adapter|connection|nvme|sata)' | tee /tmp/rbbs1
efibootmgr | grep -iP '(pxe ipv?4.*)' | grep -i connection | tee /tmp/rbbs2
cat /tmp/rbbs* | awk '!x[$0]++' | sed 's/^Boot//g' | awk '{print $1}' | tr -d '*' | xargs -r -t -i efibootmgr -b {} -B

elif [[ $system_platform == 'Intel' ]]
then
efibootmgr | grep -i 'ipv4' | grep -iv 'baseboard' | tee /tmp/bbs1
efibootmgr | grep -i cray | tee /tmp/bbs2
efibootmgr -o $(cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | tr -t '\n' ',' | sed 's/,$//') | grep -i bootorder
cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | xargs -r -t -i efibootmgr -b {} -a
efibootmgr | grep -vi 'ipv4' | grep -iP '(sata|nvme|uefi)' | tee /tmp/rbbs1
efibootmgr | grep -i baseboard | tee /tmp/rbbs2
cat /tmp/rbbs* | awk '!x[$0]++' | sed 's/^Boot//g' | awk '{print $1}' | tr -d '*' | xargs -r -t -i efibootmgr -b {} -B

elif [[ $system_platform == 'HPE' ]]
then
efibootmgr | grep -i 'port 1' | grep -i 'pxe ipv4' | tee /tmp/bbs1
efibootmgr | grep -i cray | tee /tmp/bbs2
efibootmgr -o $(cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | tr -t '\n' ',' | sed 's/,$//') | grep -i bootorder
cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | xargs -r -t -i efibootmgr -b {} -a
efibootmgr | grep -vi 'pxe ipv4' | grep -i adapter |tee /tmp/rbbs1
efibootmgr | grep -iP '(sata|nvme)' | tee /tmp/rbbs2
cat /tmp/rbbs* | awk '!x[$0]++' | sed 's/^Boot//g' | awk '{print $1}' | tr -d '*' | xargs -r -t -i efibootmgr -b {} -B

else
echo "No platform match"
fi

echo " Tell the PIT node to PXE boot on the next boot"


echo "Tell the PIT node to PXE boot on the next boot."
efibootmgr -n $(efibootmgr | grep -Ei "ip(v4|4)" | awk '{print $1}' | head -n 1 | tr -d Boot*) | grep -i bootnext



echo "Get m002 IP address"
ssh ncn-m002 ip -4 a show bond0.cmn0 | grep inet | awk '{print $2}' | cut -d / -f1
sleep 1m
echo "==============login to m002 in a different session and monitor =========="



echo " take back up in m002 and m003"


ssh ncn-m002 cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys &&
    chmod 600 /root/.ssh/authorized_keys


echo "Preserve logs and configuration files if desired."
mkdir -pv "${PITDATA}"/prep/logs &&
     ls -d \
        /etc/dnsmasq.d \
        /etc/os-release \
        /etc/sysconfig/network \
        /opt/cray/tests/cmsdev.log \
        /opt/cray/tests/install/logs \
        /opt/cray/tests/logs \
        /root/.canu \
        /root/.config/cray/logs \
        /root/csm*.{log,txt} \
        /tmp/*.log \
        /usr/share/doc/csm/install/scripts/csm_services/yapl.log \
        /var/log/conman \
        /var/log/zypper.log 2>/dev/null |
     sed 's_^/__' |
     xargs tar -C / -czvf "${PITDATA}/prep/logs/pit-backup-$(date +%Y-%m-%d_%H-%M-%S).tgz"


echo "Copy some of the installation files to ncn-m002"

ssh ncn-m002 \
    "mkdir -pv /metal/bootstrap
     rsync -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' -rltD -P --delete pit.nmn:'${PITDATA}'/prep /metal/bootstrap/
     rsync -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' -rltD -P --delete pit.nmn:'${CSM_PATH}'/cray-pre-install-toolkit*.iso /metal/bootstrap/"


echo "Upload install files to S3 in the cluster."

PITBackupDateTime=$(date +%Y-%m-%d_%H-%M-%S)
tar -czf "${PITDATA}/PitPrepIsoConfigsBackup-${PITBackupDateTime}.tgz" "${PITDATA}/prep" "${PITDATA}/configs" "${CSM_PATH}/cray-pre-install-toolkit"*.iso &&
cray artifacts create config-data \
    "PitPrepIsoConfigsBackup-${PITBackupDateTime}.tgz" \
    "${PITDATA}/PitPrepIsoConfigsBackup-${PITBackupDateTime}.tgz" &&
rm -v "${PITDATA}/PitPrepIsoConfigsBackup-${PITBackupDateTime}.tgz" && echo COMPLETED



echo "==============Reboot the pit node and do conman connection to m001 node of the cluster through csm pit server=========="

echo "==============continue manually till m001 deployed successfully and complete till step 4. Automation will start from step 5: Enable NCN disk wiping safeguard =========="
exit

