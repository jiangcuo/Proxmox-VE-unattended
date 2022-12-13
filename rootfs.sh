#!/bin/bash
#create rootfs
rootfssrc="/tmp/rootfssrc"
mkdir $rootfssrc
rootfssrcsqu="/root/rootfs.squ"
apt install debootstrap squashfs-tools -y
debootstrap --arch=amd64  bullseye $rootfssrc https://mirrors.ustc.edu.cn/debian/

#prepare rootfs env
mount -t proc /proc  $rootfs/proc
mount -t sysfs /sys  $rootfs/sys
mount -o bind /dev  $rootfs/dev
mount -o bind /dev/pts  $rootfs/dev/pts

#修改源
echo > $rootfssrc/etc/apt/sources.list

cat << EOF >> $rootfssrc/etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib 
deb https://mirrors.ustc.edu.cn/proxmox/debian bullseye pve-no-subscription
EOF

#添加key
wget http://download.proxmox.com/debian/proxmox-release-bullseye.gpg -O $rootfssrc/etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg

#安装一些软件

#打包成SquashFS
mksquashfs  $rootfssrc $rootfssrcsqu -comp zstd
