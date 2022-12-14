#!/bin/bash
#定义一个安装磁盘
sleep 5
rootdisk="/dev/sda"
userpw="P@SSw0rd"
pve_target="/tmp/target"
pve_base="/tmp/pve_base-squ"
ipaddr="192.168.3.44"
netmask="24"
gateway="192.168.3.1"
eth="enp6s18"
fq="pve"
dn="bingsin.com"
G_SLICE=always-malloc

# echo >/etc/apt/sources.list
# cat << EOF >> /etc/apt/sources.list
# deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
# deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
# deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
# deb https://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib 
# deb https://mirrors.ustc.edu.cn/proxmox/debian bullseye pve-no-subscription
# EOF
# apt update
# apt install openssh-server -y
# echo "root:root" | chpasswd
# sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
# sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

disk_setup(){

dd if=/dev/zero of=$rootdisk bs=1M count=16
echo "create gpt"
sgdisk -Z $rootdisk


echo "create bios parttion"
sgdisk -a1 -n1:34:2047  -t1:EF02  $rootdisk

echo "create efi parttion"
sgdisk -a1 -n2:1M:+512M -t2:EF00 $rootdisk
mkfs.vfat -F 32  "$rootdisk"2

echo "create root parttion"
sgdisk -a1 -n3:513M:-1G  $rootdisk
mkfs.ext4 -F "$rootdisk"3
}

copy_roofs(){
mkdir  $pve_base
mount  /cdrom/pve-base.squashfs  $pve_base -t squashfs -o loop
echo "copy pve_target"
mkdir -p $pve_target
mount "$rootdisk"3 $pve_target
cp -ar  $pve_base/* $pve_target
umount $pve_base
}

mount_fstab(){
#fstab
echo "create fstab"
efiboot=$(blkid "$rootdisk"2|awk  '{print $2}'|sed "s/\"//g")
echo "proc /proc proc defaults 0 0" > $pve_target/etc/fstab
echo "$efiboot /boot/efi vfat defaults 0 0" >> $pve_target/etc/fstab
rootboot=$(blkid "$rootdisk"3|awk  '{print $2}'|sed "s/\"//g")
echo "$rootboot / ext4 errors=remount-ro 0 1" >> $pve_target/etc/fstab
}

prepare_chroot(){
#挂载roofs之前准备
echo "prepare chroot"
mount -n -t tmpfs tmpfs $pve_target/tmp
mount -n -t proc /proc  $pve_target/proc
mount -n -o bind /dev  $pve_target/dev
mount -n -o bind /dev/pts  $pve_target/dev/pts
mount -n -t sysfs sysfs $pve_target/sys 
mkdir $pve_target/mnt/hostrun
mount --bind /run $pve_target/mnt/hostrun
chroot $pve_target mount --bind /mnt/hostrun /run
}


modify_hostname(){
echo "modify hostname"
cat << EOF >> $pve_target/etc/hosts
127.0.0.1 localhost.localdomain localhost
$ipaddr $fq.$dn $fq
#The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF
echo $fq > $pve_target/etc/hostname
}


#修改network
modify_network(){
echo "modify network"
cat << EOF >> $pve_target/etc/network/interfaces 
auto lo
iface lo inet loopback

iface $eth inet manual

auto vmbr0
iface vmbr0 inet static
	address $ipaddr/$netmask
	gateway $gateway
	bridge-ports $eth
	bridge-stp off
	bridge-fd 0
EOF
echo "nameserver 223.5.5.5" > $pve_target/etc/resolv.conf
}


install_apt(){
echo "add local registry"
echo > $pve_target/etc/apt/sources.list
cat << EOF >> $pve_target/etc/apt/sources.list
deb file:///media/proxmox/packages/ ./
EOF
chroot $pve_target  apt --allow-insecure-repositories update
DEBIAN_FRONTEND=noninteractive LC_ALL=C chroot $pve_target apt install --allow-unauthenticated proxmox-ve init  -y
chroot $pve_target dpkg  --force-confold --configure -a
}


install_dpkg(){
chroot $pve_target ifup lo
cd $pve_target/media/proxmox/packages/
for i in `ls *.deb|grep -v open-iscsi`;
do 
DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-depends --no-triggers --force-unsafe-io --force-confold  --unpack /media/proxmox/packages/$i;
done
DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-confold --configure --force-unsafe-io -a 
}

copy_proxmox_lib(){
	proxmox_libdir="/var/lib/proxmox-installer"
    cp $proxmox_libdir/policy-disable-rc.d $pve_target/usr/sbin/policy-rc.d
	cp $proxmox_libdir/fake-start-stop-daemon $pve_target/sbin/
}

clean_proxmox_lib(){
	proxmox_libdir="/var/lib/proxmox-installer"
    rm $pve_target/usr/sbin/policy-rc.d
}


diversion_add(){
    chroot $1 dpkg-divert --package proxmox --add --rename $2
	ln -sf $3 $1/$2
}
diversion_remove(){
    mv $1/$2.distrib $1/$2
	chroot $1 dpkg-divert --remove $2
}

disk_setup
copy_roofs
mount_fstab
prepare_chroot
modify_hostname
modify_network
copy_proxmox_lib
diversion_add $pve_target /sbin/start-stop-daemon /sbin/fake-start-stop-daemon
diversion_add $pve_target /usr/sbin/update-grub /bin/true
diversion_add $pve_target /usr/sbin/update-initramfs /bin/true

#将iso挂载到pve_target中
umount -l /dev/sr0
chroot $pve_target mount /dev/sr0 /media
install_dpkg
clean_proxmox_lib
diversion_remove $pve_target /sbin/start-stop-daemon
diversion_remove $pve_target /usr/sbin/update-grub
diversion_remove $pve_target /usr/sbin/update-initramfs

#配置引导
echo "create grub"
chroot $pve_target /usr/sbin/update-initramfs -c -k all
mkdir $pve_target/boot/efi 
chroot $pve_target mount "$rootdisk"2 /boot/efi
chroot $pve_target update-grub
mkdir $pve_target/boot/efi/EFI/BOOT/ -p
chroot $pve_target grub-install --target x86_64-efi --no-floppy --bootloader-id='proxmox' $rootdisk
cp $pve_target/boot/efi/EFI/proxmox/grubx64.efi $pve_target/boot/efi/EFI/BOOT/BOOTX64.EFI 

#enable ssh
echo "allow root login with openssh"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' $pve_target/etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $pve_target/etc/ssh/sshd_config

#apt source
echo "change proxmox-ve and debian registry mirror"
echo > $pve_target/etc/apt/sources.list
cat << EOF >> $pve_target/etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib 
deb https://mirrors.ustc.edu.cn/proxmox/debian bullseye pve-no-subscription
EOF

#添加key
#wget http://download.proxmox.com/debian/proxmox-release-bullseye.gpg -O $pve_target/etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg


# #取消挂载
# echo clean
# umount -l $pve_target/proc
# umount -l $pve_target/sys
# umount -l $pve_target/dev
# umount -l $pve_target/dev/pts
# umount -l $pve_target/boot/efi/
# rm -rf $pve_target/tools
# umount -l $pve_target


