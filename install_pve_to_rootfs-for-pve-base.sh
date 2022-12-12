#!/bin/bash
#定义一个安装磁盘
rootdisk="/dev/sda"
userpw="P@SSw0rd"
pve_target="/tmp/target"
pve_base="/tmp/pve_base-squ"
ipaddr="10.13.14.24"
netmask="24"
gateway="10.13.14.252"
eth="enp6s18"
fq="pve"
dn="bingsin.com"


#创建gpt分区表
dd if=/dev/zero of=$rootdisk bs=1M count=1
echo "create gpt"
sgdisk -Z $rootdisk

#创建bios分区
echo "create bios parttion"
sgdisk -a1 -n1:34:2047  -t1:EF02  $rootdisk

#创建ESP分区
echo "create efi parttion"
sgdisk -a1 -n2:1M:+512M -t2:EF00 $rootdisk
mkfs.vfat -F 32  "$rootdisk"2

#创建剩余的分区
echo "create root parttion"
sgdisk -a1 -n3:513M:-1G  $rootdisk
mkfs.ext4 -F "$rootdisk"3

#挂载pve_target
##挂载光盘
# mkdir /tmp/iso -p
mkdir  $pve_base
# mount /dev/sr0 /tmp/iso
##将光盘的base挂载到pve_target
mount  /cdrom/pve-base.squashfs  $pve_base -t squashfs -o loop
##拷贝pve_target
echo "copy pve_target"
mkdir -p $pve_target
mount "$rootdisk"3 $pve_target
cp -ar  $pve_base/* $pve_target
##卸载pve_target
umount $pve_base

#fstab
echo "create fstab"
efiboot=$(blkid "$rootdisk"2|awk  '{print $2}'|sed "s/\"//g")
echo "proc /proc proc defaults 0 0" > $pve_target/etc/fstab
echo "$efiboot /boot/efi vfat defaults 0 0" >> $pve_target/etc/fstab
rootboot=$(blkid "$rootdisk"3|awk  '{print $2}'|sed "s/\"//g")
echo "$rootboot / ext4 errors=remount-ro 0 1" >> $pve_target/etc/fstab


#挂载roofs之前准备
echo "prepare chroot "
mount -t proc /proc  $pve_target/proc
mount -t sysfs /sys  $pve_target/sys
mount -o bind /dev  $pve_target/dev

#修改host
echo "modify hostname"
cat << EOF >> $pve_target/etc/hosts
127.0.0.1	localhost
$ipaddr $fq.$dn $fq
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
echo $fq > $pve_target/etc/hostname

#修改network
echo "modify network "
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

#配置grub
echo "configure grub"
mkdir $pve_target/boot/efi 
chroot $pve_target mount "$rootdisk"2 /boot/efi

#将iso挂载到pve_target中
chroot $pve_target mount /dev/sr0 /media

cat << EOF >> $pve_target/tmp/install.sh
#!/bin/bash
DEBIAN_FRONTEND=noninteractive dpkg  --force-depends --no-triggers --force-unsafe-io --force-confold  --unpack /media/proxmox/packages/*.deb
DEBIAN_FRONTEND=noninteractive dpkg  --force-confold --configure --force-unsafe-io -a 
echo "root:$userpw" | chpasswd
EOF

#安装软件包
echo "install pve to disk"
# sed -i "s/password/$userpw/g" $pve_target/tools/installpve.sh
chroot $pve_target bash /tmp/install.sh

#配置引导
chroot $pve_target update-grub
mkdir $pve_target/boot/efi/EFI/BOOT/ -p
chroot $pve_target grub-install --target x86_64-efi --no-floppy --bootloader-id='proxmox' $rootdisk
cp $pve_target/boot/efi/EFI/proxmox/grubx64.efi $pve_target/boot/efi/EFI/BOOT/BOOTX64.EFI 

#enable ssh
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' $pve_target/etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $pve_target/etc/ssh/sshd_config

#apt source
echo > $pve_target/etc/apt/sources.list
cat << EOF >> $pve_target/etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib 
deb https://mirrors.ustc.edu.cn/proxmox/debian bullseye pve-no-subscription
EOF

#添加key
wget http://download.proxmox.com/debian/proxmox-release-bullseye.gpg -O $pve_target/etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg

#取消挂载
echo clean
umount $pve_target/proc
umount $pve_target/sys
umount $pve_target/dev
umount $pve_target/boot/efi/
rm -rf $pve_target/tools
umount $pve_target



