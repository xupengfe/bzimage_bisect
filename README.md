# bzimage_bisect
It's a bzimage bisect automation tool in QEMU

Sample:
./bisect_bz.sh -k "/root/os.linux.intelnext.kernel" -m "20206306af3eb6790acc9b43d06cd50b6da7c98d" -s "62fb9874f5da54fdb243003b386128037319b219" -d "/home/bzimage" -p "general protection" -i /root/image/stretch2.img -t 360
