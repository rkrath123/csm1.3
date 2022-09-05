#!/bin/sh

echo "user need to perform subsection 1.3 - step 1 ,2nd ,3rd step from  https://github.com/Cray-HPE/docs-csm/blob/release/1.3/install/pre-installation.md#1-boot-installation-environment "
echo "for fanta"
#pit:~ # site_ip=172.30.52.72/20
#pit:~ # site_gw=172.30.48.1
#pit:~ # site_dns=172.30.84.40
#pit:~ # site_nics=emo1
#pit:~ # site_nics=em1

echo "Prepare the data partition"
mount -vL PITDATA

export CSM_RELEASE=1.3.0-rc.2
export PITDATA="$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)"
export CSM_PATH="${PITDATA}/csm-${CSM_RELEASE}"
export SYSTEM_NAME=fanta

echo "Set /etc/environment."

cat << EOF >/etc/environment
CSM_RELEASE=${CSM_RELEASE}
CSM_PATH=${PITDATA}/csm-${CSM_RELEASE}
GOSS_BASE=${GOSS_BASE}
PITDATA=${PITDATA}
SYSTEM_NAME=${SYSTEM_NAME}
EOF


mkdir -pv "$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)/prep/admin"
ls -l "$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)/prep/admin"

/root/bin/metalid.sh

echo "Import CSM tarball"
curl -C - -o "/var/www/ephemeral/csm-${CSM_RELEASE}.tar.gz" \
  "https://artifactory.algol60.net/artifactory/csm-releases/csm/$(awk -F. '{print $1"."$2}' <<< ${CSM_RELEASE})/csm-${CSM_RELEASE}.tar.gz"
  
echo "Extract the tarball."
tar -zxvf  "${PITDATA}/csm-${CSM_RELEASE}.tar.gz" -C ${PITDATA}

echo "Install/update the RPMs necessary for the CSM installation."
zypper \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp2/" \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp3/" \
    --no-gpg-checks \
    install -y docs-csm
	
echo "Update cray-site-init."
zypper \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp2/" \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp3/" \
    --no-gpg-checks \
    update -y cray-site-init
	

echo "Install csm-testing RPM."
zypper \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp2/" \
    --plus-repo "${CSM_PATH}/rpm/cray/csm/sle-15sp3/" \
    --no-gpg-checks \
    install -y csm-testing
	
echo "Get the artifact versions."

KUBERNETES_VERSION="$(find ${CSM_PATH}/images/kubernetes -name '*.squashfs' -exec basename {} .squashfs \; | awk -F '-' '{print $NF}')"
CEPH_VERSION="$(find ${CSM_PATH}/images/storage-ceph -name '*.squashfs' -exec basename {} .squashfs \; | awk -F '-' '{print $NF}')"

echo " Copy the NCN images from the expanded tarball."

mkdir -pv "${PITDATA}/data/k8s/" "${PITDATA}/data/ceph/"
rsync -rltDP --delete "${CSM_PATH}/images/kubernetes/" --link-dest="${CSM_PATH}/images/kubernetes/" "${PITDATA}/data/k8s/${KUBERNETES_VERSION}"
rsync -rltDP --delete "${CSM_PATH}/images/storage-ceph/" --link-dest="${CSM_PATH}/images/storage-ceph/" "${PITDATA}/data/ceph/${CEPH_VERSION}"


echo "Generate SSH keys."

#ssh-keygen -N "" -t rsa
ssh-keygen  -t rsa -f /root/.ssh/id_rsa   -N "" 
echo "Export the password hash for root that is needed for the ncn-image-modification.sh script."
#export SQUASHFS_ROOT_PW_HASH="$(awk -F':' /^root:/'{print $2}' < /etc/shadow)"


echo "Inject these into the NCN images by running ncn-image-modification.sh from the CSM documentation RPM."

PW1=initial0
PW2=initial0

NCN_MOD_SCRIPT=$(rpm -ql docs-csm | grep ncn-image-modification.sh)

export SQUASHFS_ROOT_PW_HASH=$(echo -n "${PW1}" | openssl passwd -6 -salt $(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c4) --stdin)
             [[ -n ${SQUASHFS_ROOT_PW_HASH} ]] && echo "Password hash set and exported" || echo "ERROR: Problem generating hash"
			 
echo "${NCN_MOD_SCRIPT}"
"${NCN_MOD_SCRIPT}" -p \
   -d /root/.ssh \
   -k "/var/www/ephemeral/data/k8s/${KUBERNETES_VERSION}/kubernetes-${KUBERNETES_VERSION}.squashfs" \
   -s "/var/www/ephemeral/data/ceph/${CEPH_VERSION}/storage-ceph-${CEPH_VERSION}.squashfs"
   
 /root/bin/metalid.sh


echo " Create system configuration"
mkdir -pv "${PITDATA}/prep"
cd "${PITDATA}/prep"
