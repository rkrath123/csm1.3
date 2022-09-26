#!/bin/sh



export SW_ADMIN_PASSWORD=!nitial0
echo " Install latest docs on ncn-m001"
rpm -Uvh --force https://artifactory.algol60.net/artifactory/csm-rpms/hpe/stable/sle-15sp2/docs-csm/1.3/noarch/docs-csm-latest.noarch.rpm



echo " =============== Running Final Validation  ==========="



echo " Run the NCN and Kubernetes health checks."
/opt/cray/tests/install/ncn/automated/ncn-k8s-combined-healthcheck  >ncn_health.log # if any failed then exit and monitor the logs



RESULT=$(grep "0 failed" ncn_health.log)
if grep -q "0 failed" <<< "$RESULT"; then
echo "ncn health check  completed sucessfully"
else
echo "Exit due to errors"
exit
fi



/opt/cray/platform-utils/ncnHealthChecks.sh -s ncn_uptimes
/opt/cray/platform-utils/ncnHealthChecks.sh -s node_resource_consumption
/opt/cray/platform-utils/ncnHealthChecks.sh -s pods_not_running


echo " Run HMS CT test"
/opt/cray/csm/scripts/hms_verification/run_hms_ct_tests.sh >hms_logs



RESULT1=$(grep "FAILED" hms_logs)
if grep -q "FAILED" <<< "$RESULT1"; then
echo "Exit due to errors"
exit
else
echo "hms CT test completed sucessfully"
fi



echo " HMS discovery test"
/opt/cray/csm/scripts/hms_verification/hsm_discovery_status_test.sh
/opt/cray/csm/scripts/hms_verification/verify_hsm_discovery.py




echo " SMS health check "
/usr/local/bin/cmsdev test -q all >cms_logs
RESULT2=$(grep "FAILED" cms_logs)
if grep -q "FAILED" <<< "$RESULT2"; then
echo "Exit due to errors"
exit
else
echo "CMS dev test completed sucessfully"
fi



echo " Gateway test  manual intervention needed please monitor the screen "
/usr/share/doc/csm/scripts/operations/gateway-test/ncn-gateway-test.sh >gateway_logs
RESULT3=$(grep "Overall Gateway Test Status:  PASS" gateway_logs)
if grep -q "Overall Gateway Test Status:  PASS" <<< "$RESULT3"; then
echo "Gateway test completed sucessfully"
else
echo "Exit due to errors"
exit
fi



echo " ssh access test execution:  manual intervention needed please monitor the screen "
/usr/share/doc/csm/scripts/operations/pyscripts/start.py test_bican_internal >ssh_logs
RESULT4=$(grep "Overall status: PASSED" ssh_logs)
if grep -q "Overall status: PASSED" <<< "$RESULT4"; then
echo "ssh access test completed sucessfully"
else
echo "Exit due to errors"
exit
fi




echo " Bare boneboot test "
/opt/cray/tests/integration/csm/barebonesImageTest >barebone.logs
RESULT5=$(grep " Successfully completed barebones image boot test" barebone.logs)
if grep -q "Successfully completed barebones image boot test" <<< "$RESULT5"; then
echo "Barebone test completed sucessfully"
else
echo "Exit due to errors"
exit
fi



echo "UAS UAI test "
cray uas mgr-info list --format toml
cray uas list --format toml
cray uas images list --format toml
cray uas create --publickey ~/.ssh/id_rsa.pub --format toml
#read -p "Press enter to continue"
sleep 30s
cray uas list --format toml
UAINAME=`cray uas list --format toml  | grep uai_name | awk '{print $3}'`
echo $UAINAME
res=`cray uas list --format toml | grep uai_connect_string |  awk '{print $4}' | sed  's/vers@//' | sed  's/"//'`
echo $res
ssh-keygen -R $res -f /root/.ssh/known_hosts
ssh -o "StrictHostKeyChecking no" vers@$res << EOF
  echo "inside container"
  ps -afe
EOF
cray uas delete --uai-list $UAINAME --format toml




echo " Test UAI gateway health"
/usr/share/doc/csm/scripts/operations/gateway-test/uai-gateway-test.sh >uai_gateway_test.logs
RESULT5=$(grep " Successfully deleted" uai_gateway_test.logs)
if grep -q "Successfully deleted" <<< "$RESULT5"; then
echo "uai gateway test completed sucessfully"
else
echo "Exit due to errors"
exit
fi


elif [[ $press == 'n' ]]
then
        echo "go and ssh to ncn-m002 then run the script"
        exit
else
        echo "invalid choice"
        exit

fi
