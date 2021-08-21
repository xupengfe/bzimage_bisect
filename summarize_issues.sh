#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the script to summarize issues

source "bisect_common.sh"

HASH_C=""
HASH_NO_C=""
IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SUMMARIZE_LOG="/root/summarize_issues.log"
SUMMARY_C_CSV="/root/summary_c_$IP_$hostname.csv"
SUMMARY_NO_C_CSV="/root/summary_no_c_$IP_$hostname.csv"
# Hard code SYZ_FOLDER, may be a variable value in the future
SYZ_FOLDER="/root/syzkaller/workdir/crashes"
SYZ_REPRO_C="repro.cprog"


init_hash_issues() {
  local hash_all=""
  local hash_one=""
  local all_num=""
  local c_num=""
  local check_num=""
  local no_c_num=0

  [[ -d "$SYZ_FOLDER" ]] || {
    print_err "$SYZ_FOLDER does not exist, exit!" "$SUMMARIZE_LOG"
    exit 1
  }

  hash_all=$(ls -1 $SYZ_FOLDER)
  HASH_C=$(find /root/syzkaller/workdir/crashes -name "$SYZ_REPRO_C" \
          | awk -F "/" '{print $(NF-1)}')
  all_num=$(ls -1 $SYZ_FOLDER | wc -l)

  c_num=$(find /root/syzkaller/workdir/crashes -name "$SYZ_REPRO_C" | wc -l)

  for hash_one in $hash_all; do
    if [[ "$HASH_C" == *"$hash_one"* ]]; then
      continue
    else
      if [[ "$no_c_num" -eq 0 ]]; then
        HASH_NO_C="$hash_one"
      else
        HASH_NO_C="$HASH_NO_C $hash_one"
      fi
      ((no_c_num+=1))
    fi
  done

  check_num=$((no_c_num+c_num))

  print_log "check:$check_num, all:$all_num, c:$c_num, no_c:$no_c_num"
  [[ "$check_num" -eq "$all_num" ]] || {
    print_err "check_num:$check_num is not equal to $all_num"    
  }

  print_log "---->  c: $HASH_C"

  print_log "---->  No_c:$HASH_NO_C"
}

fill_simple_line() {
  local one_hash=$1
  local item_file=$2
  local one_line=$3
  local filter=$4
  local content=""
  local file_latest=""
  local key_word=""

  file_latest=$(ls -1 ${SYZ_FOLDER}/${one_hash}/${item_file}* | tail -n 1)
  if [[ -z "$filter" ]]; then
    content=$(cat $file_latest | tail -n 1)
  else
    content=$(cat $file_latest | grep "$filter" | tail -n 1)
  fi
  one_line="${one_line},${content}"
  if [[ "$item_file" == "description" ]]; then

    if [[ "$content" == *" in "* ]]; then
      key_word=$(echo $content | awk -F " in " '{print $NF}')
    elif [[ "$content" == *":"* ]]; then
      key_word=$(echo $content | awk -F ":" '{print $NF}')
    esle
      print_log "WARN: description:$content no |:| or |in|! Fill all!"
      key_word=$content
    fi
    one_line="${one_line},${key_word}"
  fi
}

fill_c() {
  local hash_one_c=$1
  local c_hash_line=""
  local c_header=""

  c_hash_line="$hash_one_c"
  c_header="HASH,description,key_word,kernel"
  echo "HASH,description,key_word,kernel" > $SUMMARY_C_CSV
  fill_simple_line "$hash_one_c" "description" "$c_hash_line"
  fill_simple_line "$hash_one_c" "report" "$c_hash_line" "\#"
  echo "$c_hash_line" >> $SUMMARY_C_CSV
}

fill_no_c() {
  local hash_one_no_c=$1
  local c_hash_line=""
  local c_header=""

  no_c_hash_line="$hash_one_no_c"
  c_header="HASH,description,key_word,kernel"
  echo "HASH,description,key_word,kernel" >> $SUMMARY_C_CSV
  fill_simple_line "$hash_one_no_c" "description" "$no_c_hash_line"
  fill_simple_line "$hash_one_no_c" "report" "$no_c_hash_line" "\#"
  echo "$no_c_hash_line" >> $SUMMARY_NO_C_CSV
}


summarize_no_c() {
  local hash_one_no_c=""

  for hash_one_no_c in $HASH_C; do
    fill_no_c "$hash_one_no_c"
  done

}

summarize_c() {
  local hash_one_c=""

  for hash_one_c in $HASH_C; do
    fill_c "$hash_one_c"
  done
}


summarize_issues() {
  init_hash_issues
  summarize_c
  summarize_no_c
}



summarize_issues
