# bzimage_bisect
It's a bzimage bisect automation tool in QEMU

Sample:
./bisect_bz.sh -k "/root/os.linux.intelnext.kernel" -m "20206306af3eb6790acc9b43d06cd50b6da7c98d" -s "62fb9874f5da54fdb243003b386128037319b219" -d "/home/bzimage" -p "general protection" -i /root/image/stretch2.img -t 360 -n 1 -r "/root/syzkaller/workdir/crashes/x.c"


commit bbf5c979011a099af5dc76498918ed7df445635b (tag: v5.9)
commit 2c85ebc57b3e1817b6ce1a6b703928e113a90442 (tag: v5.10)
commit f40ddce88593482919761f74910f42f4b84c004b (tag: v5.11)
commit 9f4ad9e425a1d3b6a34617b8ea226d56a119a717 (tag: v5.12)
commit 62fb9874f5da54fdb243003b386128037319b219 (tag: v5.13)
