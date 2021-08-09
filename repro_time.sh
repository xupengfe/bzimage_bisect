#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# It's a script for reproduce time check

source "bisect_common.sh"

TIME_FMT="%m%d_%H%M%S"
START_TIME=$(date +"$TIME_FMT")
END_TIME=""
DATE_SS=$(date +%s)
DATE_ES=""
USE_SEC=""
BOOT_TIME="20"
PORT="10022"
REPRO="/root/repro.sh"
REPRO_SH="repro.sh"
REPRO_C_FILE="repro.c"
REPRO_FILE="/root/repro.c"
BASE_PATH=$(pwd)
REPRO_FOLDER="/root/repro"
REPRO_LOG=""
REPRO_DMESG=""

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-b bzImage][-p][-i][-r][-h]
  -b  bzImage with target kernel
  -p  Check point in dmesg like "general protection"
  -i  Image file(optional, default is /root/image/stretch2.img)
  -r  Reproduce file
  -h  show this
__EOF
  exit 1
}

parm_check() {
  [[ -z "$BZIMAGE" ]] && {
    print_err "bzimage:$BZIMAGE is null"
    usage
  }

  [[ -z "$POINT" ]] && {
    print_err "POINT:$POINT is null"
    usage
  }

  [[ -e "$IMAGE" ]] || {
    print_err "IMAGE:$IMAGE does not exist"
    usage
  }

  [[ -e "$REPRO_C" ]] || {
    print_err "REPRO_C:$REPRO_C does not exist"
    usage
  }

  [[ -d "$REPRO_FOLDER" ]] {
    print_log "$REPRO_FOLDER folder does not exist, will create it"
    do_cmd "rm -rf $REPRO_FOLDER"
    do_cmd "mkdir -p $REPRO_FOLDER"
  }
}

do_cmd() {
  local cmd=$*
  local result=""

  print_log "CMD=$cmd"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    print_log "$CMD FAIL. Return code is $RESULT"
    print_log "$CMD FAIL. Return code is $RESULT" >> $REPRO_LOG
    exit $result
  fi
}

clean_old_vm() {
  local old_vm=""

  old_vm=$(ps -ef | grep qemu | grep $PORT  | awk -F " " '{print $2}')

  [[ -z "$old_vm" ]] || {
    print_log "Kill old $PORT qemu:$old_vm"
    kill -9 $old_vm
  }
}

# TODO: improve reproduce step next step
repro_bz() {
  [[ -e "$REPRO_C" ]] || {
    print_err "$REPRO_C does not exist" "$REPRO_LOG"
    exit 1
  }
  do_cmd "scp -P $PORT ${BASE_PATH}/${REPRO_SH} root@localhost:/root/${REPRO_SH}"

  do_cmd "scp -P $PORT $REPRO_C root@localhost:/root/$REPRO_C_FILE"


  do_cmd "ssh -o ConnectTimeout=1 -p $PORT localhost 'ls $REPRO'"
  print_log "ssh -o ConnectTimeout=1 -p $PORT localhost '$REPRO'"
  ssh -o ConnectTimeout=1 -p $PORT localhost "$REPRO" &
}

check_bz_time() {
  local bz_file=$1
  local dmesg_file=$2
  local dmesg_info=""
  local cp_result=""
  local i=1

  for((i=1;i<=300;i++)); do
    sleep 10
    dmesg_info=$(cat $dmesg_file)
    [[ -n "$dmesg_info" ]] || {
      print_err "$dmesg_file is null:$dmesg_info, could not judge!" "$REPRO_LOG"
      clean_old_vm
      exit 1
    }

    cp_result=$(cat $dmesg_file | grep -i "$POINT")
    if [[ -z "$cp_result" ]]; then
      continue
    else
      print_log "$bz_file contained $POINT:$cp_result, FAIL" "$REPRO_LOG"
      END_TIME=$(date +"$TIME_FMT")
      DATE_ES=$(date +%s)
      USE_SEC=$(($DATE_ES - $DATE_SS))
      echo "START_TIME:$START_TIME" >> "$REPRO_LOG"
      echo "END_TIME:$END_TIME" >> "$REPRO_LOG"
      echo "Used $USE_SEC seconds to reproduce" >> "$REPRO_LOG"

      return 0
    fi
  done

  print_log "$dmesg_file not reproduce this issue in 3000s:$bz_file, exit!" "$REPRO_LOG"
  return 1
}

test_bzimage() {
  local bz_file=$1

  clean_old_vm
  [[ -e "$bz_file" ]] || {
    print_err "bzImage:$bz_file does not exist" "$REPRO_LOG"
    exit 1
  }
  print_log "Run $bz_file with image:$IMAGE in local port:$PORT" "$REPRO_LOG"
  qemu-system-x86_64 \
    -m 2G \
    -smp 2 \
    -kernel $bz_file \
    -append "console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0" \
    -drive file=${IMAGE},format=raw \
    -net user,host=10.0.2.10,hostfwd=tcp:127.0.0.1:${PORT}-:22 \
    -cpu host \
    -net nic,model=e1000 \
    -enable-kvm \
    -nographic \
    2>&1 | tee > $REPRO_DMESG &
  sleep "$BOOT_TIME"

  repro_bz
  sleep "$TIME"

  check_bz_time "$bz_file" "$REPRO_DMESG"
}

# Set detault value
: "${TIME:=20}"
: "${IMAGE:=/root/image/stretch2.img}"
while getopts :b:p:i:r:h arg; do
  case $arg in
    b)
      BZIMAGE=$OPTARG
      REPRO_LOG="${REPRO_FOLDER}/${BZIMAGE}.log"
      REPRO_DMESG="${REPRO_FOLDER}/${BZIMAGE}.dmesg"
      ;;
    p)
      POINT=$OPTARG
      ;;
    i)
      IMAGE=$OPTARG
      ;;
    r)
      REPRO_C=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done


repro_time_check() {
  parm_check
  test_bzimage "$BZIMAGE"
  clean_old_vm
}

repro_time_check


