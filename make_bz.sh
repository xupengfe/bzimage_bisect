#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the bzImage script

set -e

source "bisect_common.sh"

KCONFIG_NAME="kconfig"
RESULT=""
STATUS=""

KCONFIG="https://raw.githubusercontent.com/xupengfe/kconfig_diff/main/config-5.13i_kvm"
DATE_START=$(date +"$TIME_FMT")
DATE_SS=$(date +%s)
DATE_END=""
DATE_ES=""
USE_SEC=""

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-c KCONFIG][-d DEST][-h]
  -k  KERNEL source folder
  -m  COMMIT ID which will be used
  -c  Kconfig(optional) which will be used
  -d  Destination where bzImage will be copied
  -h  show this
__EOF
  exit 1
}

do_cmd() {
  local cmd=$*
  local result=""

  print_log "CMD=$cmd"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    print_log "$CMD FAIL. Return code is $RESULT"
    print_log "$CMD FAIL. Return code is $RESULT" >> $STATUS
    exit $result
  fi
}

parm_check() {
  [[ -d "$DEST" ]]  || {
    print_log "DEST:$DEST folder is not exist!"
    usage
  }
  STATUS="${DEST}/${BZ_LOG}"

  [[ -d "$KERNEL_SRC/.git" ]] || {
    print_err "$KERNEL_SRC doesn't contain .git folder" "$STATUS"
    usage
  }
  [[ -n  "$COMMIT" ]] || {
    print_err "commit:$COMMIT is null." "$STATUS"
    usage
  }
  [[ -f "$BASE_PATH/kconfig_kvm.sh" ]] || {
    print_err "no kconfig_kvm.sh in $BASE_PATH" "$STATUS"
    print_log "Plase put https://raw.githubusercontent.com/xupengfe/kconfig_diff/main/kconfig_kvm.sh into $BASE_PATH"
    usage
  }
  print_log "parm check: KERNEL_SRC=$KERNEL_SRC COMMIT=$COMMIT DEST=$DEST $STATUS"
}

prepare_kconfig() {
  local commit_short=""
  local make_num=""

  do_cmd "cd $KERNEL_TARGET_PATH"
  make_num=$(cat $NUM_FILE)
  if [[ "$make_num" -eq 0 ]]; then
    print_log "First time make bzImage, clean it" "$STATUS"
    do_cmd "make distclean"
    do_cmd "git clean -fdx"
  fi
  ((make_num+=1))
  do_cmd "echo $make_num > $NUM_FILE"

  do_cmd "cp -rf $BASE_PATH/kconfig_kvm.sh ./"
  do_cmd "wget $KCONFIG -O $KCONFIG_NAME"
  commit_short=$(echo ${COMMIT:0:12})
  print_log "commit 0-12:$commit_short"
  do_cmd "./kconfig_kvm.sh $KCONFIG_NAME \"CONFIG_LOCALVERSION\" CONFIG_LOCALVERSION=\\\"-${commit_short}\\\""
  do_cmd "cp -rf ${KCONFIG_NAME}_kvm .config"
  do_cmd "git checkout -f $COMMIT"
  do_cmd "make olddefconfig"
}

make_bzimage() {
  local cpu_num=""
  local tmp_size=""
  local tmp_g=""
  local tmp_num=""

  tmp_size=$(df -Ph /tmp | tail -n 1 | awk -F ' ' '{print $4}')
  tmp_g=$(echo $tmp_size | grep G)
  [[ -n "$tmp_g" ]] || {
    print_log "No G in tmp_size:$tmp_size" "$STATUS"
    exit 1
  }
  tmp_num=$(echo $tmp_size | cut -d 'G' -f 1)
  [[ "$tmp_num" -le "8" ]] && {
    print_log "/tmp available size is less than 8G, please make sure enough space to make kernel!" "$STATUS"
    exit 1
  }

  cpu_num=$(cat /proc/cpuinfo | grep processor | wc -l)
  do_cmd "cd $KERNEL_TARGET_PATH"
  print_log "make -j${cpu_num} bzImage" "$STATUS"
  do_cmd "make -j${cpu_num} bzImage"
  do_cmd "cp -rf ${KERNEL_TARGET_PATH}/arch/x86/boot/bzImage ${DEST}/bzImage_${COMMIT}"
  print_log "PASS: make bzImage pass"
  print_log "PASS: make bzImage pass" >> $STATUS
  echo "source_kernel:$KERNEL_SRC" >> $STATUS
  echo "target_kernel:$KERNEL_TARGET_PATH" >> $STATUS
  echo "commit:$COMMIT" >> $STATUS
  echo "kconfig_source:$KCONFIG" >> $STATUS
  echo "Destination:$DEST" >> $STATUS
  echo "bzImage:${DEST}/bzImage_${COMMIT}" >> $STATUS
  echo "DATE_START:$DATE_START" >> $STATUS
  DATE_END=$(date +"$TIME_FMT")
  DATE_ES=$(date +%s)
  echo "DATE_END:$DATE_END" >> $STATUS
  USE_SEC=$(( $DATE_ES - $DATE_SS ))
  echo "Used seconds:$USE_SEC sec" >> $STATUS
  print_log "Used $USE_SEC seconds"
}

result=0
print_log "KERNEL_SRC:$KERNEL_SRC"
[[ -n "$KERNEL_SRC" ]] && [[ -n "$COMMIT" ]] && [[ -n "$DEST" ]] && result=1
print_log "result:$result"
if [[ "$result" == 1 ]]; then
  print_log "Get parm: KERNEL_SRC=$KERNEL_SRC COMMIT=$COMMIT DEST=$DEST"
else
  while getopts :k:m:c:d:h arg; do
    case $arg in
      k)
        KERNEL_SRC=$OPTARG
        ;;
      m)
        COMMIT=$OPTARG
        ;;
      c)
        KCONFIG=$OPTARG
        ;;
      d)
        DEST=$OPTARG
        ;;
      h)
        usage
        ;;
      *)
        usage
        ;;
    esac
  done
fi

main() {
  parm_check
  prepare_kernel
  prepare_kconfig
  make_bzimage
}

main
