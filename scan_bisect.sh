#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Scan and execute bisect script, which need bisect_bz.sh & summary.sh

export PATH=${PATH}:/root/bzimage_bisect
source "bisect_common.sh"

IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SCAN_LOG="/root/scan_bisect.log"

while true; do
  if [[ -z "$IP" ]]; then
    print_err "Could not get IP:$IP, wait 5s to fetch" "$SCAN_LOG"
    sleep 5
    IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
  else
    print_log "get IP:$IP" "$SCAN_LOG"
    break
  fi
done
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"
ISSUE_HASHS=""
# Need to know below 4 items to bisect
BISECT_HASHS=""
END_COMMIT=""
START_COMMIT=""
KEYWORD=""
KER_SRC_DEFAULT="/root/os.linux.intelnext.kernel"
KER_SRC=""
DEST="/home/bzimage"
IMAGE="/root/image/centos8_2.img"
REP_CPROG="repro.cprog"

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-h]
  -k  KERNEL SPECIFIC source folder(optional)
  -m  COMMIT SPECIFIC END COMMIT ID(optional)
  -s  START COMMIT(optional)
  -h  show this
__EOF
  exit 1
}


# filter needs ISSUES_HASHS of bisect and fill in BISECT_HASHS
filter_bisect_hashs() {
  local one_hash=""
  local one_hash_content=""
  local bisect_result=""
  local key_check=""
  local end_commit=""
  local bi_hash_content=""
  local bi_end_commit=""
  local ker_check_src=""
  local check_commit=""

  if [[ -z "$ISSUE_HASHS" ]]; then
    print_log "No any cprog issues in ISSUE_HASH:$ISSUE_HASHS" "$SCAN_LOG"
  else
    for one_hash in $ISSUE_HASHS; do
      one_hash_content=""
      bad_commit=""
      bisect_result=""
      check_commit=""
      if [[ "$one_hash" == *"HASH"* ]]; then
        print_log "Issue:$one_hash is the header HASH, ignore and continue." "$SCAN_LOG"
        continue
      fi

      # Get bisect result column 19, and check it's not null: bi_result
      one_hash_content=$(cat $SUMMARY_C_CSV | grep $one_hash 2>/dev/null| tail -n 1)
      bisect_result=$(echo $one_hash_content| awk -F "," '{print $19}')
      # Column 20, bisect first bad commit
      bad_commit=$(echo $one_hash_content| awk -F "," '{print $20}')
      # If already find bad commit, will not bisect this issue again
      if [[ "$bad_commit" != "null" ]]; then
        print_log "$one_hash bad commit $bad_commit is not null" "$SCAN_LOG"
        ker_check_src=$(cat $MAKE_KSRC 2>/dev/null)
        [[ -z "$ker_check_src" ]] && {
           print_log "ERROR:cat $MAKE_KSRC:$ker_check_src is null! Use default!!!" "$SCAN_LOG"
          # /tmp/kernel/os.linux.intelnext.kernel as previous default
          ker_check_src="${KERNEL_PATH}/os.linux.intelnext.kernel"
        }
        cd $ker_check_src
        check_commit=$(git show $bad_commit 2>/dev/null | head -n 1)
        if [[ -z "$check_commit" ]]; then
          print_log "ERROR:Issue:$one_hash no bad commit:$bad_commit in $ker_check_src" "$SCAN_LOG"
        else
          print_log "[INFO]$one_hash find bad commit:$bad_commit, no need bisect" "$SCAN_LOG"
          continue
        fi
      fi

      case $bisect_result in
        bi_result)
          print_log "Header $one_hash is bi_res:$bisect_result, continue" "$SCAN_LOG"
          ;;
        null)
          key_check=$(echo $one_hash_content| awk -F "," '{print $4}')
          if [[ "$key_check" == "$S_PASS" ]]; then
            print_log "$one_hash key is pass and bisect result is null" "$SCAN_LOG"
            BISECT_HASHS="$BISECT_HASHS $one_hash"
          else
            print_log "$one_hash key is fail, skip" "$SCAN_LOG"
          fi
          ;;
        $S_PASS)
          print_log "$one_hash bisect_result is $S_PASS, no need bisect" "$SCAN_LOG"
          ;;
        $S_FAIL)
          # column 10: i_commit
          end_commit=$(echo $one_hash_content| awk -F "," '{print $10}')
          bi_hash_content=$(cat "$BISECT_CSV" | grep $one_hash 2>/dev/null | tail -n 1)
          bi_end_commit=$(echo "$bi_hash_content" | awk -F "," '{print $2}')
          # failed case end commit newer than last time bisect, will bisect again
          [[ "$end_commit" ==  "$bi_end_commit" ]] || {
            print_log "end:$end_commit not same as bi:$bi_end_commit, add $one_hash for bisect" "$SCAN_LOG"
            BISECT_HASHS="$BISECT_HASHS $one_hash"
          }
          ;;
        $S_REBI)
          print_log "$one_hash bisect_result:$bisect_result is $S_REBI unexpected, will rebisect!" "$SCAN_LOG"
          BISECT_HASHS="$BISECT_HASHS $one_hash"
          ;;
        *)
          print_err "$one_hash bisect_result:$bisect_result is invalid, rebisect, please check!!!" "$SCAN_LOG"
          BISECT_HASHS="$BISECT_HASHS $one_hash"
          ;;
      esac
    done
  fi
}

execute_bisect_cmd() {
  local one_hash=$1
  local one_hash_content=""

  END_COMMIT=""
  START_COMMIT=""
  KEYWORD=""
  one_hash_content=$(cat $SUMMARY_C_CSV | grep $one_hash 2>/dev/null| tail -n 1)

  END_COMMIT=$(echo "$one_hash_content" | awk -F "," '{print $10}')
  [[ -z  "$END_COMMIT" ]]  && {
    print_err "HASH:$one_hash, END_COMMIT:$END_COMMIT is null! Update end commit" "$SCAN_LOG"
  }
  END_COMMIT=$(cat $ECOM_FILE 2>/dev/null)
  START_COMMIT=$(echo "$one_hash_content" | awk -F "," '{print $11}')
  [[ "$START_COMMIT" == *":"* ]] && {
    print_err "HASH:$one_hash, START_COMMIT:$START_COMMIT is wrong with:! Update end commit" "$SCAN_LOG"
  }
  START_COMMIT=$(cat $SCOM_FILE 2>/dev/null)
  KEYWORD=$(echo "$one_hash_content" | awk -F "," '{print $3}')
  # for rep.c file
  REP_CPROG=$(echo "$one_hash_content" | awk -F "," '{print $13}')
  if [[ -e "${SYZ_FOLDER}/${one_hash}/${REP_CPROG}" ]]; then
    print_log "Check ${SYZ_FOLDER}/${one_hash}/${REP_CPROG} existed." "$SCAN_LOG"
  elif [[ -e "${SYZ_FOLDER}/${one_hash}/repro.cprog" ]]; then
    print_log "HASH:$one_hash, Change $REP_CPROG to existed ${SYZ_FOLDER}/${one_hash}/repro.cprog file!" "$SCAN_LOG"
    REP_CPROG=repro.cprog
  elif [[ -e "${SYZ_FOLDER}/${one_hash}/rep.c" ]]; then
    print_log "HASH:$one_hash, Change $REP_CPROG to existed ${SYZ_FOLDER}/${one_hash}/rep.c file!" "$SCAN_LOG"
    REP_CPROG=rep.c
  else
    print_err "HASH:$one_hash, REP_CPROG:$REP_CPROG does not exist, will not execute this hash issue!" "$SCAN_LOG"
    return 1
  fi
  # Will not use default ker src, will use KSRC_FILE content instead
  # KER_SRC="$KER_SRC_DEFAULT"
  KER_SRC=$(cat $KSRC_FILE 2>/dev/null)
  # if SPECIFIC COMMIT, will change as below kernel source and commit
  [[ -z "$KERNEL_SPECIFIC" ]] || {
    if [[ -d "$KERNEL_SPECIFIC" ]]; then
      # Check END_COMMIT should match with COMMIT_SPECIFIC
      if [[ "$END_COMMIT" == *"$COMMIT_SPECIFIC"* ]]; then
        KER_SRC="$KERNEL_SPECIFIC"
      else
        print_err "END_COMMIT:$END_COMMIT not include specific:$COMMIT_SPECIFIC" "$SCAN_LOG"
      fi
    else
      print_err "KERNEL_SPECIFIC:$KERNEL_SPECIFIC folder does not exist!" "$SCAN_LOG"
    fi
  }

  print_log "bisect_bz.sh -k $KER_SRC -m $END_COMMIT -s $START_COMMIT -d $DEST -p $KEYWORD -i $IMAGE -r ${SYZ_FOLDER}/${one_hash}/${REP_CPROG}" "$SCAN_LOG"
  bisect_bz.sh -k "$KER_SRC" -m "$END_COMMIT" -s "$START_COMMIT" -d "$DEST" -p "$KEYWORD" -i "$IMAGE" -r "${SYZ_FOLDER}/${one_hash}/${REP_CPROG}"
}

# Recover bisect csv in /root/image, if not exit and back exist situation
check_bisect_csv() {
  if [[ -e "$BISECT_CSV" ]]; then
    print_log "bisect_csv:$BISECT_CSV exist, check step do nothing" "$SCAN_LOG"
  else
    if [[ -e "$BISECT_BAK" ]]; then
      print_log "$BISECT_CSV not exist, $BISECT_BAK exist, will recover $BISECT_CSV" "$SCAN_LOG"
      cp -rf $BISECT_BAK $BISECT_CSV
    else
      print_log "$BISECT_CSV and $BISECT_BAK doesn't exist, first time scan?" "$SCAN_LOG"
    fi
  fi
}

scan_bisect() {
  local result=""
  local hash=""
  local result=0
  local i=1

  for ((i=1;;i++)); do
    check_bisect_csv
    # Clean BISECT HASHS list before each loop
    BISECT_HASHS=""

    print_log "The $i round start: update git bzimage_bisect" "$SCAN_LOG"
    update.sh
    result=0
    print_log "summarize syzkaller issues in csv file" "$SCAN_LOG"
    # Should update KERNEL_SPECIFIC, COMMIT_SPECIFIC START COMMIT every round
    parm_check
    [[ -n "$KERNEL_SPECIFIC" ]] && [[ -n "$COMMIT_SPECIFIC" ]] && [[ -n "$SPEC_START_COMMIT" ]] && result=1
    if [[ "$result" -eq 1 ]]; then
      print_log "Get ker:$KERNEL_SPECIFIC, END commit:$COMMIT_SPECIFIC, start:$SPEC_START_COMMIT" "$SCAN_LOG"
      summary.sh -k "$KERNEL_SPECIFIC" -m "$COMMIT_SPECIFIC" -s "$SPEC_START_COMMIT"
    else
      summary.sh
    fi

    if [[ -e "$SUMMARY_C_CSV" ]]; then
      print_log "-> Check $SUMMARY_C_CSV file" "$SCAN_LOG"
      ISSUE_HASHS=""
      # Only repro.cprog issues bisect
      #ISSUE_HASHS=$(cat "$SUMMARY_C_CSV" | grep repro.cprog | awk -F "," '{print $1}')
      # all repro.cprog and rep.c issues bisect
      ISSUE_HASHS=$(cat "$SUMMARY_C_CSV" | awk -F "," '{print $1}')
      # filter needs ISSUES_HASHS of bisect and fill in BISECT_HASHS
      filter_bisect_hashs

      # list all repro.cprog issues hashs and bisect
      for hash in $BISECT_HASHS; do
        execute_bisect_cmd "$hash"
      done
    else
      print_err "There is no $SUMMARY_C_CSV file. please check!" "$SCAN_LOG"
      continue
    fi

    # every 15min to scan
    print_log "The $i round bisect loop finished, sleep 900" "$SCAN_LOG"
    sleep 900
  done
}

check_scan_pid() {
  local scan_num=""
  local scan_pid=""


  scan_num=$(ps -ef | grep scan_bisect \
            | grep sh \
            | wc -l)
  scan_pid=$(ps -ef | grep scan_bisect \
            | grep sh \
            | awk -F " " '{print $2}' \
            | head -n 1)
  [[ "$scan_num" -le 2 ]] || {
    print_log "Found scan pid num:$scan_num more than 2 pid:$scan_pid, exit" "$SCAN_LOG"
    exit 1
  }
}

parm_check() {
  # Will check the file contect with first priority
  [[ -e "$KSRC_FILE" ]] && \
    KERNEL_SPECIFIC=$(cat $KSRC_FILE 2>/dev/null)

  [[ -e "$ECOM_FILE" ]] && \
    COMMIT_SPECIFIC=$(cat $ECOM_FILE 2>/dev/null)

  [[ -e "$SCOM_FILE" ]] && \
    SPEC_START_COMMIT=$(cat $SCOM_FILE 2>/dev/null)
}


while getopts :k:m:s:h arg; do
  case $arg in
    k)
      # KERNEL_SPECIFIC is seperated from KER_SOURCE, could be null
      KERNEL_SPECIFIC=$OPTARG
      ;;
    m)
      # END specific commit for develop branch, similar as above
      COMMIT_SPECIFIC=$OPTARG
      ;;
    s)
      SPEC_START_COMMIT=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# only accept 1 scan pid was executed, otherwise will quit
check_scan_pid
parm_check
scan_bisect
