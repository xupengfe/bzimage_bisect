#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Bisect bzImage automation script, which need kconfig_kvm.sh & make_bz.sh
# bs means bzImage

BISECT_SCRIPT_FOLDER="/root/bzimage_bisect"
export PATH=${PATH}:$BISECT_SCRIPT_FOLDER
source "bisect_common.sh"

TIME_FMT="%m%d_%H%M%S"
BISECT_START_TIME=$(date +"$TIME_FMT")
BISECT_SS=$(date +%s)
BISECT_END_TIME=""
BISECT_ES=""
USE_SEC=""
DMESG_FOLDER=""
BOOT_TIME="25"
PORT="10022"
REPRO="/root/repro.sh"
REPRO_SH="repro.sh"
REPRO_C_FILE="repro.c"
REPRO_FILE="/root/repro.c"
BZ_ORIGIN_LOG="/root/bisect_bz.log"
HTML_FOLDER="/var/www/html/"
IMAGE_BAK="/root/image/centos8_3.img"

# need to fill below 4 items in ONE_LINE
MAIN_RESULT=""
BI_RESULT=""
BAD_COMMIT=""
BI_COMMENT=""
ONE_LINE=""
ISSUE_HASH=""
# reproduce time should be less or equal than 3600s in theory
MAX_LOOP_TIME=720
EVERY_LOOP_TIME=5
BASE_PATH=$BISECT_SCRIPT_FOLDER
echo $BASE_PATH > $PATH_FILE
BI_INFO_LOG=""

fill_one_line() {
  local item=$1

  case $item in
    hash_3)
      if [[ -z "$ISSUE_HASH" ]]; then
        print_err "ISSUE_HASH:$ISSUE_HASH is null!" "$BISECT_LOG"
        ONE_LINE="$NULL"
      else
        ONE_LINE="$ISSUE_HASH"
      fi
      ONE_LINE="$ONE_LINE,$COMMIT,$DMESG_FOLDER"
      ;;
    rep_time)
      ONE_LINE="$ONE_LINE,$TIME"
      ;;
    bi_result)
      ONE_LINE="$ONE_LINE,$MAIN_RESULT,$BI_RESULT,$BAD_COMMIT,$BI_COMMENT"
      ;;
    *)
      print_err "invalid item:$item!!! Ignore" "$BISECT_LOG"
      ;;
  esac
}

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
  BI_RESULT="$S_FAIL"
  # chek ONE_LINE is null, will fill hash_3
  [[ -z "$ONE_LINE" ]] && fill_one_line "hash_3"
  [[ -z "$TIME" ]] && fill_one_line "rep_time"
  [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
  [[ -z "$BI_RESULT" ]] && BI_RESULT="$S_FAIL"
  [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
  BI_COMMENT="Invalid parm in bisect_bz.sh"

  fill_one_line "bi_result"
  echo "$ONE_LINE" >> $BISECT_CSV

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

  print_log "CMD=$cmd" "$BISECT_LOG"

  eval "$cmd"
  result=$?
  if [[ $result -ne 0 ]]; then
    print_log "$CMD FAIL. Return code is $result" "$BISECT_LOG"
    # Bisect all detailed info for debug
    git bisect log 2>/dev/null >> "$BISECT_LOG"
    # Short bisect info log to report
    git bisect log 2>/dev/null >> "$BI_INFO_LOG"

    # chek ONE_LINE is null, will fill hash_3
    [[ -z "$ONE_LINE" ]] && fill_one_line "hash_3"
    [[ -z "$TIME" ]] && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_RESULT="$S_REBI"
    [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
    BI_COMMENT="bisect_bz cmd $CMD FAIL:$result"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> "$BISECT_CSV"

    clean_old_vm
    exit $result
  fi
}

prepare_dmesg_folder() {
  local issue_info=""

  issue_info=$(echo $POINT | tr ' ' '_')
  issue_info=$(echo $issue_info | tr "'" '_')
  issue_info=$(echo $issue_info | tr "/" '_')
  DMESG_FOLDER="${DEST}/${BISECT_START_TIME}_${issue_info}"
  print_log "Prepare $DMESG_FOLDER" "$BISECT_LOG"
  if [[ -e "$DMESG_FOLDER" ]]; then
    do_cmd "rm -rf $DMESG_FOLDER"
    do_cmd "mkdir -p "$DMESG_FOLDER""
  else
    do_cmd "mkdir -p "$DMESG_FOLDER""
  fi

  if [[ -e "$BISECT_CSV" ]]; then
    print_log "$BISECT_CSV exist" "$BISECT_LOG"
  else
    print_log "There is no $BISECT_CSV exist, create header" "$BISECT_LOG"
    echo "bi_hash,bi_commit,bi_path,rep_time,mainline_result,bisect_result,bad_commit,bi_comment" >> $BISECT_CSV
  fi
  # Will fill bi_hash,bi_commit,bi_path 3 items
  fill_one_line "hash_3"
}

parm_check() {
  [[ -d "$DEST" ]]  || {
    print_log "DEST:$DEST folder does not exist!" "$BZ_ORIGIN_LOG"
    usage
  }

  [[ -d "$KERNEL_SRC/.git" ]] || {
    print_err "$KERNEL_SRC doesn't contain .git folder" "$BZ_ORIGIN_LOG"
    usage
  }
  [[ -n  "$COMMIT" ]] || {
    print_err "commit:$COMMIT is null." "$BZ_ORIGIN_LOG"
    usage
  }
  [[ -n  "$START_COMMIT" ]] || {
    print_err "Start commit:$START_COMMIT is null." "$BZ_ORIGIN_LOG"
    usage
  }
  [[ -n "$POINT" ]] || {
    print_err "Check point:$POINT is null." "$BZ_ORIGIN_LOG"
    usage
  }
  [[ -e "$IMAGE" ]] || {
    print_err "IMAGE:$IMAGE does not exist" "$BZ_ORIGIN_LOG"
    usage
  }
  echo $NUM > "$NUM_FILE"

  if [[ "$START_COMMIT" == "$NULL" ]]; then
    DMESG_FOLDER="$NULL"
    fill_one_line "hash_3"

    fill_one_line "rep_time"
    MAIN_RESULT="$NULL"
    # Don't infinite loop in no commit hash, so fail it.
    BI_RESULT="$S_FAIL"
    BAD_COMMIT="$NULL"
    BI_COMMENT="No END COMMIT"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  fi

  prepare_dmesg_folder
  BISECT_LOG="${DMESG_FOLDER}/${BISECT_LOG}"
  BI_INFO_LOG="${DMESG_FOLDER}/${BI_INFO}"
  BI_LOG="${DEST}/bi.log"
  cat /dev/null > "$BISECT_LOG"
  cat /dev/null > "$BI_INFO_LOG"
  echo  >> "$BI_LOG"
  echo "-------------------------------------------------------" >> "$BI_LOG"
  echo >> "$BI_LOG"
  print_log " $DMESG_FOLDER" >> "$BI_LOG"

  print_log "PARM KER:$KERNEL_SRC|END:$COMMIT|start:$START_COMMIT|DEST:$DEST|CP:$POINT|IMG:$IMAGE|TIME:$TIME"
  export PATH="${PATH}:$BASE_PATH"
}

update_mainline_repro() {
  local day_file=""
  local issue_folder=""
  local c_file=""
  local mtag=""

  [[ -z "$ISSUE_HASH" ]] && \
    print_err "ISSUE_HASH:$ISSUE_HASH is null!" "$BISECT_LOG"
  day_file=$(date +%Y_%m_%d)
  issue_folder="${HTML_FOLDER}/syzkaller/${day_file}/${ISSUE_HASH}"
  if [[ -d "$issue_folder" ]]; then
    print_log "issue_folder alreayd exist:$issue_folder" "$BISECT_LOG"
  else
    do_cmd "rm -rf $issue_folder"
    do_cmd "mkdir -p $issue_folder"
  fi

  echo "$TIME" > "${issue_folder}/rep_time"
  echo "$TIME" > "${DMESG_FOLDER}/rep_time"

  c_file=$(echo $REPRO_C | awk -F "/" '{print $NF}' | cut -d '.' -f 1)
  do_cmd "cp -rf $REPRO_C ${issue_folder}/${c_file}.c"
  cp -rf "$REPRO_C" "${DMESG_FOLDER}/${c_file}.c"

  print_log "gcc -pthread ${issue_folder}/${c_file}.c -o ${issue_folder}/repro"
  gcc -pthread ${issue_folder}/${c_file}.c -o ${issue_folder}/repro
  gcc -pthread ${issue_folder}/${c_file}.c -o ${DMESG_FOLDER}/repro

  if [[ -e "${SYZ_FOLDER}/${ISSUE_HASH}/description" ]]; then
    do_cmd "cp -rf ${SYZ_FOLDER}/${ISSUE_HASH}/description $issue_folder"
    cp -rf "${SYZ_FOLDER}/${ISSUE_HASH}/description" "${DMESG_FOLDER}/description"
  else
    print_err "${SYZ_FOLDER}/${ISSUE_HASH}/description does not exist!"
  fi

  echo "$POINT" > "${issue_folder}/keyword"
  echo "$POINT" > "${DMESG_FOLDER}/keyword"

  # Get the proxy for wget, even wget failed, will not impact bisect
  source /etc/environment
  wget $KCONFIG_ORI -O ${DMESG_FOLDER}/kconfig_origin
  print_log "wget $KCONFIG_ORI -O ${DMESG_FOLDER}/kconfig_origin:$?" "$BISECT_LOG"

  do_cmd "cd $KERNEL_SRC"
  mtag=$(git show-ref --tags --dereference \
        | grep "$START_COMMIT" \
        | awk -F "/" '{print $NF}' \
        | cut -d '^' -f 1)
  if [[ -z "$mtag" ]]; then
    print_err "Get $START_COMMIT in $KERNEL_SRC mtag is null"
  else
    echo "$mtag" > "${issue_folder}/mtag"
  fi
}

check_commit() {
  local commit=$1
  local check_result=""

  check_result=$(git log "$commit" | grep "^commit" | head -n 1 2>/dev/null)
  print_log "git log $commit check_result:$check_result" "$BISECT_LOG"
  [[ -n "$check_result" ]] || {
    print_err "There is no $commit info in $(pwd)" "$BISECT_LOG"
    usage
  }
}

bisect_init() {
  local old_bisect=""

  old_bisect=$(git bisect log 2>/dev/null)
  [[ -z "$old_bisect" ]] || {
    print_log "There was old bisect log:$old_bisect, will clean it" "$BISECT_LOG"
    do_cmd "git bisect reset"
  }
  do_cmd "git checkout -f $COMMIT"
}

bisect_prepare() {
  do_cmd "cd $KERNEL_SRC"
  check_commit "$COMMIT"
  check_commit "$START_COMMIT"
  bisect_init
}

check_time() {
  local dmesg_file=$1
  local result=""
  local time=""

  [[ -e "$dmesg_file" ]] || {
    print_err "dmesg_file:$dmesg_file does not exist" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    [[ -z "$BI_RESULT" ]] && BI_RESULT="$S_FAIL"
    [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
    BI_COMMENT="dmesg :$dmesg_file does not exist"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  }

  result=$(cat $dmesg_file | grep "$POINT" | head -n 1)
  [[ -n "$result" ]] || {
    print_err "No $POINT dmesg info:$result" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    [[ -z "$BI_RESULT" ]] && BI_RESULT="$S_FAIL"
    BAD_COMMIT="$NULL"
    BI_COMMENT="No $POINT find in time check dmesg:$dmesg_file"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  }

  time=$(echo "$result" | awk -F " " '{print $2}' | cut -d '.' -f 1)
  print_log "Found time:$time in $dmesg_file" "$BISECT_LOG"
  if [[ "$time" -le 25 ]]; then
    # Met TIME 0.23s to reproduce, it's better add 5 in 0-25s
    TIME=$((time+25))
  elif [[ "$time" -le 60 ]]; then
    TIME=$((time+120))
  else
    # For long time to reproduce, add more time to avoid fake judgement
    TIME=$((time+1800))
  fi
  print_log "Logic: |<=25: +25|25-60 +120|>60 +1800| Set TIME:$TIME" "$BISECT_LOG"
  fill_one_line "rep_time"
}

prepare_bz() {
  local commit=$1
  local make_res=""

  [[ -n "$commit" ]] || {
    print_err "prepare bz commit is null:$commit" "$BISECT_LOG"
    usage
  }

  if [[ -e "${DEST}/bzImage_${commit}" ]]; then
    print_log "|${DEST}/bzImage_${commit}| exist, no need make" "$BISECT_LOG"
    echo "0" > $MAKE_RESULT
    return 0
  else
    print_log "|${DEST}/bzImage_${commit}| was not exist, will make it" "$BISECT_LOG"
    ${BASE_PATH}/make_bz.sh -k "$KERNEL_SRC" -m "$commit" -d "$DEST" -o "$KERNEL_PATH"
  fi

  make_res=$(cat $MAKE_RESULT)
  [[ "$make_res" -eq 0 ]] || {
    if [[ "$commit" == "$COMMIT" ]]; then
      print_err "END ${DEST}/bzImage_${commit} failed, check ${DEST}/${BZ_LOG}" "$BISECT_LOG"

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      BI_RESULT="$S_FAIL"
      BI_COMMENT=$(cat $RESULT_FILE 2>/dev/null)
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> $BISECT_CSV
      exit 1
    fi
    if [[ "$commit" == "$START_COMMIT" ]]; then
      print_err "START ${DEST}/bzImage_${commit} failed, check ${DEST}/${BZ_LOG}" "$BISECT_LOG"

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      BI_RESULT="$S_FAIL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_COMMENT=$(cat $RESULT_FILE 2>/dev/null)
      echo "$ONE_LINE" >> $BISECT_CSV
      exit 1
    fi
  }
}

prepare_revert_bz() {
  local end_commit=$1
  local bad_commit=$2
  local bzimage=$3
  local make_res=""

  [[ -n "$end_commit" ]] || {
    print_err "prepare bz commit is null:$end_commit" "$BISECT_LOG"

    BI_RESULT="$S_FAIL"
    [[ "$BAD_COMMIT" == "$bad_commit" ]] || {
      print_err "revert bz: bad commit is null" "$BISECT_LOG"
      BAD_COMMIT="$BAD_COMMIT -> ${bad_commit}"
    }
    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_COMMENT="Revert and end commit $end_commit is null"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  }

  if [[ -e "$bzimage" ]]; then
    print_log "$bzimage exist, no need make" "$BISECT_LOG"
    echo "0" > $MAKE_RESULT
    return 0
  else
    print_log "${BASE_PATH}/make_bz.sh -k $KERNEL_SRC -m $end_commit -b $bad_commit -d $DEST -o $KERNEL_PATH -f $bzimage" "$BISECT_LOG"
    ${BASE_PATH}/make_bz.sh -k "$KERNEL_SRC" -m "$end_commit" -b "$bad_commit" -d "$DEST" -o "$KERNEL_PATH" -f "$bzimage"
  fi

  make_res=$(cat $MAKE_RESULT)
  [[ "$make_res" -eq 0 ]] || {
    print_err "Make $end_commit $bad_commit $bzimage failed" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_RESULT="$S_FAIL"
    [[ "$BAD_COMMIT" == "$bad_commit" ]] || {
      print_err "revert bz: bad commit is null" "$BISECT_LOG"
      BAD_COMMIT="$BAD_COMMIT -> ${bad_commit}"
    }
    BI_COMMENT=$(cat $RESULT_FILE 2>/dev/null)
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  }
}

# TODO: improve reproduce step next step
repro_bz() {
  if [[ -z "$REPRO_C" ]]; then
    do_cmd "ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost 'ls -ltr $REPRO'"
    do_cmd "ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost 'ls -ltr $REPRO_FILE'"
  else
    [[ -e "$REPRO_C" ]] || {
      print_err "$REPRO_C does not exist" "$BISECT_LOG"

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_RESULT="$S_FAIL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_COMMENT="$REPRO_C does not exist in vm"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> $BISECT_CSV
      exit 1
    }
    # Some repro binary generated 5G file0 file and no disk space, delete it
    do_cmd "ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost 'rm -rf file*'"
    do_cmd "scp -o 'StrictHostKeyChecking no' -P $PORT ${BASE_PATH}/${REPRO_SH} root@localhost:/root/${REPRO_SH}"
    sleep 1
    do_cmd "scp -o 'StrictHostKeyChecking no' -P $PORT $REPRO_C root@localhost:/root/$REPRO_C_FILE"
    sleep 1
  fi

  do_cmd "ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost 'ls $REPRO'"
  print_log "ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost '$REPRO'"
  ssh -o ConnectTimeout=1 -o 'StrictHostKeyChecking no' -p $PORT localhost "$REPRO" &
}

check_bz_result() {
  local bz_file=$1
  local dmesg_file=$2
  local commit=$3
  local dmesg_info=""
  local cp_result=""
  local i=1
  local time_check=0

  dmesg_info=$(cat $dmesg_file)
  [[ -n "$dmesg_info" ]] || {
    print_err "$dmesg_file is null:$dmesg_info, could not judge!" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_RESULT="$S_FAIL"
    [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
    BI_COMMENT="$dmesg_file is null"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    clean_old_vm
    exit 1
  }

  if [[ "$commit" == "$COMMIT" ]]; then

    [[ -n "$TIME" ]] && [[ "$TIME" -gt 99 ]] && time_check=1

    # Set a time to debug, which need time > 99s
    if [[ "$time_check" -eq 1 ]]; then
      print_log "time_check:$time_check. Set TIME:$TIME >99, will not test reproduce time!"
      sleep $TIME

      cp_result=$(cat $dmesg_file | grep -i "$POINT")
      if [[ -z "$cp_result" ]]; then
        COMMIT_RESULT="$PASS"
      else
        print_log "$bz_file contained $POINT:$cp_result, FAIL" "$BISECT_LOG"
        COMMIT_RESULT="$FAIL"
      fi
      return 0
    else
      print_log "time_check:$time_check. Need to check end commit $COMMIT reproduce time!"
      for((i=1;i<=MAX_LOOP_TIME;i++)); do
        sleep $EVERY_LOOP_TIME

        cp_result=$(cat $dmesg_file | grep -i "$POINT")
        if [[ -z "$cp_result" ]]; then
          continue
        else
          print_log "$bz_file contained $POINT:$cp_result, FAIL" "$BISECT_LOG"
          COMMIT_RESULT="$FAIL"
          return 0
        fi
      done
    fi
    COMMIT_RESULT="$PASS"
    print_log "$dmesg_file not reproduce this issue in 3600s:$bz_file!" "$BISECT_LOG"
  else
    cp_result=$(cat $dmesg_file | grep -i "$POINT")
    if [[ -z "$cp_result" ]]; then
      print_log "$bz_file didn't contain $POINT:$cp_result in dmesg, pass" "$BISECT_LOG"
      COMMIT_RESULT="$PASS"
    else
      print_log "$bz_file contained $POINT:$cp_result, FAIL" "$BISECT_LOG"
      COMMIT_RESULT="$FAIL"
    fi
  fi
}

test_bz() {
  local bz_file=$1
  local commit=$2
  local check_bz=""

  clean_old_vm
  check_bz=$(ls "$bz_file" 2>/dev/null)
  if [[ -z "$check_bz" ]]; then
    print_err "bzImage:$bz_file does not exist:$check_bz" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_RESULT="$S_FAIL"
    [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
    BI_COMMENT="bzImage $bz_file does not exist"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  fi

  [[ -e "$IMAGE_BAK" ]] && {
    print_log "$IMAGE_BAK -> $IMAGE" "$BISECT_LOG"
    echo y | cp -rf $IMAGE_BAK $IMAGE
  }

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
  if [[ -n "$TIME" ]]; then
    sleep "$TIME"
  else
    print_log "No time:$TIME for first time, sleep 5 for first reproduce time"
    sleep 5
  fi

  check_bz_result "$bz_file" "${DMESG_FOLDER}/${commit}_dmesg.log" "$commit"
}

test_commit() {
  local commit=$1
  local make_res=""
  COMMIT_RESULT=""

  prepare_bz "$commit"
  make_res=$(cat $MAKE_RESULT)
  if [[ "$make_res" -eq 0 ]]; then
    test_bz "${DEST}/bzImage_${commit}" "$commit"
    if [[ -z "$COMMIT_RESULT" ]]; then
      print_err "After test $commit, result is null:$COMMIT_RESULT" "$BISECT_LOG"

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_RESULT="$S_FAIL"
      BI_COMMENT="Test $commit result is null"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> $BISECT_CSV

      clean_old_vm
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

    TIME="3600"
    fill_one_line "rep_time"
    [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
    BI_RESULT="$S_FAIL"
    BAD_COMMIT="$NULL"
    BI_COMMENT="END commit $COMMIT pass unexpectedly"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
    exit 1
  else
    check_time "${DMESG_FOLDER}/${COMMIT}_dmesg.log"
    print_log "-END- commit $COMMIT FAIL $COMMIT_RESULT" "$BISECT_LOG"
  fi

  # Whatever it's reproduced or not, will update the repro.c and so on files
  update_mainline_repro

  # Check START COMMIT should test PASS, other wise will stop(TODO for next)
  test_commit "$START_COMMIT"

  if [[ "$COMMIT_RESULT" == "$PASS" ]]; then
    print_log "Start commit $START_COMMIT PASS $COMMIT_RESULT" "$BISECT_LOG"
    # MAIN LINE RESULT should fill here
    MAIN_RESULT="$S_PASS"
  else
    print_log "Srart commit $START_COMMIT FAIL, will stop!" "$BISECT_LOG"

    [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
    [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
    BI_RESULT="$S_FAIL"
    MAIN_RESULT="$S_FAIL"
    BI_COMMENT="Main line kernel reproduced this issue"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> $BISECT_CSV
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
      print_log "Bisect first start commit:$START_COMMIT" "$BISECT_LOG"
      NEXT_COMMIT=$START_COMMIT
    }

    print_log "git bisect $COMMIT_RESULT $NEXT_COMMIT" "$BISECT_LOG"
    bisect_info=$(git bisect $COMMIT_RESULT $NEXT_COMMIT)
    [[ -n "$bisect_info" ]] || {
      print_err "No bisect_info $bisect_info" "$BISECT_LOG"

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_RESULT="$S_FAIL"
      BI_COMMENT="No bisect_info in git bisect:$bisect_info"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> $BISECT_CSV
      exit 1
    }
    # bisect_info for end example:xxx_hash is the first bad commit
    bisect_end=$(echo "$bisect_info" | grep "is the first bad commit")
    [[ -z "$bisect_end" ]] || {
      print_log "Bisect PASS: find $bisect_end" "$BISECT_LOG"
      do_cmd "git bisect log >> $BI_LOG"
      do_cmd "git bisect log >> $BISECT_LOG"
      # Short bisect info log to report
      git bisect log 2>/dev/null >> "$BI_INFO_LOG"
      BAD_COMMIT=$(echo "$bisect_end" | cut -d ' ' -f 1)

      return 0
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

      [[ -z "$TIME" ]] && TIME="$NULL" && fill_one_line "rep_time"
      [[ -z "$MAIN_RESULT" ]] && MAIN_RESULT="$NULL"
      [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="$NULL"
      BI_RESULT="$S_FAIL"
      BI_COMMENT="No bisect_info $bisect_info"
      fill_one_line "$commit is not same as tip:$commit_c"
      echo "$ONE_LINE" >> $BISECT_CSV
      exit 1
    fi
    test_commit "$NEXT_COMMIT"
  done
}

verify_bad_commit() {
  local revert_bz=""
  local make_res=""
  local commit_revert=""

  commit_revert="${COMMIT}_${BAD_COMMIT}_revert"
  revert_bz="${DEST}/bzImage_${commit_revert}"
  prepare_revert_bz "$COMMIT" "$BAD_COMMIT" "$revert_bz"

  [[ -z "$BAD_COMMIT" ]] && BAD_COMMIT="ERR:bad_commit is null in revert step!"

  make_res=$(cat $MAKE_RESULT)
  if [[ "$make_res" -eq 0 ]]; then
    test_bz "$revert_bz" "$commit_revert"
    print_log "$commit_revert $COMMIT_RESULT" "$BI_LOG"

    if [[ -z "$COMMIT_RESULT" ]]; then
      print_err "After test $commit_revert, result is null:$COMMIT_RESULT" "$BISECT_LOG"
      print_err "After test $commit_revert, result is null:$COMMIT_RESULT" "$BI_INFO_LOG"

      BI_RESULT="$S_FAIL"
      BI_COMMENT="test $commit_revert result is null"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> "$BISECT_CSV"
    elif [[ "$COMMIT_RESULT" == "$PASS" ]]; then
      print_log "Bisect successfully! $commit_revert bzimage passed!" "$BISECT_LOG"
      print_log "Bisect successfully! $commit_revert bzimage passed!" "$BI_INFO_LOG"
      print_log "Bisect successfully! $commit_revert bzimage passed!" "$BI_LOG"

      BI_RESULT="$S_PASS"
      BI_COMMENT="Bisect and revert bad commit on top PASS!"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> $BISECT_CSV
    elif [[ "$COMMIT_RESULT" == "$FAIL" ]]; then
      print_err "Bisect failed! $commit_revert bzimage failed!" "$BISECT_LOG"
      print_err "Bisect failed! $commit_revert bzimage failed!" "$BI_INFO_LOG"
      print_err "Bisect failed! $commit_revert bzimage failed!" "$BI_LOG"

      BI_RESULT="$S_FAIL"
      BI_COMMENT="Revert $commit_revert test failed"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> "$BISECT_CSV"
    else
      print_err "Invalid Result:$COMMIT_RESULT in $commit_revert" "$BISECT_LOG"
      print_err "Invalid Result:$COMMIT_RESULT in $commit_revert" "$BI_INFO_LOG"
      print_err "Invalid Result:$COMMIT_RESULT in $commit_revert" "$BI_LOG"
      BI_RESULT="$S_FAIL"
      BI_COMMENT="Revert step invalid result:$COMMIT_RESULT"
      fill_one_line "bi_result"
      echo "$ONE_LINE" >> "$BISECT_CSV"
    fi
  else
    print_err "Make $revert_bz failed, please check ${DEST}/${BZ_LOG}"
    BI_RESULT="$S_FAIL"
    BI_COMMENT="make revert $revert_bz failed"
    fill_one_line "bi_result"
    echo "$ONE_LINE" >> "$BISECT_CSV"
  fi
  clean_old_vm
}

# Set detault value
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
      ISSUE_HASH=$(echo "$REPRO_C" | awk -F "/" '{print $(NF-1)}' 2>/dev/null)
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
  verify_bad_commit
}

main
