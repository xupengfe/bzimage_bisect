#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Bisect bzImage automation script, which need kconfig_kvm.sh & make_bz.sh
# bs means bzImage

source "bisect_common.sh"

TIME_FMT="%m%d_%H%M%S"
BISECT_START_TIME=$(date +"$TIME_FMT")
BISECT_SS=$(date +%s)
BISECT_END_TIME=""
BISECT_ES=""
USE_SEC=""
DMESG_FOLDER=""
BOOT_TIME="20"
PORT="10022"
REPRO="/root/repro.sh"
REPRO_SH="repro.sh"
REPRO_C_FILE="repro.c"
REPRO_FILE="/root/repro.c"
BASE_PATH=$(pwd)
echo $BASE_PATH > $PATH_FILE

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-s][-d DEST][-p][-t][-i][-n][-r][-h]
  -k  KERNEL source folder
  -m  COMMIT(end) ID which will be used
  -s  Start COMMIT ID
  -d  Destination where bzImage will be copied
  -p  Check point in dmesg like "general protection"
  -t  Wait time(optional, default time like 10s)
  -i  Image file(optional, default is /root/image/stretch2.img)
  -n  No need make clean kernel src
  -r  Reproduce file
  -h  show this
__EOF
  exit 1
}

clean_old_vm() {
  local old_vm=""

  old_vm=$(ps -ef | grep qemu | grep $PORT  | awk -F " " '{print $2}')

  [[ -z "$old_vm" ]] || {
    print_log "Kill old $PORT qemu:$old_vm"
    kill -9 $old_vm
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
    print_log "$CMD FAIL. Return code is $RESULT" >> $BISECT_LOG
    git bisect log 2>/dev/null >> $BISECT_LOG
    clean_old_vm
    exit $result
  fi
}

tear_down() {
  print_log "Kill old $PORT qemu:$old_vm"
    do_cmd "kill -9 $old_vm"
}

prepare_dmesg_folder() {
  local issue_info=""

  issue_info=$(echo $POINT | tr ' ' '_')
  DMESG_FOLDER="${DEST}/${BISECT_START_TIME}_${issue_info}"
  print_log "Prepare $DMESG_FOLDER" "$BISECT_LOG"
  if [[ -e "$DMESG_FOLDER" ]]; then
    do_cmd "rm -rf $DMESG_FOLDER"
    do_cmd "mkdir -p $DMESG_FOLDER"
  else
    do_cmd "mkdir -p $DMESG_FOLDER"
  fi
}

parm_check() {
  [[ -d "$DEST" ]]  || {
    print_log "DEST:$DEST folder is not exist!"
    usage
  }

  [[ -d "$KERNEL_SRC/.git" ]] || {
    print_err "$KERNEL_SRC doesn't contain .git folder"
    usage
  }
  [[ -n  "$COMMIT" ]] || {
    print_err "commit:$COMMIT is null."
    usage
  }
  [[ -n  "$START_COMMIT" ]] || {
    print_err "Start commit:$START_COMMIT is null."
    usage
  }
  [[ -n "$POINT" ]] || {
    print_err "Check point:$POINT is null."
    usage
  }
  [[ -e "$IMAGE" ]] || {
    print_err "IMAGE:$IMAGE is not exist"
    usage
  }
  echo $NUM > "$NUM_FILE"

  prepare_dmesg_folder
  BISECT_LOG="${DMESG_FOLDER}/${BISECT_LOG}"
  BI_LOG="${DEST}/bi.log"
  cat /dev/null > $BISECT_LOG
  echo >> $BI_LOG
  echo "-------------------------------------------------------" >> $BI_LOG
  echo >> $BI_LOG

  print_log "PARM KER:$KERNEL_SRC|END:$COMMIT|start:$START_COMMIT|DEST:$DEST|CP:$POINT|IMG:$IMAGE|TIME:$TIME"
  export PATH="${PATH}:$BASE_PATH"
}

check_commit() {
  local commit=$1
  local check_result=""

  check_result=$(git log $commit | grep ^commit | head -n 1 2>/dev/null)
  [[ -n "$check_result" ]] || {
    print_err "There is no $commit info in $(pwd)" "$BISECT_LOG"
    usage
  }
}

bisect_init() {
  local old_bisect=""

  old_bisect=$(git bisect log 2>/dev/null)
  print_log "There was old bisect log:$old_bisect, will clean it" "$BISECT_LOG"
  do_cmd "git bisect reset"
  do_cmd "git checkout -f $COMMIT"
}

bisect_prepare() {
  do_cmd "cd $KERNEL_SRC"
  check_commit "$COMMIT"
  check_commit "$START_COMMIT"
  bisect_init
}

prepare_bz() {
  local commit=$1

  [[ -n "$commit" ]] || {
    print_err "prepare bz commit is null:$commit" "$BISECT_LOG"
    usage
  }

  if [[ -e "${DEST}/bzImage_${commit}" ]]; then
    print_log "${DEST}/bzImage_${commit} exist, no need make" "$BISECT_LOG"
  else
    ${BASE_PATH}/make_bz.sh -k "$KERNEL_SRC" -m "$commit" -d "$DEST"
  fi

  [[ "$MAKE_RESULT" -eq 0 ]] || {
    if [[ "$commit" == "$COMMIT" ]]; then
      print_err "END ${DEST}/bzImage_${commit} failed, check ${DEST}/${BZ_LOG}" "$BISECT_LOG"
      exit 1
    fi
    if [[ "$commit" == "$START_COMMIT" ]]; then
      print_err "START ${DEST}/bzImage_${commit} failed, check ${DEST}/${BZ_LOG}" "$BISECT_LOG"
      exit 1
    fi
  }
}

# TODO: improve reproduce step next step
repro_bz() {
  if [[ -z "$REPRO_C" ]]; then
    do_cmd "ssh -o ConnectTimeout=1 -p $PORT localhost 'ls -ltr $REPRO'"
    do_cmd "ssh -o ConnectTimeout=1 -p $PORT localhost 'ls -ltr $REPRO_FILE'"
  else
    [[ -e "$REPRO_C" ]] || {
      print_err "$REPRO_C is not exist" "$BISECT_LOG"
      exit 1
    }
    do_cmd "scp -P $PORT ${BASE_PATH}/${REPRO_SH} root@localhost:/root/${REPRO_SH}"
    sleep 1
    do_cmd "scp -P $PORT $REPRO_C root@localhost:/root/$REPRO_C_FILE"
    sleep 1
  fi

  do_cmd "ssh -o ConnectTimeout=1 -p $PORT localhost 'ls $REPRO'"
  print_log "ssh -o ConnectTimeout=1 -p $PORT localhost '$REPRO'"
  ssh -o ConnectTimeout=1 -p $PORT localhost "$REPRO" &
}

check_bz_result() {
  local bz_file=$1
  local dmesg_file=$2
  local dmesg_info=""
  local cp_result=""

  dmesg_info=$(cat $dmesg_file)
  [[ -n "$dmesg_info" ]] || {
    print_err "dmesg info is null:$dmesg_info, could not judge!" "$BISECT_LOG"
    exit 1
  }

  cp_result=$(cat $dmesg_file | grep -i "$POINT")
  if [[ -z "$cp_result" ]]; then
    print_log "$bz_file didn't contain $POINT:$cp_result in dmesg, pass" "$BISECT_LOG"
    COMMIT_RESULT="$PASS"
  else
    print_log "$bz_file contained $POINT:$cp_result, FAIL" "$BISECT_LOG"
    COMMIT_RESULT="$FAIL"
  fi
}

test_bz() {
  local bz_file=$1
  local commit=$2

  clean_old_vm
  print_log "Run $bz_file with image:$IMAGE in local port:$PORT" "$BISECT_LOG"
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
    2>&1 | tee > ${DMESG_FOLDER}/${commit}_dmesg.log &
  sleep "$BOOT_TIME"

  repro_bz
  sleep "$TIME"

  check_bz_result "$bz_file" "${DMESG_FOLDER}/${commit}_dmesg.log"
}

test_commit() {
  local commit=$1
  COMMIT_RESULT=""

  prepare_bz "$commit"
  if [[ "$MAKE_RESULT" -eq 0 ]]; then
    test_bz "${DEST}/bzImage_${commit}" "$commit"
    if [[ -z "$COMMIT_RESULT" ]]; then
      print_err "After test $commit, result is null:$COMMIT_RESULT" "$BISECT_LOG"
      exit 1
    fi
  else
    COMMIT_RESULT="$SKIP"
  fi
  print_log "$commit $COMMIT_RESULT" "$BI_LOG"
  clean_old_vm
}

bisect_bz() {
  local commit=""
  local commit_c=""
  local steps=""
  local bisect_info=""
  local i=""

  do_cmd "cd $KERNEL_SRC"
  # Init next cycle make bzimage log
  echo >> ${DEST}/${BZ_LOG}
  echo "-------------------------------------------------------" >> ${DEST}/${BZ_LOG}
  echo >> ${DEST}/${BZ_LOG}

  # Check END COMMIT should test FAIl
  test_commit "$COMMIT"
  if [[ "$COMMIT_RESULT" == "$PASS" ]]; then
    print_err "-END- commit $COMMIT test PASS unexpectedly!" "$BISECT_LOG"
    clean_old_vm
    exit 1
  else
    print_log "-END- commit $COMMIT FAIL $COMMIT_RESULT" "$BISECT_LOG"
  fi

  # Check START COMMIT should test PASS, other wise will stop(TODO for next)
  test_commit "$START_COMMIT"
  if [[ "$COMMIT_RESULT" == "$PASS" ]]; then
    print_log "Start commit $COMMIT PASS $COMMIT_RESULT" "$BISECT_LOG"
  else
    print_log "Srart commit $COMMIT FAIL, will stop!" "$BISECT_LOG"
    clean_old_vm
    exit 0
  fi

  # Set up bad with end commit, good with start commit
  do_cmd "git checkout -f $COMMIT"
  do_cmd "git bisect start"
  do_cmd "git bisect bad $COMMIT"

  # should not bisect more than 99 steps
  for ((i=0; i<=100; i++)); do
    cd $KERNEL_SRC
    commit=""
    commit_c=""
    bisect_info=""
    bisect_end=""

    [[ "$i" -eq 0 ]] && {
      print_log "Bisect first start commit:$START_COMMIT"
      NEXT_COMMIT=$START_COMMIT
    }

    bisect_info=$(git bisect $COMMIT_RESULT $NEXT_COMMIT)
    [[ -n "$bisect_info" ]] || {
      print_err "No bisect_info:$bisect_info" "$BISECT_LOG"
      exit 1
    }
    bisect_end=$(echo "$bisect_info" | grep "is the first bad commit")
    [[ -z "$bisect_end" ]] || {
      print_log "Bisect PASS: find $bisect_end" "$BISECT_LOG"
      do_cmd "git bisect log >> $BI_LOG"
      do_cmd "git bisect log >> $BISECT_LOG"
      exit 0
    }
    steps=$(echo "$bisect_info" | grep step)
    [[ -n "$steps" ]] \
      || print_log "WARN: no steps when start commit $START_COMMIT:$steps" "$BISECT_LOG"
    commit_c=$(echo "$bisect_info" \
            | grep "^\[" \
            | awk -F '[' '{print $2}' \
            | awk -F ']' '{print $1}')
    commit=$(git log -1 | grep ^commit | cut -d ' ' -f 2)
    if [[ "$commit" == "$commit_c" ]]; then
      print_log "$commit is same as bisect tip commit_c:$commit_c"
      NEXT_COMMIT=$commit
    else
      print_err "$commit is not same as bisect tip commit_c:$commit_c" "$BISECT_LOG"
      exit 1
    fi
    test_commit "$NEXT_COMMIT"
  done
}


# Set detault value
: "${TIME:=20}"
: "${NUM:=0}"
: "${IMAGE:=/root/image/stretch2.img}"
while getopts :k:m:s:d:p:t:i:n:r:h arg; do
  case $arg in
    k)
      KERNEL_SRC=$OPTARG
      ;;
    m)
      COMMIT=$OPTARG
      ;;
    s)
      START_COMMIT=$OPTARG
      ;;
    d)
      DEST=$OPTARG
      ;;
    p)
      POINT=$OPTARG
      ;;
    t)
      TIME=$OPTARG
      ;;
    i)
      IMAGE=$OPTARG
      ;;
    n)
      NUM=$OPTARG
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


main() {
  parm_check
  bisect_prepare
  bisect_bz
}

main
