#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the script to summarize issues

source "bisect_common.sh"

readonly S_PASS="pass"
readonly S_FAIL="fail"
readonly NULL="NULL"
HASH_C=""
HASH_NO_C=""
IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SUMMARIZE_LOG="/root/summarize_issues.log"
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"
SUMMARY_NO_C_CSV="/root/summary_no_c_${IP}_${HOST}.csv"
# Hard code SYZ_FOLDER, may be a variable value in the future
SYZ_FOLDER="/root/syzkaller/workdir/crashes"
SYZ_REPRO_C="repro.cprog"
HASH_LINE=""
DES_CONTENT=""
FKER_CONTENT=""
KEY_RESULT=""

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

  print_log "check:$check_num, all:$all_num, c:$c_num, no_c:$no_c_num" "$SUMMARIZE_LOG"
  [[ "$check_num" -eq "$all_num" ]] || {
    print_err "check_num:$check_num is not equal to $all_num" "$SUMMARIZE_LOG"
  }

  print_log "---->  c: $HASH_C" "$SUMMARIZE_LOG"

  print_log "---->  No_c:$HASH_NO_C" "$SUMMARIZE_LOG"
}

fill_line() {
  local one_hash=$1
  local item_file=$2
  local des_content=""
  local key_content=""
  local fker_content=""
  local nkers_content=""
  local nmac_info=""
  local nker=""
  local nkers=""

  case $item_file  in
    description)
      des_latest=""
      des_content=""
      des_latest=$(ls -1 ${SYZ_FOLDER}/${one_hash}/${item_file}* 2>/dev/null | tail -n 1)
      [[ -z "$des_latest" ]] && {
        print_err "des_latest is null:$des_latest in ${SYZ_FOLDER}/${one_hash}/${item_file}" "$SUMMARIZE_LOG"
        exit 1
      }
      des_content=$(cat $des_latest | tail -n 1)
      [[ -z "$des_latest" ]] \
        && print_err "des_content is null:$des_content in ${SYZ_FOLDER}/${one_hash}/${item_file}" "$SUMMARIZE_LOG"

      DES_CONTENT=$des_content
      HASH_LINE="${HASH_LINE},${des_content}"
      ;;
    key_word)
      key_content=""
      KEY_RESULT=""
      if [[ "$DES_CONTENT" == *" in "* ]]; then
        key_content=$(echo $DES_CONTENT | awk -F " in " '{print $NF}')
        KEY_RESULT=$S_PASS
      elif [[ "$DES_CONTENT" == *":"* ]]; then
        key_content=$(echo $DES_CONTENT | awk -F ":" '{print $NF}')
        KEY_RESULT=$S_PASS
      else
        print_log "WARN: description:$DES_CONTENT no |:| or |in|! Fill all!" "$SUMMARIZE_LOG"
        KEY_RESULT=$S_FAIL
        key_content=$DES_CONTENT
      fi
      HASH_LINE="${HASH_LINE},${key_content}"
      ;;
    key_ok)
      [[ -z "$KEY_RESULT" ]] && {
        print_err "KEY_RESULT:$KEY_RESULT is null" "$SUMMARIZE_LOG"
      }
      HASH_LINE="${HASH_LINE},${KEY_RESULT}"
      ;;
    repro_kernel)
      # repro.report should contain the first reproduce kernel
      fker_content=""
      fker_content=$(grep "PID:" repro.report* 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq | head -n 1)

      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      fker_content=$(cat repro.report | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | head -n 1)
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      [[ -n "$fker_content" ]] || {
        print_err "${SYZ_FOLDER}/${one_hash}/repro.report no kernel!!" "$SUMMARIZE_LOG"
        FKER_CONTENT="$NULL"
        HASH_LINE="${HASH_LINE},$NULL"
        return 0
      }

      # useless
      [[ -z "$fker_content" ]] && {
        [[ -e "${SYZ_FOLDER}/${one_hash}/machineInfo0" ]] && {
          print_err "repro.report and ${SYZ_FOLDER}/${one_hash}/machineInfo0 does not exist" "$SUMMARIZE_LOG"
          FKER_CONTENT="NULL"
          HASH_LINE="${HASH_LINE},NULL"
          return 0
        }
        fker_content=$(cat machineInfo0 | grep bzImage | awk -F "kernel\" \"" '{print $2}' | awk -F "\"" '{print $1}')
        fker_content="$fker_content"
      }
      FKER_CONTENT=$fker_content
      HASH_LINE="${HASH_LINE},${fker_content}"
      ;;
    all_kernels)
      nkers_content=""
      nkers=""
      nkers_content=$(grep "PID:" report* 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq)

      [[ -z "$nkers_content" ]] && {
        nmac_info=$(ls -ltra machineInfo* 2>/dev/null | awk -F " " '{print $NF}' | tail -n 1)
        [[ -z "$nmac_info" ]] && {
          print_log "No ${one_hash}/machineInfo fill $FKER_CONTENT"
          HASH_LINE="${HASH_LINE},|${FKER_CONTENT}|"
          return 0
        }
        nkers_content=$(cat $nmac_info | grep bzImage | awk -F "kernel\" \"" '{print $2}' | awk -F "\"" '{print $1}' | uniq)
      }

      # nkers_content may be several kernels with enter, maybe same, solve them
      for nker in $nkers_content; do
        [[ "$nkers" == *"$nker"* ]] && continue
        nkers="${nkers}|${nker}"
      done
        nkers="${nkers}|"
      HASH_LINE="${HASH_LINE},${nkers}"
      ;;
    *)
      print_err "invalid $item_file!!! Ignore" "$SUMMARIZE_LOG"
      ;;
  esac

  #print_log "$HASH_LINE" "$SUMMARIZE_LOG"
}

fill_c() {
  local hash_one_c=$1

  # init HASH_LINE in each loop
  HASH_LINE=""
  HASH_LINE="$hash_one_c"

  cd ${SYZ_FOLDER}/${hash_one_c}
  #print_log "$hash_one_c" "$SUMMARIZE_LOG"
  fill_line "$hash_one_c" "description"
  fill_line "$hash_one_c" "key_word"
  fill_line "$hash_one_c" "key_ok"
  fill_line "$hash_one_c" "repro_kernel"
  fill_line "$hash_one_c" "all_kernels"
  #fill_line "$hash_one_c" "new_kernel"
  echo "$HASH_LINE" >> $SUMMARY_C_CSV
}

fill_no_c() {
  local hash_one_no_c=$1

  # init HASH_LINE in each loop
  HASH_LINE=""
  HASH_LINE="$hash_one_no_c"

  cd ${SYZ_FOLDER}/${hash_one_no_c}
  #print_log "$hash_one_c" "$SUMMARIZE_LOG"
  fill_line "$hash_one_no_c" "description"
  fill_line "$hash_one_no_c" "key_word"
  fill_line "$hash_one_no_c" "key_ok"
  fill_line "$hash_one_no_c" "repro_kernel"
  fill_line "$hash_one_no_c" "all_kernels"
  #fill_line "$hash_one_no_c" "new_kernel"
  echo "$HASH_LINE" >> $SUMMARY_NO_C_CSV
}

summarize_no_c() {
  local hash_one_no_c=""
  local no_c_header=""

  no_c_header="HASH,description,key_word,key_ok,repro_kernel,all_kernels,new_kernel"
  echo "$no_c_header" > $SUMMARY_NO_C_CSV
  for hash_one_no_c in $HASH_NO_C; do
    fill_no_c "$hash_one_no_c"
  done
}

summarize_c() {
  local hash_one_c=""
  local c_header=""

  c_header="HASH,description,key_word,key_ok,repro_kernel,all_kernels,new_kernel"
  echo "$c_header" > $SUMMARY_C_CSV
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
