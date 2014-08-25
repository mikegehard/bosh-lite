#!/bin/bash

set -ex

os_name=$(source /etc/lsb-release ; echo -n ${DISTRIB_DESCRIPTION})
kernel_version=$(basename $(ls /boot/vmlinuz-* |tail -1) |cut -f2-8 -d'-')
initrd_file="initrd.img-${kernel_version}"

cat > /boot/grub/menu.lst <<GRUB_CONF
default=0
timeout=1
title ${os_name} (${kernel_version})
  root (hd0)
  kernel /boot/vmlinuz-${kernel_version} root=LABEL=cloudimg-rootfs ro selinux=0 cgroup_enable=memory swapaccount=1
  initrd /boot/${initrd_file}
GRUB_CONF
