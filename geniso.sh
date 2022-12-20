#!/bin/bash
isofile="/root/Desktop/proxmox-ve_7.3-1.iso"
isotemp="/tmp/iso"
startsh="/root/Desktop/Proxmox-VE-unattended/start.sh"
mkdir $isotemp
mount -o loop $isofile /mnt
rsync -rav /mnt/* $isotemp
umount /mnt

cd $isotemp 
unsquashfs $isotemp/pve-installer.squashfs  
cp $startsh $isotemp/squashfs-root/install-pve.sh
sed -i "3i bash /start.sh" $isotemp/squashfs-root/.xinitrc
mksquashfs $isotemp/squashfs-root/ ./pve-installer.squashfs
rm -rf $isotemp/squashfs-root 

# I find ifupdown2 can't configure correctly by dpkg,  delete it and add ifenslave
echo "make pkg"
rm $isotemp/proxmox/packages/ifupdown2_3.1.0-1+pmx3_all.deb
wget -P $isotemp/proxmox/packages/ https://mirrors.ustc.edu.cn/proxmox/debian/dists/bullseye/pve-no-subscription/binary-amd64/ifupdown_0.8.36%2Bpve2_amd64.deb
wget -P $isotemp/proxmox/packages/ https://mirrors.ustc.edu.cn/debian/pool/main/i/ifenslave/c_2.13~deb11u1_all.deb

#recreated the Packages
cd  $isotemp/proxmox/packages
dpkg-scanpackages -m . > Packages


# Now we can install proxmox-ve with apt install
#add base apt source 
#deb file:///path/to/packages/ ./
#apt --allow-insecure-repositories update
#DEBIAN_FRONTEND=noninteractive  apt install --allow-unauthenticated  proxmox-ve -y