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
BOOT_TIME="20"
PORT="10022"
REPRO="/root/repro.sh"
BASE_PATH=$(pwd)
echo $BASE_PATH > $PATH_FILE

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-s][-d DEST][-p][-t][-i][-h]
  -k  KERNEL source folder
  -m  COMMIT(end) ID which will be used
  -s  Start COMMIT ID
  -d  Destination where bzImage will be copied
  -p  Check point in dmesg like "general protection"
  -t  Wait time(optional, default time like 20s)
  -i  Image file(optional, default is /root/image/stretch2.img)
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

parm_check() {
  [[ -d "$DEST" ]]  || {
    print_log "DEST:$DEST folder is not exist!"
    usage
  }
  BISECT_LOG="${DEST}/${BISECT_LOG}"
  cat /dev/null > $BISECT_LOG

  [[ -d "$KERNEL_SRC/.git" ]] || {
    print_err "$KERNEL_SRC doesn't contain .git folder" "$BISECT_LOG"
    usage
  }
  [[ -n  "$COMMIT" ]] || {
    print_err "commit:$COMMIT is null." "$BISECT_LOG"
    usage
  }
  [[ -n  "$START_COMMIT" ]] || {
    print_err "Start commit:$START_COMMIT is null." "$BISECT_LOG"
    usage
  }
  [[ -n "$POINT" ]] || {
    print_err "Check point:$POINT is null." "$BISECT_LOG"
    usage
  }
  [[ -e "$IMAGE" ]] || {
    print_err "IMAGE:$IMAGE is not exist" "$BISECT_LOG"
    usage
  }
  echo 0 > "$NUM_FILE"

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
  local check_commit=""

  do_cmd "cd $KERNEL_SRC"
  check_commit "$COMMIT"
  check_commit "$START_COMMIT"
  bisect_init
}

prepare_bz() {
  local commit=$1

  [[ -n "$commit" ]] || {
    print_err "prepare_bz commit is null:$commit" "$BISECT_LOG"
    usage
  }

  if [[ -e "${DEST}/bzImage_${commit}" ]]; then
    print_log "${DEST}/bzImage_${commit} exist, no need make" "$BISECT_LOG"
  else
    ${BASE_PATH}/make_bz.sh -k "$KERNEL_SRC" -m "$commit" -d "$DEST"
  fi

  [[ -e "${DEST}/bzImage_${commit}" ]] || {
    print_err "Make ${DEST}/bzImage_${commit} failed, check ${DEST}/${BZ_LOG}" "$BISECT_LOG"
    exit 1
  }
}

# TODO: improve reproduce step next step
repro_bz() {
  print_log "ssh -o ConnectTimeout=1 -p $PORT localhost '$REPRO'"
  ssh -o ConnectTimeout=1 -p $PORT localhost "$REPRO" &
}

check_bz_result() {
  local cp_result=""

  cp_result=$(ssh -o ConnectTimeout=1 -p $PORT localhost "dmesg | grep 'general pro' 2>/dev/null")
  if [[ -z "$cp_result" ]]; then
    ssh -o ConnectTimeout=1 -p 10022 localhost "uptime"
    if [[ $? -eq 0 ]]; then
      print_log "$bz_file connect ok and no $POINT, pass" "$BISECT_LOG"
      COMMIT_RESULT="$PASS"
    else
      print_log "WARN: $bz_file connect err, consider as reproduced, fail" "$BISECT_LOG"
      COMMIT_RESULT="$FAIL"
    fi
  else
    print_log "$bz_file contain $cp_result, FAIL" "$BISECT_LOG"
    COMMIT_RESULT="$FAIL"
  fi
}

test_bz() {
  local bz_file=$1

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
    2>&1 | > ${DEST}/vm.log &
  sleep "$BOOT_TIME"

  repro_bz
  sleep "$TIME"

  check_bz_result "$bz_file"
}

test_commit() {
  local commit=$1
  COMMIT_RESULT=""

  prepare_bz "$commit"
  test_bz "${DEST}/bzImage_${commit}"
  if [[ -z "$COMMIT_RESULT" ]]; then
    print_err "After test $commit, result is null:$COMMIT_RESULT" "$BISECT_LOG"
    exit 1
  fi
}

bisect_bz() {
  local commit=""

  do_cmd "git bisect start"
  # Init make bzimage log
  cat /dev/null > ${DEST}/${BZ_LOG}
  # Check END COMMIT should test FAIl
  test_commit "$COMMIT"
  if [[ "$COMMIT_RESULT" -eq 0 ]]; then
    print_err "-END- commit $COMMIT test PASS unexpectedly!" "$BISECT_LOG"
    clean_old_vm
    exit 1
  else
    print_log "-END- commit $COMMIT FAIL $COMMIT_RESULT" "$BISECT_LOG"
  fi

  # Check START COMMIT should test PASS, other wise will stop(TODO for next)
  test_commit "$START_COMMIT"
  if [[ "$COMMIT_RESULT" -eq 0 ]]; then
    print_log "Start commit $COMMIT PASS $COMMIT_RESULT" "$BISECT_LOG"
  else
    print_log "Srart commit $COMMIT FAIL, will stop!" "$BISECT_LOG"
    clean_old_vm
    exit 0
  fi

  # TODO bisect in while
}


# Set detault value
: "${TIME:=20}"
: "${IMAGE:=/root/image/stretch2.img}"
while getopts :k:m:s:d:p:t:i:h arg; do
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
