# Ubuntu 18.04 SD card installation creator

`mkcard.sh` creates fully unattended installation on removable media. It is tailored to install on Atomic Pi with wifi support, but you can tailor it to your needs.  Be careful with disk you specify as an argument because if it is removable there will be no questions, confirmations or warnings.

## How to use

TL;DR

```
WIFI_SSID=my_ssid WIFI_PASS=my_ssid_pass \
SERVICE_PASSWORD=my_service_user_password \
SSH_KEY=ssh_public_key_to_add_to_ssh_authorized_keys \
bash mkcard.sh /dev/sdX
```

Script understands following environment variables:

* `WIFI_SSID` - **required** SSID of wireless network to use during installation and in system settings
* `WIFI_PASS` - **required** password for SSID specified above
* `SERVICE_PASSWORD` - **required (or use CRYPT_PASSWORD)** unencrypted service user password. Will be encrypted using SHA-512.
* `CRYPT_PASSWORD` - **required (or use SERVICE_PASSWORD)** instead of exposing service user password in your shell history you can create encrypted password using `mkpasswd` utility and specify its result as `CRYPT_PASSWORD`. Script will ignore `SERVICE_PASSWORD` variable then.
* `TIMEZONE` - optional. Script will use contents `/etc/timezone` by default.
* `SSH_KEY`/`SSH_KEY1`/`SSH_KEY2` - optional. You can specify either one or two public keys to be placed in service user `~/.ssh/authorized_keys` file.
* `ISO_NAME`/`ISO_RELEASE_URL` - optional. You can override name and URL for Ubuntu distro. Most likely you want to keep it untouched.

## Service user

Script uses hardcode username `service` for installation to be created. You have to specify password for it using either `SERVICE_PASSWORD` or `CRYPT_PASSWORD`.
Here is example how to create `CRYPT_PASSWORD`. You have to install package "whois" to get mkpasswd utility or you can use any other good method to generate encrypted password.
```
% mkpasswd -m sha-512 -R 50000
Password:
$6$rounds=50000$kcMcBX3u$sF/kY15acgOCn3lzqy9BPubFuJYD8vleFudbC45c0I84UuKpda6onYHTNnGjv3CWgXTF5bDWG9X/vk1mK.ZlY0
% WIFI_SSID=my_ssid WIFI_PASS=my_ssid_pass \
	CRYPT_PASSWORD='$6$rounds=50000$kcMcBX3u$sF/kY15acgOCn3lzqy9BPubFuJYD8vleFudbC45c0I84UuKpda6onYHTNnGjv3CWgXTF5bDWG9X/vk1mK.ZlY0' \
	SSH_KEY=ssh_public_key_to_add_to_ssh_authorized_keys \
	bash mkcard.sh /dev/sdX
```

## How to boot and install from SD card on Atomic Pi

```
% sudo efibootmgr

BootCurrent: 0000
Timeout: 1 seconds
BootOrder: 0000,0007,0001,0002,0005
Boot0000* ubuntu
Boot0001* UEFI: IP4 Realtek PCIe GBE Family Controller
Boot0002* UEFI: IP6 Realtek PCIe GBE Family Controller
Boot0005* UEFI: Generic MassStorageClass2402, Partition 1
Boot0007* Android-IA

# specify number from output above that has (MassStorageClass..) in description
# in our case it is "5".
% sudo efibootmgr -n 5

# Check that BootNext is correct

BootNext: 0005
BootCurrent: 0000
Timeout: 1 seconds
BootOrder: 0000,0007,0001,0002,0005
Boot0000* ubuntu
Boot0001* UEFI: IP4 Realtek PCIe GBE Family Controller
Boot0002* UEFI: IP6 Realtek PCIe GBE Family Controller
Boot0005* UEFI: Generic MassStorageClass2402, Partition 1
Boot0007* Android-IA

% sudo reboot
```
