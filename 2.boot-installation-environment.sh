#!/bin/sh

export CSM_RELEASE=1.3.0-rc.2
export USERNAME=root
export IPMI_PASSWORD=initial0



echo "download csm tarball"
echo "nameserver 172.30.84.40" >>/etc/resolv.conf
curl -C - -O "https://artifactory.algol60.net/artifactory/csm-releases/csm/$(awk -F. '{print $1"."$2}' <<< ${CSM_RELEASE})/csm-${CSM_RELEASE}.tar.gz"

echo "Extract the LiveCD from the tarball."

OUT_DIR="$(pwd)/csm-temp"
mkdir -pv "${OUT_DIR}"
tar -C "${OUT_DIR}" --wildcards --no-anchored --transform='s/.*\///' -xzvf "csm-${CSM_RELEASE}.tar.gz" 'cray-pre-install-toolkit-*.iso'

echo "Create a USB stick using the following procedure."
OUT_DIR="$(pwd)/csm-temp"
mkdir -pv "${OUT_DIR}"
tar -C "${OUT_DIR}" --wildcards --no-anchored --transform='s/.*\///' -xzvf "csm-${CSM_RELEASE}.tar.gz" 'cray-site-init-*.rpm'

echo "Install the write-livecd.sh script:"

rpm -Uvh --force ${OUT_DIR}/cray-site-init*.rpm

lsscsi
echo "Set a variable with the USB device and for the CSM_PATH:"
USB=/dev/sdd

echo "Use the CSI application to do this:"
csi pit format "${USB}" "${OUT_DIR}/"cray-pre-install-toolkit-*.iso 50000

echo "sleeping 2 mins go and and check if any isssue is there then exit"
sleep 1m

echo "Boot the LiveCD"



echo "user need to reboot the system manually select usb stick from bios menu"
exit 

