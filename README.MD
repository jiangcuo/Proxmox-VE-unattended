#  Proxmox VE  unattend install 
## Note

we can find proxmox-installer source on https://git.proxmox.com/?p=pve-installer.git;a=blob;f=proxinstall;h=f9b67a37e042ed7503238e8cf4c2dd19e1ae5de8;hb=refs/heads/master

We can find this in proxmox-ve.iso

- debian-base-rootfs -->pve-base.squ

- pve-installer -->pve-base.squ


I add a `start.sh` to `.xinitrc`(pve-installer). 

```
root@jammy:~/2/proxmox/packages# cat /tmp/iso/squashfs-root/.xinitrc 
/usr/bin/xrdb -load /.Xdefaults
/usr/bin/X11/xsetroot -solid grey
bash /start.sh
openbox &
/.spice-vdagent.sh &
G_SLICE=always-malloc /usr/bin/proxinstall
```

`start.sh` will executes `install-pve.sh` file which in  `/cdrom `.

![](./arch.jpg)

Now, We can edit `install-pve.sh` if we want to do more.

## files

- geniso.sh    ->modify iso
- install_pve_to_rootfs-for-pve-base.sh    ->old scripts
- install-pve.sh ->install pve to disk shell scripts
- sart.sh ->add to .xinitrc
- rootfs.sh -> diy rootfs

## ISOFILE
```
root@jammy:~/2# tree -L 1
.
├── COPYING
├── COPYRIGHT
├── EULA
├── Release.txt
├── System
├── boot
├── debian -> .
├── dists
├── efi.img
├── install-pve.sh
├── mach_kernel
├── proxmox
├── pve-base.squashfs
└── pve-installer.squashfs
```

iso download link
https://foxi.buduanwang.vip/pan/foxi/Virtualization/proxmox/unofficialiso/PVE7.iso


## how to use

- gen pxe file ,see https://github.com/morph027/pve-iso-2-pxe
- use pxe to deploy


## Next

- make scripts readable and intelligent.
- load config file from cdrom or lan.
- can add more package like ceph and so on.
- add legacy and uefi mode support, only support uefi now.