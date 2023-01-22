#!/bin/bash
#ReadME
##########  install_way  ###########
#install_way="cdrom"  # optional !
##default is cdrom. apt now has some bug,not recommened
#########   config_file  ##########
#config_file="local"  # necessary!
##how to load config_file from http|cdrom|local
#-----  http  ------
#you must set http_conf_url if you want't use http.
##http_conf_url="http://192.168.3.120:801/msg.conf"
##msg.conf like
###mac fq dn  ip_addr cidr  gateway install_way time_zone passwd  pvedisk 
###EA:5A:F0:5A:B3:D2 pve2 bingsin.com 10.13.14.22 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D3 pve3 bingsin.com 10.13.14.23 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D4 pve4 bingsin.com 10.13.14.24 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D5 pve5 bingsin.com 10.13.14.25 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sdb
###EA:5A:F0:5A:B3:D6 pve6 bingsin.com 10.13.14.26 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D7 pve7 bingsin.com 10.13.14.27 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
#-----   local  -------
##if you set config_file="local",You need to configure the following env
#local_env
#pve_target="/tmp/target"
#pve_base="/tmp/pve_base-squ"
#rootdisk="/dev/sdb"
#userpw="P@SSw0rd"
#ipaddr="192.168.3.41"
#netmask="24"
#gateway="192.168.3.1"
#eth="enp6s18"
#fq="pve"
#dn="bingsin.com"
#-----------------------------------------------------
##########  isofile  ###########
#isofile="/proxmox.iso" # optional !
## if you don't hava /dev/sr0,you can use proxmox.iso 
sleep 3

errlog(){
	if [ $? != 0 ];then
		echo $1
		exit 0
	fi
}


checkisofile(){
	if [ ! -z $isofile ];then
		if [ -d /cdrom ];then
			umount -l /cdrom
		else
			mkdir /cdrom
		fi
		mount -t iso9660 -o ro,loop $isofile /cdrom || errlog "can't mount iso file!"
	fi
}

copy_roofs(){
	if [ -d $pve_base  ];then
		echo "$pve_base is exist"
		echo "delete!"
		rm $pve_base -rf
	fi
	mkdir  $pve_base 
	mount  /cdrom/pve-base.squashfs  $pve_base -t squashfs -o loop  || errlog "can't mount pve-base.squashfs!"
	echo "copy pve_target"
	if [ -d $pve_target  ];then
		echo "$pve_target is exist"
		echo "delete!"
		rm $pve_target -rf
	fi
	mkdir -p $pve_target
	mount "$rootdisk"3 $pve_target || errlog "mount rootfs disk error!"
	cp -ar  $pve_base/* $pve_target
	umount -l $pve_base
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

clean_chroot(){
	echo "clean chroot"
	echo clean
	umount -l $pve_target/proc
	umount -l $pve_target/sys
	umount -l $pve_target/dev
	umount -l $pve_target/dev/pts
	umount -l $pve_target/boot/efi/
	umount -l $pve_target
}

modify_hostname(){
	echo "modify hostname"
    cat << EOF > $pve_target/etc/hosts
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
	echo "nameserver 223.5.5.5" > $pve_target/etc/resolv.conf
    cat << EOF > $pve_target/etc/network/interfaces 
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
}

apt_mirrors(){
	echo "change proxmox-ve and debian registry mirror"
	wget http://download.proxmox.com/debian/proxmox-release-bullseye.gpg -O $pve_target/etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
	echo > $pve_target/etc/apt/sources.list
	cat << EOF > $pve_target/etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb http://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb http://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
deb http://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib 
deb http://mirrors.ustc.edu.cn/proxmox/debian bullseye pve-no-subscription
EOF
}

install_apt(){
	apt_mirrors
	# echo "#!/bin/sh" > $pve_target/usr/sbin/policy-rc.d
	# echo "exit 0" >> $pve_target/usr/sbin/policy-rc.d
	chroot $pve_target apt update
	#DEBIAN_FRONTEND=noninteractive chroot $pve_target apt install --no-install-recommends init systemd -y 
	DEBIAN_FRONTEND=noninteractive chroot $pve_target apt install --no-install-recommends ifenslave ifupdown proxmox-ve -y
}

install_dpkg(){
	#chroot $pve_target mount /dev/sr0 /media
	mount -o bind /cdrom $pve_target/media
	cd $pve_target/media/proxmox/packages/
	for i in `ls *.deb`;
	do 
		LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-depends --no-triggers --force-unsafe-io --force-confold  --unpack /media/proxmox/packages/$i;
	done
	LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-confold --configure --force-unsafe-io -a 
	umount -l $pve_target/media
}

copy_proxmox_lib(){
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

enable_ssh(){
	echo "allow root login with openssh"
	sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' $pve_target/etc/ssh/sshd_config
	sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $pve_target/etc/ssh/sshd_config
}

grub_install(){
	echo "create grub"
	chroot $pve_target /usr/sbin/update-initramfs -c -k all
	echo "create efi boot"
	mkdir $pve_target/boot/efi 
	chroot $pve_target mount "$rootdisk"2 /boot/efi
	chroot $pve_target update-grub
	mkdir $pve_target/boot/efi/EFI/BOOT/ -p
	chroot $pve_target grub-install --target x86_64-efi --no-floppy --bootloader-id='proxmox' $rootdisk
	cp $pve_target/boot/efi/EFI/proxmox/grubx64.efi $pve_target/boot/efi/EFI/BOOT/BOOTX64.EFI 
	echo "create bios boot"
	chroot $pve_target grub-install --target=i386-pc --recheck --debug $rootdisk >/dev/null 2>&1
}

config_postfix(){
	sed -i "s/^#\?myhostname.*/myhostname=$fq.$dn/" $pve_target/etc/postfix/main.cf
	chroot $pve_target /usr/sbin/postfix check
	chroot $pve_target /usr/sbin/postsuper -d ALL
	chroot $pve_target /usr/bin/newaliases
}

config_timezone(){
	rm $pve_target/etc/localtime
	if [ -z $timezone ];then
		chroot $pve_target ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
	else
		chroot $pve_target ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	fi
}

check_config(){
	if [ $config_file = "http" ];then
		wget -P /tmp/ $http_conf_url 
	elif [ $config_file = "cdrom" ];then 
		if [ -e /cdrom/msg.conf ];then
			cp /cdrom/msg.conf /tmp/
		else
			echo "no local conf found"
			exit 0
		fi
	elif [ $config_file = "local" ];then
		echo "config is set to local"
	else
	 	echo "config_file $config_file not correct !"
	fi
}

load_config(){
	if [ -s /tmp/msg.conf ];then
		doccheck=`cat -A /tmp/msg.conf `
		if [ -n "$doccheck" ];then
		echo "this is windows file  dos2unix"
		dos2unix /tmp/msg.conf
		fi
		#find local machine netdev
		for i in `ls /sys/class/net/`;do echo "$i" `cat /sys/class/net/$i/address` ;done >>/tmp/netandmac
		# use local mac to find this machine conf
		for i in `cat /tmp/netandmac |awk '{print $2}'`;do grep -i $i /tmp/msg.conf ;done >>/tmp/yourconf
		#load conf
		if [ ! -s /tmp/yourconf ];then
			echo "/tmp/yourconf is empty,mybe your server is not in config file."
			exit 0
		fi
		macaddr=`awk '{print $1}' /tmp/yourconf`
		eth=`cat /tmp/netandmac|grep -i $macaddr|awk '{print $1}'`
		ipaddr=`awk '{print $4}' /tmp/yourconf`
		fq=`awk '{print $2}' /tmp/yourconf`
		dn=`awk '{print $3}' /tmp/yourconf`
		netmask=`awk '{print $5}' /tmp/yourconf`
		gateway=`awk '{print $6}' /tmp/yourconf`
		install_way=`awk '{print $7}' /tmp/yourconf`
		timezone=`awk '{print $8}' /tmp/yourconf`
		userpw=`awk '{print $9}' /tmp/yourconf`
		rootdisk=`awk '{print $10}' /tmp/yourconf`
	else
		echo "no config file found"
		exit 0
	fi
}

config_check(){
	if [ -z $rootdisk ];then
	errlog "disk not defined"
	fi
	if [ ! -b $rootdisk ];then
		errlog "$rootdisk is not exist"
	fi
	if [ ! -z "$(lsblk -f|grep $rootdisk|grep LVM2)" ];then
		echo "Detected lvm filesystem on,abort!"
		echo "please remove it and try again."
		exit 0
	fi
	if [ ! -z "$(df -h|grep $rootdisk)" ];then
		echo "Detected $rootdisk has mounted !"
		echo "plese umount first"
		exit 0
	fi
	test -f /cdrom/pve-base.squashfs || errlog "can't find pve-base.squashfs! mybe /cdrom not mounted"
	export proxmox_libdir="/var/lib/proxmox-installer"
	test -d $proxmox_libdir || errlog "no proxmox-installer found"
}

disk_setup(){
	dd if=/dev/zero of=$rootdisk bs=1M count=16
	echo "create gpt"
	sgdisk -GZ $rootdisk >/dev/null 2>&1
	
	echo "create bios parttion"
	sgdisk -a1 -n1:34:2047  -t1:EF02  $rootdisk >/dev/null 2>&1

	echo "create efi parttion"
	sgdisk -a1 -n2:1M:+512M -t2:EF00 $rootdisk >/dev/null 2>&1
	mkfs.vfat -F 32 "$rootdisk"2

	echo "create root parttion"
	sgdisk -a1 -n3:513M:-1G  $rootdisk >/dev/null 2>&1
	mkfs.ext4 -F "$rootdisk"3
}

config_passwd(){
	echo "root:$userpw" |chroot $pve_target chpasswd
}

checkisofile
check_config
if [  $config_file != "local" ];then
	load_config
fi
config_check
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

if [ -z $install_way ];then
	install_dpkg
elif [ $install_way = "apt" ];then
	install_apt
elif [ $install_way = "cdrom" ];then
	install_dpkg
else
	echo "install_way not corrected"
fi

clean_proxmox_lib
diversion_remove $pve_target /sbin/start-stop-daemon
diversion_remove $pve_target /usr/sbin/update-grub
diversion_remove $pve_target /usr/sbin/update-initramfs

grub_install
enable_ssh
apt_mirrors
config_timezone
config_passwd
clean_chroot
#reboot -f