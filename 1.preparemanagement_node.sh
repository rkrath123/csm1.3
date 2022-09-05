#!/bin/sh
#prepare management node
#Pre req- All the NCN should be up and ssh connection should be working from master  node 1

host_name=`hostname | grep pit`
system_platform=`ipmitool fru | grep "Board Mfg" | tail -n 1  | awk '{print $4}'`


echo "Disable dhcp service"
kubectl scale -n services --replicas=0 deployment cray-dhcp-kea
export username=root
export IPMI_PASSWORD=initial0 



echo "get the inventory from ncns"
#get the inventory from pit will get later
#readarray BMCS < <(grep mgmt /etc/hosts | awk '{print $NF}' | grep -v m001 | sort -u)
BMCS=$(grep -wEo "ncn-[msw][0-9]{3}-mgmt" /etc/hosts | grep -v "m001" | sort -u | tr '\n' ' ') ; echo $BMCS

echo "Power status NCNs."
printf "%s\n" ${BMCS[@]} | xargs -t -i ipmitool -I lanplus -U "${username}" -E -H {} power status

echo "Power off  NCNs."
printf "%s\n" ${BMCS[@]} | xargs -t -i ipmitool -I lanplus -U "${username}" -E -H {} power off

echo "Power status NCNs."
printf "%s\n" ${BMCS[@]} | xargs -t -i ipmitool -I lanplus -U "${username}" -E -H {} power status

echo "Set node BMCs to DHCP"

echo "Get the inventory of BMCs."

readarray BMCS < <(grep mgmt /etc/hosts | awk '{print $NF}' | grep -v m001 | sort -u)

echo "Set the BMCs to DHCP."
function bmcs_set_dhcp {
   local lan=1
   for bmc in ${BMCS[@]}; do
      # by default the LAN for the BMC is lan channel 1, except on Intel systems.
      if ipmitool -I lanplus -U "${username}" -E -H "${bmc}" lan print 3 2>/dev/null; then
         lan=3
      fi
      printf "Setting %s to DHCP ... " "${bmc}"
      if ipmitool -I lanplus -U "${username}" -E -H "${bmc}" lan set "${lan}" ipsrc dhcp; then
         echo "Done"
      else
         echo "Failed!"
      fi
   done
}
bmcs_set_dhcp

echo "Perform a cold reset of any BMCs which are still reachable."

function bmcs_cold_reset {
  for bmc in ${BMCS[@]}; do
     printf "Setting %s to DHCP ... " "${bmc}"
     if ipmitool -I lanplus -U "${username}" -E -H "${bmc}" mc reset cold; then
        echo "Done"
     else
        echo "Failed!"
     fi
  done
}
bmcs_cold_reset

