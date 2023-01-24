#!/bin/bash
#create rootfs
arch="arm64"
release="bullseye"
rootfssrc="/tmp/rootfssrc"
rootfssrcsqu="/root/rootf.squ"
pve_pkgs='rados|pve|proxmox|extjs|qemu-server|apparmor|criu|spiceterm|vncterm|ceph|rgw|corosync|rbd|libcfg7|libcmap4|libcpg4|ibjs-qrcodejs|libknet1|libnozzle1|quorum|lxcfs|smartmontools'

get_all_depends(){
        apt-cache depends --no-pre-depends --no-suggests --no-recommends \
                --no-conflicts --no-breaks --no-enhances\
                --no-replaces --recurse $1 | awk '{print $2}'| tr -d '<>' | sort --unique|grep -E -v $pve_pkgs
}

prepare_rootfs_mount(){
mount -t proc /proc  $rootfssrc/proc
mount -t sysfs /sys  $rootfssrc/sys
mount -o bind /dev  $rootfssrc/dev
mount -o bind /dev/pts  $rootfssrc/dev/pts
}

prepare_rootfs_umount(){
umount -l $rootfssrc/proc
umount -l $rootfssrc/sys
umount -l $rootfssrc/dev/pts
umount -l $rootfssrc/dev
}

mkdir $rootfssrc
apt install debootstrap squashfs-tools -y
debootstrap --arch=$arch $release $rootfssrc https://mirrors.ustc.edu.cn/debian/

if [ $release = "buster" ];then
cat << EOF > $rootfssrc/etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ buster main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ buster-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ buster-backports main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security/ buster/updates main contrib non-free
EOF
else
cat << EOF > $rootfssrc/etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security/ bullseye-security main contrib non-free
EOF
fi

rm $rootfssrc/debianpkg/* -rf
mkdir $rootfssrc/debianpkg
cd $rootfssrc/debianpkg

all_depends=$(get_all_depends proxmox-ve )
for depend in $all_depends
do
    apt-get download $depend >>/tmp/download.log
done

prepare_rootfs_mount
chroot $rootfssrc apt update
for i in `ls *.deb`;
do 
LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $rootfssrc dpkg -i /debianpkg/$i
done
LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $rootfssrc apt install -f -y
#打包成SquashFS
rm $rootfssrc/debianpkg/ -rf
prepare_rootfs_umount
mksquashfs  $rootfssrc $rootfssrcsqu -comp zstd
