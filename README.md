# bzimage_bisect
It's a bzimage bisect automation tool in QEMU

Sample:
./bisect_bz.sh -k "/root/os.linux.intelnext.kernel" -m "20206306af3eb6790acc9b43d06cd50b6da7c98d" -s "62fb9874f5da54fdb243003b386128037319b219" -d "/home/bzimage" -p "general protection" -i /root/image/stretch2.img -t 360 -n 1 -r "/root/syzkaller/workdir/crashes/x.c"

i:
./bisect_bz.sh -k "/root/os.linux.intelnext.kernel" -m "20206306af3eb6790acc9b43d06cd50b6da7c98d" -s "62fb9874f5da54fdb243003b386128037319b219" -d "/home/bzimage" -p "general protection" -i /root/image/stretch2.img  -n 1 -r "/root/syzkaller/workdir/crashes/6f06714da341949c683ef3e11e4b08c26b10448b/repro.cprog"

./bisect_bz.sh -k "/root/linux" -m "8fe28cb58bcb235034b64cbbb7550a8a43fd88be" -s "39a8804455fb23f09157341d3ba7db6d7ae6ee76" -d "/home/bzimage" -p "netlbl_cipsov4_add" -i /root/image/stretch2.img  -n 1 -r "/root/syzkaller/workdir/crashes/6f06714da341949c683ef3e11e4b08c26b10448b/repro.cprog"

commit bbf5c979011a099af5dc76498918ed7df445635b (tag: v5.9)
commit 2c85ebc57b3e1817b6ce1a6b703928e113a90442 (tag: v5.10)
commit f40ddce88593482919761f74910f42f4b84c004b (tag: v5.11)
commit 9f4ad9e425a1d3b6a34617b8ea226d56a119a717 (tag: v5.12)
commit 62fb9874f5da54fdb243003b386128037319b219 (tag: v5.13)

./repro_time.sh -b /home/bzimage/bzImage_eb8b4dd9b2ff8e9dcad191bf178b3c975ab9f702 -p "kernel BUG" -i /root/image/stretch2.img -r "/root/syzkaller/workdir/crashes/d4d317dc0ede25fe095dc6dcfa9e6a6600e4efd8/repro.cprog"


# debug for make_bz.sh revert commit
/home/code/bzimage_bisect/make_bz.sh -k /root/os.linux.intelnext.kernel -m eb8b4dd9b2ff8e9dcad191bf178b3c975ab9f702  -b 0e0d00d9ecc57f9886b3784e12a71752035b188f -d /home/bzimage -o /tmp/kernel -f /home/bzimage/bzImage_eb8b4dd9b2ff8e9dcad191bf178b3c975ab9f702_0e0d00d9ecc57f9886b3784e12a71752035b188f_rever


