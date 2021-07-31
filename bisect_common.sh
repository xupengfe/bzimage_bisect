#!/bin/bash

readonly PASS="good"
readonly FAIL="bad"

KERNEL_PATH="/root/kernel"
PATH_FILE="/tmp/base_path"
BASE_PATH=$(cat $PATH_FILE)
TIME_FMT="%m%d_%H%M%S"
COMMIT_RESULT=""
BZ_LOG="make_bz.log"
BISECT_LOG="bisect.log"
NUM_FILE="/tmp/make_num"
KERNEL_TARGET_PATH=""
NEXT_COMMIT=""
BI_LOG=""

print_log(){
  local log_info=$1
  local log_file=$2

  echo "|$(date +"$TIME_FMT")|$log_info|"
  [[ -z "$log_file" ]] \
    || echo "|$(date +"$TIME_FMT")|$log_info|" >> $log_file
}

print_err(){
  local log_info=$1
  local log_file=$2

  echo "|$(date +"$TIME_FMT")|FAIL|$log_info|"

  [[ -z "$log_file" ]] \
    || echo "|$(date +"$TIME_FMT")|FAIL|$log_info|" >> $log_file
}

prepare_kernel() {
  local kernel_folder=""
  local kernel_target_path=""
  local ret=""

  # Get last kernel source like /usr/src/os.linux.intelnext.kernel/
  kernel_folder=$(echo $KERNEL_SRC | awk -F "/" '{print $NF}')
  [[ -n "$kernel_folder" ]] || {
    kernel_folder=$(echo $KERNEL_SRC | awk -F "/" '{print $(NF-1)}')
    [[ -n "$kernel_folder" ]] || {
      print_err "FAIL: kernel_folder is null:$kernel_folder" "$STATUS"
      usage
    }
  }

  [[ -d "$KERNEL_SRC" ]] || {
    print_err "FAIL:KERNEL_SRC:$KERNEL_SRC folder is not exist" "$STATUS"
    usage
  }

  [[ -d "$KERNEL_PATH" ]] || {
    do_cmd "rm -rf $KERNEL_PATH"
    do_cmd "mkdir -p $KERNEL_PATH"
  }

  KERNEL_TARGET_PATH="${KERNEL_PATH}/${kernel_folder}"
  if [[ -d "$KERNEL_TARGET_PATH" ]]; then
    do_cmd "cd $KERNEL_TARGET_PATH"
    git checkout -f $COMMIT
    ret=$?
    if [[ "$ret" -eq 0 ]]; then
      print_log "git checkout -f $COMMIT pass, no need copy $KERNEL_SRC again" "$STATUS"
    else
      print_log "git checkout -f $COMMIT failed:$ret, will copy $KERNEL_SRC" "$STATUS"
      do_cmd "cp -rf $KERNEL_SRC $KERNEL_PATH"
    fi
  else
    do_cmd "cp -rf $KERNEL_SRC $KERNEL_PATH" "$STATUS"
  fi
}
