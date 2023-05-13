#!/bin/bash
#ReadME
##########  install_way  ###########
install_way="cdrom"  # apt|cdrom optional ! default is cdrom. 
#########   config_file  ##########
config_file="rand" # how to load config_file from http|cdrom|local|rand
#-----  http  ------
#you must set http_conf_url if you want't use http.
##http_conf_url="http://192.168.3.120:801/msg.conf"
##msg.conf like
###mac hostname dn  ip_addr cidr  gateway install_way time_zone passwd  pvedisk 
###EA:5A:F0:5A:B3:D2 pve2 bingsin.com 10.13.14.22 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D3 pve3 bingsin.com 10.13.14.23 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D4 pve4 bingsin.com 10.13.14.24 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D5 pve5 bingsin.com 10.13.14.25 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sdb
###EA:5A:F0:5A:B3:D6 pve6 bingsin.com 10.13.14.26 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
###EA:5A:F0:5A:B3:D7 pve7 bingsin.com 10.13.14.27 24  10.13.14.252 cdrom Asia/Shanghai P@SSword /dev/sda
#-----   cdrom  -------
#you must set add msg.conf to the cdrom root dir.
#-----   local  -------
##if you set config_file="local",You need to configure the local_config function 
#-----   rand  -------
##if you set config_file="rand",You need to configure the rand_config function.
##########  isofile  ###########
#isofile="/2/PVE-unattached-ceph.iso" # optional !
## if you don't hava /dev/sr0,you can use proxmox.iso 
sleep 3
#force env
proxmox_libdir="/var/lib/proxmox-installer"
pve_target="/tmp/target"

local_config(){
	rootdisk="/dev/sdd"
	userpw="bingsin"
	ipaddr="10.13.14.5"
	netmask="24"
	gateway="10.13.14.252"
	eth="enp68s0"
	fq="pve5"
	dn="bingsin.com"
}

rand_config(){
	echo > /tmp/nets
	echo > /tmp/ips
	for nets in `ls /sys/class/net/|grep -v lo`;do
	echo "$nets" `ip addr show dev $nets |grep -v inet6|grep inet|head -n 1|awk '{print $2}'` >>/tmp/ips;
	done
	eth=`grep / /tmp/ips |head -n 1 |awk '{print $1}'`
	ipaddr=`grep / /tmp/ips |head -n 1 |awk '{print $2}'|cut -d "/" -f1`
	netmask=`grep / /tmp/ips |head -n 1 |awk '{print $2}'|cut -d "/" -f2`
	gateway=
	dn="bingsin.com"
	fq=`strings /dev/urandom |tr -dc a-z | head -c14`
	userpw="P@SSw0rd"
	rootdisk="/dev/sda" # two disk need zfs , eg. rootdisk="/dev/sda /dev/sdb".
	# usezfs="1" # will use zfs mirrors.
}

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
	if [  ! -z $usezfs ];then
	unsquashfs  -f -dest $pve_target -i /cdrom/pve-base.squashfs
	else
	if [ -d $pve_target  ];then
		echo "$pve_target is exist"
		echo "delete!"
		umount $pve_target
		rm $pve_target -rf
	fi
	mkdir -p $pve_target
	if [ -n "$diskcheck" ];then
		echo "special detected"
		mount "$rootdisk"p3 -t ext4 $pve_target || errlog "mount rootfs disk error!"
	else
		mount "$rootdisk"3 -t ext4 $pve_target || errlog "mount rootfs disk error!"
	fi
	unsquashfs  -f -dest $pve_target -i /cdrom/pve-base.squashfs
	fi
}

mount_fstab(){
	#fstab
	echo "create fstab"
	if [ -n "$diskcheck" ];then
		echo "special detected"
		efiboot=$(blkid "$rootdisk"p2|awk  '{print $2}'|sed "s/\"//g")
		echo "proc /proc proc defaults 0 0" > $pve_target/etc/fstab
		echo "$efiboot /boot/efi vfat defaults 0 0" >> $pve_target/etc/fstab
		rootboot=$(blkid "$rootdisk"p3|awk  '{print $2}'|sed "s/\"//g")
		echo "$rootboot / ext4 errors=remount-ro 0 1" >> $pve_target/etc/fstab
	else
		efiboot=$(blkid "$rootdisk"2|awk  '{print $2}'|sed "s/\"//g")
		echo "proc /proc proc defaults 0 0" > $pve_target/etc/fstab
		echo "$efiboot /boot/efi vfat defaults 0 0" >> $pve_target/etc/fstab
		rootboot=$(blkid "$rootdisk"3|awk  '{print $2}'|sed "s/\"//g")
		echo "$rootboot / ext4 errors=remount-ro 0 1" >> $pve_target/etc/fstab
	fi
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
	umount -l $pve_target/dev/pts
	umount -l $pve_target/dev
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
	if [ ! -n "$gateway" ];then
   		cat << EOF > $pve_target/etc/network/interfaces 
auto lo
iface lo inet loopback

iface $eth inet manual

auto vmbr0
iface vmbr0 inet static
	address $ipaddr/$netmask
	bridge-ports $eth
	bridge-stp off
	bridge-fd 0
EOF
	else
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
	fi
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
	DEBIAN_FRONTEND=noninteractive chroot $pve_target apt install --no-install-recommends ifupdown2 proxmox-ve grub-efi shim-signed grub-efi-amd64-bin grub-efi-amd64-signed console-setup bash-completion ksmtuned wget init curl nano vim iputils-* locales  -y || echo "failed but ok !"
	fix_pkg_systemderror
}

install_dpkg(){
	#chroot $pve_target mount /dev/sr0 /media
	mount -o bind /cdrom $pve_target/media
	cd $pve_target/media/proxmox/packages/
	for i in `ls *.deb`;
	do 
		LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-depends --no-triggers --force-unsafe-io --force-confold  --unpack /media/proxmox/packages/$i;
	done
	LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --force-confold --configure --force-unsafe-io -a || echo "failed but ok"
	fix_pkg_systemderror
	umount -l $pve_target/media
}

fix_pkg_systemderror(){
	modify_proxmox_boot_sync
	#fix kernel postinstall error
	cp $pve_target/var/lib/dpkg/info/pve-kernel-*.postinst /tmp/
	rm $pve_target/var/lib/dpkg/info/pve-kernel-*.postinst
	#fix ifupdown2 error
	cp $pve_target/var/lib/dpkg/info/ifupdown2.postinst  /tmp/
	rm $pve_target/var/lib/dpkg/info/ifupdown2.postinst  
	LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $pve_target dpkg --configure -a
	cp /tmp/ifupdown2.postinst $pve_target/var/lib/dpkg/info/ifupdown2.postinst
	cp /tmp/pve-kernel-*.postinst $pve_target/var/lib/dpkg/info/
	restore_proxmox_boot_sync
	chroot $pve_target systemctl enable networking  >/dev/null 2>&1
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
	# sshid=""
	# mkdir $pve_target/root/.ssh/
	# echo "$ssdid" >>$pve_target/root/.ssh/authorized_keys

}

grub_install(){
	echo "create grub"
	chroot $pve_target /usr/sbin/update-initramfs -c -k all  >/dev/null 2>&1
	echo "create efi boot"
	mkdir $pve_target/boot/efi
	if [ -n "$diskcheck" ];then
		echo "special detected"
		chroot $pve_target mount "$rootdisk"p2 /boot/efi || errlog "mount boot partition failed !"
	else
		chroot $pve_target mount "$rootdisk"2 /boot/efi || errlog "mount boot partition failed !"
	fi
	chroot $pve_target update-grub
	mkdir $pve_target/boot/efi/EFI/boot/ -p
	chroot $pve_target grub-install --target x86_64-efi --uefi-secure-boot --no-floppy --bootloader-id='proxmox' $rootdisk
	cp $pve_target/boot/efi/EFI/proxmox/* $pve_target/boot/efi/EFI/boot/
	mv $pve_target/boot/efi/EFI/boot/grubx64.efi $pve_target/boot/efi/EFI/boot/bootx64.efi
	echo "create bios boot"
	chroot $pve_target grub-install --target=i386-pc --recheck --debug $rootdisk >/dev/null 2>&1
}

zfs_install(){
	echo "create systemd boot"
	echo "root=ZFS=rpool/ROOT/pve-1 boot=zfs" > $pve_target/etc/kernel/cmdline
	echo "GRUB_CMDLINE_LINUX=\"root=ZFS=rpool/ROOT/pve-1 boot=zfs\"" > $pve_target/etc/default/grub.d/zfs.cfg 
	echo >  $pve_target/etc/kernel/proxmox-boot-uuids
	for rootdisks in $rootdisk;do
		diskcheck=`echo $rootdisk |grep  -E "nvme|nbd|pmem0"`
		if [ -n "$diskcheck" ];then
			chroot $pve_target proxmox-boot-tool format "$rootdisks"p2 --force 
			blkid "$rootdisks"p2 |awk '{print $2}'|cut -d "\"" -f2 >> $pve_target/etc/kernel/proxmox-boot-uuids
			chroot $pve_target proxmox-boot-tool init "$rootdisks"p2 
		else
			chroot $pve_target proxmox-boot-tool format "$rootdisks"2 --force  
			blkid "$rootdisks"2 |awk '{print $2}'|cut -d "\"" -f2 >>$pve_target/etc/kernel/proxmox-boot-uuids
			chroot $pve_target proxmox-boot-tool init "$rootdisks"2 
		fi
	done
	cp /etc/hostid $pve_target/etc
	systemd-id128 new > $pve_target/etc/machine-id
	chroot $pve_target /usr/sbin/update-initramfs -c -k all  >/dev/null 2>&1
	chroot $pve_target  proxmox-boot-tool refresh
	chroot $pve_target update-grub
	mkdir $pve_target/boot/efi/EFI/boot/ -p
	for rootdisks in $rootdisk;do
		diskcheck=`echo $rootdisk |grep  -E "nvme|nbd|pmem0"`
		if [ ! -d /sys/firmware/efi ];then
				if [ -n "$diskcheck" ];then
					echo "special detected"
					chroot $pve_target mount "$rootdisks"p2 /boot/efi || errlog "mount boot partition failed !"
				else
					chroot $pve_target mount "$rootdisks"2 /boot/efi || errlog "mount boot partition failed !"
				fi
			chroot $pve_target /usr/sbin/grub-install.real --target x86_64-efi --uefi-secure-boot --no-floppy --bootloader-id='proxmox' $rootdisks
			cp $pve_target/boot/efi/EFI/proxmox/* $pve_target/boot/efi/EFI/boot/
			mv $pve_target/boot/efi/EFI/boot/grubx64.efi $pve_target/boot/efi/EFI/boot/bootx64.efi
			chroot $pve_target  umount /boot/efi
		fi
	done
}

config_postfix(){
	cat << EOF > $pve_target/etc/postfix/main.cf
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

myhostname=$fq.$dn

smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = \$myhostname, localhost.\$mydomain, localhost
relayhost =
mynetworks = 127.0.0.0/8
inet_interfaces = loopback-only
recipient_delimiter = +

compatibility_level = 2

EOF
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
		echo "config_file is set to http"
		wget -P /tmp/ $http_conf_url 
	elif [ $config_file = "cdrom" ];then 
		echo "config_file is set to cdrom"
		if [ -e /cdrom/msg.conf ];then
			cp /cdrom/msg.conf /tmp/
		else
			errlog "no local conf found"
		fi
	else
	 	errlog "config_file $config_file not correct !"
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
		for i in `ls /sys/class/net/|grep -v lo`;do echo "$i" `cat /sys/class/net/$i/address` ;done >/tmp/netandmac
		# use local mac to find this machine conf
		for i in `cat /tmp/netandmac |awk '{print $2}'`;do grep -i $i /tmp/msg.conf ;done >/tmp/yourconf
		#load conf
		if [ ! -s /tmp/yourconf ];then
			errlog "/tmp/yourconf is empty,mybe your server is not in config file."
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
		errlog  "no config file found"
	fi
}

config_check(){
	if [ -z $rootdisk ];then
	errlog "disk not defined"
	fi
	for rootdisks in $rootdisk; do
	if [ ! -b $rootdisks ];then
		errlog "$rootdisks is not exist"
	fi
	if [ ! -z "$(lsblk -f|grep $rootdisks|grep LVM2)" ];then
		errlog "Detected lvm filesystem on $rootdisks ,abort! please remove it and try again."
	fi
	if [ ! -z "$(df -h|grep $rootdisks)" ];then
		errlog "Detected $rootdisks has mounted ! plese umount first"
	fi
	done
	test -f /cdrom/pve-base.squashfs || errlog "can't find pve-base.squashfs! mybe /cdrom not mounted"
	test -d $proxmox_libdir || errlog "no proxmox-installer found"
	
}

disk_setup(){
	for rootdisks in $rootdisk; do
	dd if=/dev/zero of=$rootdisks bs=1M count=2048
	echo "create gpt"

	sgdisk -GZ $rootdisks >/dev/null 2>&1
	echo "create bios parttion"

	sgdisk -a1 -n1:34:2047  -t1:EF02  $rootdisks >/dev/null 2>&1
	echo "create efi parttion"

	sgdisk -a1 -n2:1M:+512M -t2:EF00 $rootdisks >/dev/null 2>&1

	echo "create root parttion"
	sgdisk -a1 -n3:513M:-1G  $rootdisks >/dev/null 2>&1
	diskcheck=`echo $rootdisk |grep  -E "nvme|nbd|pmem0"`
	if [ -n "$diskcheck" ];then
		echo "special detected"
		mkfs.ext4 -F "$rootdisks"p3
		mkfs.vfat -F 32 "$rootdisks"p2
	else
		mkfs.ext4 -F "$rootdisks"3
		mkfs.vfat -F 32 "$rootdisks"2
	fi
	done
}

zfs_mirrors(){
		modprobe zfs
		echo >/tmp/zfsdev
		for rootdisks in $rootdisk;do
			diskcheck=`echo $rootdisk |grep  -E "nvme|nbd|pmem0"`
			if [ -n "$diskcheck" ];then
					echo -n " $rootdisks"p3 >>/tmp/zfsdev
			else
					echo -n " $rootdisks"3 >>/tmp/zfsdev
			fi
		done
		zpool create -f -o ashift=12 rpool mirror `cat /tmp/zfsdev` || errlog "zfs create mirrors failed"
		zfs create rpool/ROOT  || errlog "zfs create rpool/ROOT failed"
		zfs create rpool/data  || errlog "zfs create rpool/data failed"
		zfs create rpool/ROOT/pve-1 || errlog "zfs create rpool/ROOT/pve-1 failed"
		pve_target="/rpool/ROOT/pve-1"
}


config_passwd(){
	echo "root:$userpw" |chroot $pve_target chpasswd
}

debconfig_set(){
	echo "locales locales/default_environment_locale select en_US.UTF-8" >> $pve_target/tmp/debconfig.txt
	echo "locales locales/locales_to_be_generated select en_US.UTF-8 UTF-8" >> $pve_target/tmp/debconfig.txt
	echo "samba-common samba-common/dhcp boolean false" >> $pve_target/tmp/debconfig.txt
	echo "samba-common samba-common/workgroup string WORKGROUP" >> $pve_target/tmp/debconfig.txt
	echo "postfix postfix/main_mailer_type select No configuration" >> $pve_target/tmp/debconfig.txt
}
debconfig_write(){
	chroot $pve_target debconf-set-selections /tmp/debconfig.txt
	chroot $pve_target rm /tmp/debconfig.txt
}
modify_proxmox_boot_sync(){
	sed -i 's/^/#&/' $pve_target/etc/initramfs/post-update.d//proxmox-boot-sync
	sed -i '1c \#!/bin/bash' $pve_target/etc/initramfs/post-update.d//proxmox-boot-sync
}

restore_proxmox_boot_sync(){
	sed -i 's/^#//' $pve_target/etc/initramfs/post-update.d//proxmox-boot-sync
	sed -i '1c \#!/bin/bash' $pve_target/etc/initramfs/post-update.d//proxmox-boot-sync
}

checkisofile
if [ $config_file = "local" ];then
	echo "config_file is set to local"
	local_config
elif [ $config_file = "rand" ];then
	echo "config_file is set to rand"
	rand_config
else
	check_config
	load_config
fi
config_check

disk_setup
if [ ! -z $usezfs ];then
zfs_mirrors
fi

copy_roofs
if [ -z $usezfs ];then
mount_fstab
fi
prepare_chroot
modify_hostname
modify_network
copy_proxmox_lib
diversion_add $pve_target /sbin/start-stop-daemon /sbin/fake-start-stop-daemon
diversion_add $pve_target /usr/sbin/update-grub /bin/true
diversion_add $pve_target /usr/sbin/update-initramfs /bin/true
debconfig_set
debconfig_write
if [ -z $install_way ];then
	echo "install way is set to dpkg !" 
	install_dpkg
elif [ $install_way = "apt" ];then
	echo "install way is set to apt !" 
	install_apt
elif [ $install_way = "cdrom" ];then
	echo "install way is set to dpkg !" 
	install_dpkg
else
	errlog "install_way not corrected !"
fi

clean_proxmox_lib
diversion_remove $pve_target /sbin/start-stop-daemon
diversion_remove $pve_target /usr/sbin/update-grub
diversion_remove $pve_target /usr/sbin/update-initramfs

if [ -z $usezfs ];then
grub_install
else
zfs_install
fi
enable_ssh
config_postfix
config_timezone
config_passwd
clean_chroot
if [ ! -z $usezfs ];then
	zfs set mountpoint=/ rpool/ROOT/pve-1
	zpool set bootfs=rpool/ROOT/pve-1 rpool 
	zpool export rpool
fi

#reboot -f