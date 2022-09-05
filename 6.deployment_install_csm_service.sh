#!bin/sh


echo " At this point all the management nodes deployed successfuly and it should join in the cluster "
echo " run kubectl get nodes command in ncn-m002"
FM=$(cat "${PITDATA}"/configs/data.json | jq -r '."Global"."meta-data"."first-master-hostname"')
echo ${FM}


mkdir -v ~/.kube
scp "${FM}.nmn:/etc/kubernetes/admin.conf" ~/.kube/config

cd "${PITDATA}/prep"


echo "run lvm test"
/usr/share/doc/csm/install/scripts/check_lvm.sh


sleep 1m

echo " run goss test"
"${CSM_PATH}"/lib/install-goss-tests.sh



pdsh -b -S -w "$(grep -oP 'ncn-\w\d+' /etc/dnsmasq.d/statics.conf | grep -v m001 | sort -u |  tr -t '\n' ',')" \
        'sed -i "s/^! pool pool\.ntp\.org.*//" /etc/chrony.conf' && echo SUCCESS


echo " validate deployments"
csi pit validate --ceph
csi pit validate --k8s

echo "Starting  Install CSM services"

rpm -Uvh "${CSM_PATH}"/rpm/cray/csm/sle-15sp2/x86_64/yapl-*.x86_64.rpm
pushd /usr/share/doc/csm/install/scripts/csm_services
yapl -f install.yaml execute  >> yapl.log



RESULT=$(grep "error" yapl.log)
if [[ -z $RESULT ]]
then
echo "Install CSM service completed successfully"
else
echo "EXIT in install csm service due to error"
exit
fi

popd

kubectl -n services rollout status deployment cray-bss
export TOKEN=$(curl -k -s -S -d grant_type=client_credentials \
                       -d client_id=admin-client \
                       -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
                       https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token | jq -r '.access_token')
                                              
curl -i -k -H "Authorization: Bearer ${TOKEN}" -X PUT \
         https://api-gw-service-nmn.local/apis/bss/boot/v1/bootparameters \
         --data '{"hosts":["Global"]}'
         
SPIRE_JOB=$(kubectl -n spire get jobs -l app.kubernetes.io/name=spire-update-bss -o name)



kubectl -n spire get "${SPIRE_JOB}" -o json | jq 'del(.spec.selector)' \
         | jq 'del(.spec.template.metadata.labels."controller-uid")' \
         | kubectl replace --force -f -
         
kubectl -n spire wait "${SPIRE_JOB}" --for=condition=complete --timeout=5m
exit
