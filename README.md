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

./bisect_bz.sh -k "/root/os.linux.intelnext.kernel" -m "93715b26deb1783677a6c6db9951930caebc698b" -s "7c60610d476766e128cc4284bb6349732cbd6606" -n 1 -d "/home/bzimage" -p "BUG:" -i /root/image/centos8_2.img -r "/root/syzkaller/workdir/crashes/fab31573b49fb78ea0208630854e4f48e322c6ad/repro.cprog"

# debug for make_bz.sh revert commit
/home/code/bzimage_bisect/make_bz.sh -k /root/os.linux.intelnext.kernel -m eb8b4dd9b2ff8e9dcad191bf178b3c975ab9f702  -b 0e0d00d9ecc57f9886b3784e12a71752035b188f -d /home/bzimage -o /tmp/kernel -f /home/bzimage/bzImage_eb8b4dd9b2ff8e9dcad191bf178b3c975ab9f702_0e0d00d9ecc57f9886b3784e12a71752035b188f_rever


#1    2   3	      4      5         6       7         8     9     10       11       12     13      14      15      16       17       18       19     20      21
#HASH des keyword key_ok repro_ker all_ker nker_hash i_tag m_tag i_commit m_commit ndate  c_file  bi_hash bi_com  bi_path  rep_time main_res bi_res bad_com bi_comment

# For summary.sh
./summary.sh -k "/home/linux_cet" -m "7ed918f933a7a4e7c67495033c06e4fe674acfbd" -s "36a21d51725af2ce0700c6ebcb6b9594aac658a6"

# For specific kernel and specific commit
./scan_bisect.sh -k "/home/linux_cet" -m "7ed918f933a7a4e7c67495033c06e4fe674acfbd" -s "36a21d51725af2ce0700c6ebcb6b9594aac658a6"
