#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the bzImage script

source "bisect_common.sh"

KCONFIG_NAME="kconfig"
STATUS=""

#KCONFIG="https://raw.githubusercontent.com/xupengfe/kconfig_diff/main/config-5.13i_kvm"
KCONFIG="https://raw.githubusercontent.com/xupengfe/kconfig_diff/main/config-5.18rc4i_kvm"
DATE_START=$(date +"$TIME_FMT")
DATE_SS=$(date +%s)
DATE_END=""
DATE_ES=""
USE_SEC=""

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-c KCONFIG][-d DEST][-b bad][-f bz][-o][-h]
  -k  KERNEL source folder
  -m  COMMIT ID which will be used
  -c  Kconfig(optional) which will be used
  -d  Destination where bzImage will be copied
  -b  Bad commit
  -f  bzImage file name(optional)
  -o  Make kernel path
  -h  show this
__EOF
  echo "make_bz.sh parm invalid" > $RESULT_FILE
  exit 1
}

do_cmd() {
  local cmd=$*
  local result=""

  print_log "CMD=$cmd" "$STATUS"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    print_log "$CMD FAIL. Return code is $result" "$STATUS"
    echo "$CMD FAIL. Return code is $result" > $RESULT_FILE
    exit $result
  fi
}

parm_check() {
  # clean old RESULT_FILE
  rm -rf $RESULT_FILE
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
  print_log "parm check: KERNEL_SRC=$KERNEL_SRC COMMIT=$COMMIT DEST=$DEST $STATUS, BAD:$BAD_COMMIT" "$STATUS"
  echo "0" > $MAKE_RESULT
}

# Prepare the kconfig and checkout commit and revert action if needed
prepare_kconfig() {
  local kernel_target_folder=$1
  local bad_commit=$2
  local commit_short=""
  local bad_commit_short=""
  local revert_status=""
  local http=""

  do_cmd "cd $kernel_target_folder"

  do_cmd "cp -rf $BASE_PATH/kconfig_kvm.sh ./"
  source /etc/environment
  http=$(env | grep http)
  print_log "http: $http" "$STATUS"
  do_cmd "wget $KCONFIG -O $KCONFIG_NAME"
  #commit_short=$(echo ${COMMIT:0:12})
  #print_log "commit 0-12:$commit_short"
  #do_cmd "./kconfig_kvm.sh $KCONFIG_NAME \"CONFIG_LOCALVERSION\" CONFIG_LOCALVERSION=\\\"-${commit_short}\\\""

  print_log "git checkout -f $COMMIT" "$STATUS"
  do_cmd "git checkout -f $COMMIT"
  if [[ -n "$bad_commit" ]]; then
    print_log "There was bad commit:$bad_commit, will revert it" "$STATUS"
    do_cmd "git show $bad_commit | head -n 20"
    git revert -n $bad_commit
    [[ $? -eq 0 ]] || {
      print_err "git revert $bad_commit failed! Could not make!" "$STATUS"
      echo "git revert $bad_commit failed" > $RESULT_FILE
      exit 1
    }
    revert_status=$(git status)
    print_log "revert status: $revert_status" "$STATUS"

    # there is bad commit, will change name to commit-badcommit-revert
    commit_short=$(echo ${COMMIT:0:12})
    bad_commit_short=$(echo ${bad_commit:0:12})
    commit_short="${commit_short}-${bad_commit_short}-revert"
    print_log "commit revert:$commit_short"
  else
    # no bad commit revert, will use commit 0:12
    commit_short=$(echo ${COMMIT:0:12})
    print_log "commit 0-12:$commit_short"
  fi

  do_cmd "./kconfig_kvm.sh $KCONFIG_NAME \"CONFIG_LOCALVERSION\" CONFIG_LOCALVERSION=\\\"-${commit_short}\\\""
  do_cmd "cp -rf ${KCONFIG_NAME}_kvm .config"
  do_cmd "cat .config | grep CONFIG_LOCALVERSION"
  do_cmd "make olddefconfig"
}

make_bzimage() {
  local kernel_target_folder=$1
  local cpu_num=""
  local tmp_size=""
  local tmp_g=""
  local tmp_num=""
  local result_make=""

  tmp_size=$(df -Ph $UPPER_KERNEL_PATH | tail -n 1 | awk -F ' ' '{print $4}')
  tmp_g=$(echo $tmp_size | grep G)
  [[ -n "$tmp_g" ]] || {
    print_log "Less than 1G size in folder:$UPPER_KERNEL_PATH" "$STATUS"
    echo "No enough size in $UPPER_KERNEL_PATH" > $RESULT_FILE
    exit 1
  }
  tmp_num=$(echo $tmp_size | cut -d 'G' -f 1)
  [[ "$tmp_num" -le "8" ]] && {
    print_log "$UPPER_KERNEL_PATH available size is less than 8G, please make sure enough space to make kernel!" "$STATUS"
    echo "$UPPER_KERNEL_PATH available size is less than 8G" > $RESULT_FILE
    exit 1
  }

  cpu_num=$(cat /proc/cpuinfo | grep processor | wc -l)
  # avoid adl make kernel failed
  ((cpu_num-=4))
  do_cmd "cd $kernel_target_folder"
  print_log "make -j1 bzImage" "$STATUS"

  # make -j more threads cause make bzImage failed, so used j1 #TODO for more
  print_log "make -j1 bzImage for $COMMIT" "$STATUS"
  make -j1 bzImage 2>> "$STATUS"
  result_make=$?
  #do_cmd "make -j${cpu_num} bzImage"

  if [[ "$result_make" -eq 0 ]]; then
    if [[ -z "$BZIMAGE_FILE" ]]; then
      do_cmd "cp -rf ${kernel_target_folder}/arch/x86/boot/bzImage ${DEST}/bzImage_${COMMIT}"
      echo "Make ${DEST}/bzImage_${COMMIT} successfully" > $RESULT_FILE
    else
      print_log "Saved ${kernel_target_folder}/arch/x86/boot/bzImage into $BZIMAGE_FILE" $STATUS
      cp -rf ${kernel_target_folder}/arch/x86/boot/bzImage $BZIMAGE_FILE
      [[ $? -eq 0 ]] || {
        print_err "Saved $BZIMAGE_FILE failed, will save to ${DEST}/bzImage_${COMMIT}_${BAD_COMMIT}" $STATUS
        do_cmd "cp -rf ${kernel_target_folder}/arch/x86/boot/bzImage ${DEST}/bzImage_${COMMIT}_${BAD_COMMIT}"
      }
      echo "$BZIMAGE_FILE or ${DEST}/bzImage_${COMMIT}_${BAD_COMMIT} is ready" > $RESULT_FILE
    fi

    echo "0" > $MAKE_RESULT
    print_log "PASS: make bzImage pass" "$STATUS"
    echo "source_kernel:$KERNEL_SRC" >> $STATUS
    echo "target_kernel:$kernel_target_folder" >> $STATUS
    echo "commit:$COMMIT" >> $STATUS
    echo "kconfig_source:$KCONFIG" >> $STATUS
    echo "Destination:$DEST" >> $STATUS
    echo "bzImage:${DEST}/bzImage_${COMMIT}" >> $STATUS
    echo "DATE_START:$DATE_START" >> $STATUS
    DATE_END=$(date +"$TIME_FMT")
    DATE_ES=$(date +%s)
    echo "DATE_END:$DATE_END" >> $STATUS
    USE_SEC=$(( $DATE_ES - $DATE_SS ))

    print_log "Used $USE_SEC seconds" "$STATUS"
  else
    echo "1" > $MAKE_RESULT
    print_err "FAIL: make bzImage_${COMMIT} fail" "$STATUS"
    echo "make bzImage_${COMMIT} fail" > $RESULT_FILE
  fi

  do_cmd "rm -rf $NUM_FILE"
}

result=0
print_log "KERNEL_SRC:$KERNEL_SRC"
[[ -n "$KERNEL_SRC" ]] && [[ -n "$COMMIT" ]] && [[ -n "$DEST" ]] && result=1
print_log "result:$result"
if [[ "$result" == 1 ]]; then
  print_log "Get parm: KERNEL_SRC=$KERNEL_SRC COMMIT=$COMMIT DEST=$DEST"
else
  while getopts :k:m:c:d:b:f:o:h arg; do
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
      b)
        BAD_COMMIT=$OPTARG
        ;;
      f)
        BZIMAGE_FILE=$OPTARG
        ;;
      o)
        UPPER_KERNEL_PATH=$OPTARG
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

make_bz_img() {
  parm_check
  # Found the target commit and copy the kernel to UPPER_KERNEL_PATH
  prepare_kernel "$KERNEL_SRC" "$UPPER_KERNEL_PATH" "$COMMIT" "$STATUS"
  echo "$KERNEL_TARGET_PATH" > $MAKE_KSRC
  echo "echo $KERNEL_TARGET_PATH > $MAKE_KSRC" >> "$STATUS"
  # Prepare the kconfig and checkout commit and revert action if needed
  prepare_kconfig "$KERNEL_TARGET_PATH" "$BAD_COMMIT"
  make_bzimage "$KERNEL_TARGET_PATH"
}

make_bz_img
