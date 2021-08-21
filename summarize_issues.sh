#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the script to summarize issues

source "bisect_common.sh"

IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SUMMARIZE_LOG="/root/summarize_issues.log"
SUMMARY_FILE="/root/summary_$IP_$hostname.csv"
# Hard code SYZ_FOLDER, may be a variable value in the future
SYZ_FOLDER="/root/syzkaller/workdir/crashes"
SYZ_REPRO_C="repro.cprog"

summarize_issues() {
  local hash_all=""
  local hash_one=""
  local hash_c=""
  local hash_no_c=""
  local all_num=""
  local c_num=""
  local check_num=""
  local no_c_num=0

  [[ -d "$SYZ_FOLDER" ]] || {
    print_err "$SYZ_FOLDER does not exist, exit!" "$SUMMARIZE_LOG"
    exit 1
  }

  hash_all=$(ls -1 $SYZ_FOLDER)
  hash_c=$(find /root/syzkaller/workdir/crashes -name "$SYZ_REPRO_C" \
          | awk -F "/" '{print $(NF-1)}')
  all_num=$(ls -1 $SYZ_FOLDER | wc -l)

  c_num=$(find /root/syzkaller/workdir/crashes -name "$SYZ_REPRO_C" | wc -l)

  for hash_one in $hash_all; do
    if [[ "$hash_c" == *"$hash_one"* ]]; then
      continue
    else
      if [[ "$no_c_num" -eq 0 ]]; then
        hash_no_c="$hash_one"
      else
        hash_no_c="$hash_no_c $hash_one"
      fi
      ((no_c_num+=1))
    fi
  done

  check_num=$((no_c_num+c_num))

  print_log "check:$check_num, all:$all_num, c:$c_num, no_c:$no_c_num"
  [[ "$check_num" -eq "$all_num" ]] || {
    print_err "check_num:$check_num is not equal to $all_num"    
  }

  print_log "---->  c: $hash_c"

  print_log "---->  No_c:$hash_no_c"
}



summarize_issues
