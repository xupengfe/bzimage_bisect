#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Scan and execute bisect script, which need bisect_bz.sh & summary.sh

export PATH=${PATH}:/root/bzimage_bisect
source "bisect_common.sh"

IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SCAN_LOG="/root/scan_bisect.log"
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"
ISSUE_HASHS=""
# Need to know below 4 items to bisect
BISECT_HASHS=""
END_COMMIT=""
START_COMMIT=""
KEYWORD=""
KER_SRC="/root/os.linux.intelnext.kernel"
DEST="/home/bzimage"
IMAGE="/root/image/centos8_2.img"
SYZ_FOLDER="/root/syzkaller/workdir/crashes"
REP_CPROG="repro.cprog"

filter_bisect_hashs() {
  local one_hash=""
  local one_hash_content=""
  local bisect_result=""
  local key_check=""

  if [[ -z "$ISSUE_HASHS" ]]; then
    print_log "No any cprog issues in ISSUE_HASH:$ISSUE_HASHS" "$SCAN_LOG"
  else
    for one_hash in $ISSUE_HASHS; do
      # get bisect result column 18, and check it's not null
      one_hash_content=$(cat $SUMMARY_C_CSV | grep $one_hash 2>/dev/null| tail -n 1)
      bisect_result=$(echo $one_hash_content| awk -F "," '{print $18}')
      case $bisect_result in
        null)
          key_check=$(echo $one_hash_content| awk -F "," '{print $4}')
          if [[ "$key_check" == "$S_PASS" ]]; then
            print_log "$one_hash key is pass and bisect result is null" "$SCAN_LOG"
            BISECT_HASHS="$BISECT_HASHS $one_hash"
          else
            print_log "$one_hash key is fail, skip" "$SCAN_LOG"
          fi
          ;;
        $S_FAIL|$S_PASS)
          print_log "$one_hash bisect_result is $bisect_result, no need bisect" "$SCAN_LOG"
          ;;
        *)
          print_err "$one_hash bisect_result is invalid, please check!!!" "$SCAN_LOG"
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
  START_COMMIT=$(echo "$one_hash_content" | awk -F "," '{print $11}')
  KEYWORD=$(echo "$one_hash_content" | awk -F "," '{print $3}')

  # if CET branch, will change as below!
  [[ "$END_COMMIT" == "7ed918f933a7a4e7c67495033c06e4fe674acfbd" ]] && {
    KER_SRC="/home/linux_cet"
  }

  print_log "bisect_bz.sh -k $KER_SRC -m $END_COMMIT -s $START_COMMIT -d $DEST -p $KEYWORD -i $IMAGE -r ${SYZ_FOLDER}/${one_hash}/${REP_CPROG}" "$SCAN_LOG"
  bisect_bz.sh -k "$KER_SRC" -m "$END_COMMIT" -s "$START_COMMIT" -d "$DEST" -p "$KEYWORD" -i "$IMAGE" -r "${SYZ_FOLDER}/${one_hash}/${REP_CPROG}"
}

scan_bisect() {
  local result=""
  local hash=""

  while true; do

    summary.sh
    if [[ -e "$SUMMARY_C_CSV" ]]; then
      ISSUE_HASHS=""
      ISSUE_HASHS=$(cat "$SUMMARY_C_CSV" | grep repro.cprog | awk -F "," '{print $1}')
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
    sleep 900
  done
}

scan_bisect
