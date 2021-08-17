#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the bzImage and run this bzImage in syzkaller fuzzy test

source "bisect_common.sh"

KERNEL_PATH="/tmp/syzkaller"
KER_TARGET="/tmp/syzkaller/os.linux.intelnext.kernel"
RUNSYZ_LOG="runsyz.log"
RUN_COMMIT=""
IMAGE_FOLDER="/root/image"
MY_CFG="${IMAGE_FOLDER}/my.cfg"
BASE_PATH=$(pwd)
echo $BASE_PATH > $PATH_FILE

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-k] [-t TAG] [-d] [-i] [-h]
  -k  Kernel source (default /root/os.linux.intelnext.kernel)
  -t  TAG: git tag
  -d  DEST (default /home/bzimage/XXXTAG)
  -i  IMAGE (default /root/image/centos8.img)
  -h  Help
__EOF
  exit 2
}

do_cmd() {
  local cmd=$*
  local result=""

  print_log "CMD=$cmd"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    print_log "$CMD FAIL. Return code is $RESULT"
    print_log "$CMD FAIL. Return code is $RESULT" >> $RUNSYZ_LOG
    exit $result
  fi
}

prepare_kernel() {
  [[ -d "$KERNEL_SRC" ]] || {
    rm -rf $KERNEL_SRC
    do_cmd "git clone https://github.com/intel-innersource/os.linux.intelnext.kernel.git"
  }

  do_cmd "cd $KERNEL_SRC"
  print_log "git fetch origin $TAG" "$RUNSYZ_LOG"
  do_cmd "git fetch origin $TAG"
  do_cmd "git fetch origin"
  RUN_COMMIT=$(git log $TAG | head -n 1 | cut -d ' ' -f 2)
  [[ -n "$RUN_COMMIT" ]] || {
    print_err "Get $TAG commit:$RUN_COMMIT null, exit"
    exit 2
  }
}

run_syzkaller() {
  local ker_ori=""
  local bz_ori=""
  local ker_tar=""
  local bzimage=""

  bzimage="${DEST}/bzImage_${RUN_COMMIT}"
  [[ -e "$bzimage" ]] || {
    print_err "No $bzimage exist, exit" "$RUNSYZ_LOG"
    exit 1
  }
  ker_ori=$(cat $MY_CFG | grep "\"kernel_obj\"" | cut -d '"' -f 4)
  bz_ori=$(cat $MY_CFG | grep "\"kernel\"" | cut -d '"' -f 4)
  ker_tar=$(echo $KER_TARGET | grep "\"kernel\"" | cut -d '"' -f 4)
  ker_ori=$(echo $ker_ori | sed s/'\/'/'\\\/'/g)
  bz_ori=$(echo $bz_ori | sed s/'\/'/'\\\/'/g)

  bzimage=$(echo $bzimage | sed s/'\/'/'\\\/'/g)

  print_log "sed -i s/${ker_ori}/${ker_tar}/g $MY_CFG" "$RUNSYZ_LOG"
  sed -i s/"${ker_ori}"/"${ker_tar}"/g $MY_CFG
  print_log "sed -i s/${bz_ori}/${bzimage}/g $MY_CFG" "$RUNSYZ_LOG"
  sed -i s/"${bz_ori}"/"${bzimage}"/g $MY_CFG
  cat $MY_CFG
  cat $MY_CFG >> "$RUNSYZ_LOG"

  do_cmd "cd $IMAGE_FOLDER"
  do_cmd "syz-manager --config my.cfg"
}

run_syz() {
  [[ -e "$MY_CFG" ]] || {
    print_err "No $MY_CFG exist, exit"
    usage
  }

  DEST="${DEST}/${TAG}"
  [[ -d "$DEST" ]] || {
    print_log "$DEST folder is not exist, create it"
    print_log "rm -rf $DEST"
    rm -rf $DEST
    mkdir -p $DEST
    print_log "mkdir -p $DEST"
  }
  RUNSYZ_LOG="${DEST}/${RUNSYZ_LOG}"

  # Init next make bzimage log
  echo >> ${DEST}/${BZ_LOG}
  echo "-------------------------------------------------------" >> ${DEST}/${BZ_LOG}
  echo >> ${DEST}/${BZ_LOG}

  prepare_kernel

  if [[ -e "${DEST}/bzImage_${RUN_COMMIT}" ]]; then
    print_log "${DEST}/bzImage_${RUN_COMMIT} exist, no need make" "$RUNSYZ_LOG"
  else
    print_log "Make ${DEST}/bzImage_${RUN_COMMIT}, $KERNEL_SRC -> $KERNEL_PATH"
    ${BASE_PATH}/make_bz.sh -k "$KERNEL_SRC" -m "$RUN_COMMIT" -d "$DEST" -o "$KERNEL_PATH"
  fi

  run_syzkaller
}


# Set detault value
: "${KERNEL_SRC:=/root/os.linux.intelnext.kernel}"
: "${DEST:=/home/bzimage}"
: "${IMAGE:=/root/image/centos8.img}"
while getopts :k:t:d:i:h arg; do
  case $arg in
    k)
      KERNEL_SRC=$OPTARG
      ;;
    t)
      TAG=$OPTARG
      [[ -n "$TAG" ]] || {
        print_err "TAG:$TAG is null, exit"
        usage
      }
      ;;
    d)
      DEST=$OPTARG
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

run_syz
