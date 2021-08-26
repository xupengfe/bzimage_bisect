#!/bin/bash

readonly PASS="good"
readonly FAIL="bad"
readonly SKIP="skip"
readonly NULL="null"
readonly S_PASS="pass"
readonly S_FAIL="fail"
readonly BISECT_CSV="/root/image/bisect.csv"
readonly BISECT_BAK="/opt/bisect_bak.csv"

readonly KERNEL_PATH="/tmp/kernel"
PATH_FILE="/tmp/base_path"
[[ -e "$PATH_FILE" ]] && BASE_PATH=$(cat $PATH_FILE)
TIME_FMT="%m%d_%H%M%S"
COMMIT_RESULT=""
BZ_LOG="make_bz.log"
BISECT_LOG="bisect.log"
NUM_FILE="/tmp/make_num"
KERNEL_TARGET_PATH=""
NEXT_COMMIT=""
BI_LOG=""
# MAKE_RESULT just record 0 for pass, 1 for fail
MAKE_RESULT="/tmp/makebz_result"
# Make bz failed short description
RESULT_FILE="/root/make_bz_short_result.log"

do_common_cmd() {
  local cmd=$*
  local result=""

  echo "CMD=$cmd"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    echo "$CMD FAIL. Return code is $result"
    exit $result
  fi
}

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

copy_kernel() {
  local ker_src=$1
  local ker_path=$2
  local log_file=$3
  local kernel_folder=""
  local ker_tar_path=""

  [[ -d "$ker_src" ]] || {
    print_err "copy kernel:ker_src:$ker_src folder is not exist" "$log_file"
    usage
  }

  [[ -d "$ker_path" ]] || {
    do_common_cmd "rm -rf $ker_path"
    do_common_cmd "mkdir -p $ker_path"
  }

  kernel_folder=$(echo $KERNEL_SRC | awk -F "/" '{print $NF}')
  [[ -n "$kernel_folder" ]] || {
    kernel_folder=$(echo $KERNEL_SRC | awk -F "/" '{print $(NF-1)}')
    [[ -n "$kernel_folder" ]] || {
      print_err "copy kernel: kernel_folder is null:$kernel_folder" "$log_file"
      usage
    }
  }

  ker_tar_path="${ker_path}/${kernel_folder}"

  do_common_cmd "rm -rf $ker_tar_path"
  do_common_cmd "cp -rf $ker_src $ker_path"
}

prepare_kernel() {
  local ker_src=$1
  local ker_path=$2
  local commit=$3
  local log_file=$4
  local kernel_folder=""
  local kernel_target_path=""
  local ret=""
  local make_num=""
  local tag=""

  # Get last kernel source like /usr/src/os.linux.intelnext.kernel/
  kernel_folder=$(echo $ker_src | awk -F "/" '{print $NF}')
  [[ -n "$kernel_folder" ]] || {
    kernel_folder=$(echo $ker_src | awk -F "/" '{print $(NF-1)}')
    [[ -n "$kernel_folder" ]] || {
      print_err "FAIL: kernel_folder is null:$kernel_folder" "$log_file"
      usage
    }
  }

  [[ -d "$ker_src" ]] || {
    print_err "FAIL:KERNEL_SRC:$ker_src folder is not exist" "$log_file"
    usage
  }

  [[ -d "$ker_path" ]] || {
    do_common_cmd "rm -rf $ker_path"
    do_common_cmd "mkdir -p $ker_path"
  }

  [[ -e "$NUM_FILE" ]] && make_num=$(cat $NUM_FILE)
  KERNEL_TARGET_PATH="${ker_path}/${kernel_folder}"
  if [[ -d "$KERNEL_TARGET_PATH" ]]; then
    print_log "cd $KERNEL_TARGET_PATH" "$log_file"
    do_common_cmd "cd $KERNEL_TARGET_PATH"
    print_log "Show commit $commit" "$log_file"

    ret=$(git show "$commit" 2>/dev/null | head -n 1)
    if [[ -n "$ret" ]]; then
      print_log "check $commit pass:$ret, no need copy $ker_src again" "$log_file"
    else
      tag=$(git ls-remote | grep $commit \
            | awk -F "/" '{print $NF}' \
            | tail -n 1)
      if [[ -n "$tag" ]]; then
        print_log "Could fetch $commit in $KERNEL_TARGET_PATH" "$log_file"
        git fetch origin $tag
        git fetch origin
      else
        print_log "No $commit commit:$ret, will copy $ker_src" "$log_file"
        copy_kernel "$ker_src" "$ker_path" "$log_file"
      fi
    fi
  else
    copy_kernel "$ker_src" "$ker_path" "$log_file"
    ((make_num+=1))
    do_cmd "echo $make_num > $NUM_FILE"
  fi

  if [[ "$make_num" -eq 0 ]]; then
    print_log "First time make bzImage, copy and clean it" "$log_file"
    copy_kernel "$ker_src" "$ker_path" "$log_file"
    do_common_cmd "cd $KERNEL_TARGET_PATH"
    do_common_cmd "make distclean"
    do_common_cmd "git clean -fdx"
  fi
  ((make_num+=1))
  print_log "make_num:$make_num" "$log_file"
  do_common_cmd "echo $make_num > $NUM_FILE"
}
