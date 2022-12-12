#定义一个安装磁盘
rootdisk="/dev/sda"
userpw="P@SSw0rd"
rootfs="/mnt"
rootfssrc="/data/rootfs"
ipaddr="10.13.14.24"
netmask="24"
gateway="10.13.14.252"
eth="enp6s18"
fq="pve"
dn="bingsin.com"

#创建gpt分区表

dd if=/dev/zero of=$rootdisk bs=1M count=1

echo "create gpt"
parted -s "$rootdisk" mklabel gpt

#创建bios分区
echo "create bios parttion"
parted -s "$rootdisk"  mkpart bios_grub fat32 10 110
parted -s "$rootdisk" set 1 bios_grub

#创建ESP分区
echo "create efi parttion"
parted -s "$rootdisk" mkpart boot fat32 110 610
parted -s "$rootdisk" set 2 esp
sleep 1
mkfs.vfat -F 32  "$rootdisk"2

#创建剩余的分区
echo "create root parttion"
parted -s "$rootdisk" mkpart rootfs ext4 610 90%
sleep 1
mkfs.ext4 -F "$rootdisk"3

#use roofs
echo "copy rootfs"
mkdir -p $rootfs
mount "$rootdisk"3 $rootfs
rsync -arz $rootfssrc/* $rootfs

#fstab
echo "create fstab"
efiboot=$(blkid "$rootdisk"2|awk  '{print $2}'|sed "s/\"//g")
echo "proc /proc proc defaults 0 0" > $rootfs/etc/fstab
echo "$efiboot /boot/efi vfat defaults 0 0" >> $rootfs/etc/fstab
rootboot=$(blkid "$rootdisk"3|awk  '{print $2}'|sed "s/\"//g")
echo "$rootboot / ext4 errors=remount-ro 0 1" >> $rootfs/etc/fstab


#挂载roofs之前准备
echo "prepare chroot "
mount -t proc /proc  $rootfs/proc
mount -t sysfs /sys  $rootfs/sys
mount -o bind /dev  $rootfs/dev

#修改host
echo "modify hostname "
sed -i "2i $ipaddr $fq.$dn $fq" $rootfs/etc/hosts
echo $fq > $rootfs/etc/hostname


#修改network
echo "modify network "
cat << EOF >> $rootfs/etc/network/interfaces 
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
mkdir $rootfs/boot/efi 
chroot $rootfs mount "$rootdisk"2 /boot/efi

#安装软件包
echo "install pve to disk"
sed -i "s/password/$userpw/g" $rootfs/tools/installpve.sh
chroot $rootfs bash /tools/installpve.sh

#配置引导
chroot $rootfs update-grub
mkdir $rootfs/boot/efi/EFI/BOOT/ -p
chroot $rootfs /grub-install --target x86_64-efi --no-floppy --bootloader-id='proxmox' $rootdisk
chroot $rootfs grub-mkimage -c /boot/efi/EFI/proxmox/grub.cfg -p "/EFI/proxmox" -o /boot/efi/EFI/BOOT/BOOTX64.EFI -O x86_64-efi  boot \
chain configfile fat linux ls part_gpt reboot serial efi_gop search_fs_uuid lvm ext2 \
zfs video terminal tar xfs lvm fat all_video  efi_uga echo search \
video_bochs video_cirrus gzio part_gpt loadenv gfxterm gfxterm_menu gfxterm_background \
file font extcmd btrfs geli gettext loopback regexp romfs squash4 udf usb usb_keyboard \
normal 
cp $rootfs/boot/efi/EFI/BOOT/BOOTX64.EFI $rootfs/boot/efi/EFI/proxmox/grubx64.efi

# grub-mkimage -c grub.cfg -p "/EFI/proxmox" -o /boot/efi/EFI/BOOT/BOOTX64.EFI -O x86_64-efi  boot \
# chain configfile fat linux ls part_gpt reboot serial efi_gop search_fs_uuid lvm ext2 \
# zfs video terminal tar xfs lvm fat all_video  efi_uga echo search \
# video_bochs video_cirrus gzio part_gpt loadenv gfxterm gfxterm_menu gfxterm_background \
# file font extcmd btrfs geli gettext loopback regexp romfs squash4 udf usb usb_keyboard  \
# normal 

#enable ssh
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' $rootfs/etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $rootfs/etc/ssh/sshd_config

#取消挂载
echo clean
umount $rootfs/proc
umount $rootfs/sys
umount $rootfs/dev
umount $rootfs/boot/efi/
rm -rf $rootfs/tools
umount $rootfs


