#!/bin/bash
#
# Creates an unattended SD card installation of Ubuntu 18.04
#

set -euo pipefail

for COMMAND in curl grub-install mkpasswd realpath rsync sha256sum ; do
	if ! which "${COMMAND}" >/dev/null ; then
		echo "Binary for '${COMMAND}' wasn't found in path."
		echo "Recommended way to fix:"
		echo "	sudo apt-get install coreutils grub2-common whois"
		exit 1
	fi
done

: ${ISO_NAME:=ubuntu-18.04.4-server-amd64.iso}
: ${ISO_RELEASE_URL:=http://cdimage.ubuntu.com/releases/18.04/release/}
: ${WIFI_SSID:?Please define wireless SSID}
: ${WIFI_PASS:?Please define wireless password}
: ${CRYPT_PASSWORD:=$(echo "${SERVICE_PASSWORD:?Please specifyeither CRYPT_PASSWORD or SERVICE_PASSWORD}" | mkpasswd -m sha-512 -s -R 100000)}
: ${SSH_KEY1:=${SSH_KEY:-}}
: ${SSH_KEY2:-}
: ${TIMEZONE:=$(cat /etc/timezone)}

function _log {
	echo -e "\e[1m"
	echo "$*"
	echo -e "\e[0m"
}

[[ "$#" != 1 ]] && echo "Usage: $0 <sd card device>" && exit 1

TARGET_BD="$1"
TARGET_PART="${TARGET_BD}1"
[[ ! -b "${TARGET_BD}" ]] && echo "${TARGET_BD} is not a block device" && exit 1

if [[ $(cat "/sys/block/$(basename ${TARGET_BD})/removable") != "1" ]] ; then
	echo "${TARGET_BD} is not a removable media."
	echo "Edit the script if you thing I'm wrong."
	exit 1
fi

SELF=$(realpath "$0")
SELFDIR=$(dirname "${SELF}")

BUILD_DIR="${SELFDIR}/build"

mkdir -p "${BUILD_DIR}" || echo "Cannot create ${BUILD_DIR}" || exit 1
pushd  "${BUILD_DIR}" >/dev/null

_log "Downloading fresh SHA256SUMS..."
curl -L "${ISO_RELEASE_URL}/SHA256SUMS" -o release.sha256

if [[ -f "${ISO_NAME}" ]] ; then
	_log "Found existing ISO image."
else
	_log "Downloading ISO image..."
	curl -L "${ISO_RELEASE_URL}/${ISO_NAME}" -o "${ISO_NAME}"
fi

#_log "Validating ISO image..."
#if sha256sum -c --quiet <(grep "${ISO_NAME}$" release.sha256) ; then
#	echo "Image validated"
#else
#	echo "Checksum failed. Remove image manually to redownload fresh one"
#	exit 1
#fi

_log "Making partitions and filesystem on ${TARGET_BD}"
sudo parted -s "${TARGET_BD}" mklabel msdos
sudo parted "${TARGET_BD}" mkpart primary fat32 0% 100%
sudo mkfs.vfat "${TARGET_PART}"

mkdir -p distro
sudo mount -o loop "${ISO_NAME}" distro

mkdir -p target
sudo mount "${TARGET_PART}" target

_log "Copying distro contents to target disk (warnings are ok)..."
sudo rsync -rtv distro/ target/

_log "Fixing symlinks on VFAT..."
pushd target/dists >/dev/null
sudo cp -r bionic stable
sudo cp -r bionic unstable
popd >/dev/null

_log "Making ${TARGET_PART} bootable..."
sudo grub-install --no-floppy --root-directory="${BUILD_DIR}/target" --target=x86_64-efi "${TARGET_PART}"
sudo sed -i 's%^set timeout=.*%set timeout=5\
menuentry "APi: Server (Wifi)" {\
	set gfxpayload=keep\
	linux	/install/vmlinuz file=/cdrom/preseed/api-server-wifi.seed auto=true priority=critical debian-installer/locale=en_US keyboard-configuration/layoutcode=us languagechooser/language-name=English countrychooser/shortlist=US localechooser/supported-locales=en_US.UTF-8 console=ttyS0,115200 --- net.ifnames=0 ipv6.disable=1 interface=wlan0 mitigations=off\
	initrd	/install/initrd.gz\
}%' target/boot/grub/grub.cfg

_log "Creating preseed..."
sudo tee target/preseed/api-server-wifi.seed > /dev/null <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us
d-i pkgsel/install-language-support boolean false
d-i localechooser/supported-locales multiselect en_US.UTF-8

d-i netcfg/choose_interface select wlan0
d-i netcfg/wireless_show_essids select manual
d-i netcfg/wireless_essid string ${WIFI_SSID}
d-i netcfg/wireless_essid_again string ${WIFI_SSID}
d-i netcfg/wireless_security_type select wpa
d-i netcfg/wireless_wpa string ${WIFI_PASS}

d-i mirror/http/proxy string 
d-i mirror/http/mirror select CC.archive.ubuntu.com
d-i mirror/suite string bionic
d-i mirror/udeb/suite string bionic
d-i mirror/udeb/components multiselect main, restricted

d-i passwd/user-fullname string Service User
d-i passwd/username string service
d-i passwd/user-password-crypted password ${CRYPT_PASSWORD}
d-i user-setup/encrypt-home boolean false

d-i clock-setup/utc boolean true
d-i time/zone string ${TIMEZONE}
d-i clock-setup/ntp boolean true

d-i netcfg/get_hostname string iron
d-i netcfg/get_domain string local

### Apt setup
d-i apt-setup/restricted boolean true
d-i apt-setup/universe boolean true

### Package selection
tasksel tasksel/first multiselect
tasksel/skip-tasks multiselect server
d-i pkgsel/ubuntu-standard boolean false
d-i pkgsel/include string openssh-server python-minimal

d-i pkgsel/update-policy select unattended-upgrades

d-i partman-auto/disk string /dev/mmcblk0
d-i partman-auto/method string regular
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-auto/choose_recipe select atomic

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i grub-installer/grub2_instead_of_grub_legacy boolean true
d-i grub-installer/only_debian boolean true
d-i finish-install/reboot_in_progress note

popularity-contest popularity-contest/participate boolean false

d-i preseed/late_command string \\
	in-target mkdir /home/service/.ssh ; \\
	in-target chmod 700 /home/service/.ssh ; \\
	echo "${SSH_KEY1}" > /target/home/service/.ssh/authorized_keys ; \\
	echo "${SSH_KEY2}" >> /target/home/service/.ssh/authorized_keys ; \\
	in-target chmod 600 /home/service/.ssh/authorized_keys ; \\
	in-target chown -R service:service /home/service/.ssh ; \\
	echo "service ALL=(ALL) NOPASSWD: ALL" > /target/etc/sudoers.d/010_service-nopasswd ; \\
	in-target chmod 600 /etc/sudoers.d/010_service-nopasswd 
EOF

_log "Cleanup..."
sudo umount distro
sudo umount target

_log "Installation media is ready."
popd >/dev/null  # ${BUILD_DIR}
