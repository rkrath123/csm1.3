#!/bin/sh

export USERNAME=root
export IPMI_PASSWORD=initial0
export  mtoken='ncn-m(?!001)\w+-mgmt' ; stoken='ncn-s\w+-mgmt' ; wtoken='ncn-w\w+-mgmt'

echo "bios baseline"
/root/bin/bios-baseline.sh

echo "Check power status of all NCNs."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power status
	  
echo "Power off all NCNs."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off
	  
	  
echo "Clear CMOS; ensure default settings are applied to all NCNs."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev none options=clear-cmos
	  
echo "Boot NCNs to BIOS to allow the CMOS to reinitialize."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev bios options=efiboot
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power on
	  
sleep 2m

/root/bin/bios-baseline.sh

echo " Power off the nodes."

grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
      xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off
	  
echo "Deploy management nodes"

grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u | xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev pxe options=persistent
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u | xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev pxe options=efiboot
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u | xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off

echo "Deploy storage NCNs"
grep -oP "${stoken}" /etc/dnsmasq.d/statics.conf | sort -u | xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power on 


echo "monitor storage node deploy process then start master and worker node deploy process"
exit

