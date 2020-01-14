#!/bin/bash

set -e

echo "===== CLONING SCRIPT FOR CS3630 DUCKIES ====="

# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS="d:n:v"
LONGOPTS="device:,name:,verbose"

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi

# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

v=0 device="" host_name="duckie01"
# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -v|--verbose)
            v=1
            shift
            ;;
        -d|--device)
            device="$2"
            shift 2
            ;;
        -n|--name)
            host_name="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Argument error"
            exit 3
            ;;
    esac
done


[[ $v == 1 ]] && { echo "verbose: $v, device: $device, host_name: $host_name"; }

device_type="$(lsblk -nd -o HOTPLUG $device)" || device_type="0"
device_name="$(lsblk -nd -o LABEL ${device}1)" || device_name="NOFS"

# Sanity check
if [ ! -e $device ] || [[ $(expr $device_type + 0) != 1 ]] || [[ $device_name == "HypriotOS" ]]; then
    echo "Invalid Device, please use the /dev/sdX pointing to the empty SD card"
    echo "Type: $device_type, Name: $device_name"
    exit 4
fi

duration=$SECONDS
echo "[$duration] Copying Image"

sudo dd if=./sdb_10G of=${device} bs=1M count=10240 status=progress

duration=$SECONDS
echo "[$duration] Refresh Partiton Cache"

sudo partprobe ${device}

duration=$SECONDS
echo "[$duration] Resize File System"

sudo parted -s ${device} "resizepart 2 -1" quit
sudo partprobe ${device}

sleep 5

sudo e2fsck -f "${device}2"
sudo resize2fs "${device}2"

duration=$SECONDS
echo "[$duration] Fixing Hostname"

set +x

mp=$(sudo mktemp -d)
sudo mount "${device}2" $mp
sudo sed -i "s/duckie01/${host_name}/g" "$mp/etc/hostname"
sudo sed -i "s/duckie01/${host_name}/g" "$mp/etc/hosts"
sudo sed -i "s/duckie01/${host_name}/g" "$mp/var/lib/cloud/instances/pirate001/cloud-config.txt"
sudo sed -i "s/duckie01/${host_name}/g" "$mp/var/lib/cloud/instances/pirate001/user-data.txt"
sudo sed -i "s/duckie01/${host_name}/g" "$mp/var/lib/cloud/instances/pirate001/user-data.txt.i"
sudo sed -i "s/duckie01/${host_name}/g" "$mp/data/stats/init_sd_card/parameters/hostname"
sudo sed -i "s/-echo /-/g" "$mp/lib/systemd/system/report-mac.service"
sudo sed -i "s#ExecStart=.*#ExecStart=/usr/bin/btuart#" "$mp/etc/systemd/system/hciuart.service"
sudo cp ./btuart "$mp/usr/bin/btuart"
sudo chmod +x "$mp/usr/bin/btuart"
sudo rm "$mp/var/lib/dhcpcd5/dhcpcd-wlan0-GTother.lease"

sudo umount $mp

sudo mount "${device}1" $mp
sudo sed -i "s/duckie01/${host_name}/g" "$mp/user-data"
sudo umount $mp
sudo rmdir $mp

duration=$SECONDS
echo "[$duration] Complete, please remove SD Card"
