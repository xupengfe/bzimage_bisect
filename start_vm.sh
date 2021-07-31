#!/bin/bash

bzimage=$1

[[ -z "$bzimage" ]] && {bzimage="/root/image/bzImage_5.13i_kvm"

qemu-system-x86_64 \
        -m 2G \
        -smp 2 \
        -kernel $bzimage \
        -append "console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0" \
        -drive file=./stretch2.img,format=raw \
        -net user,host=10.0.2.10,hostfwd=tcp:127.0.0.1:10022-:22 \
        -cpu host \
        -net nic,model=e1000 \
        -enable-kvm \
        -nographic \
        2>&1 | tee vm.log
