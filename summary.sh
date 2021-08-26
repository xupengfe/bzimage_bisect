#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Make the script to summarize issues

export PATH=${PATH}:/root/bzimage_bisect
source "bisect_common.sh"

HASH_CPROGS=""
HASH_C=""
HASH_NO_C=""
IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SUMMARIZE_LOG="/root/summarize_issues.log"
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"
SUMMARY_NO_C_CSV="/root/summary_no_c_${IP}_${HOST}.csv"
# Hard code SYZ_FOLDER, may be a variable value in the future
SYZ_FOLDER="/root/syzkaller/workdir/crashes"
# Hard code kernel source, will improve in future
KER_SOURCE="/root/os.linux.intelnext.kernel"
SYZ_REPRO_C="repro.cprog"
SYZ_REPRO_PROG="repro.prog"
REP_C="rep.c"
HASH_LINE=""
DES_CONTENT=""
FKER_CONTENT=""
KEY_RESULT=""
NKERS=""
NKER_HASH=""
I_TAG=""
M_TAG=""
BI_RES_FILE="/root/image/bi_result.csv"
BI_RES_BAK="/opt/bi_result_bak.csv"

init_hash_issues() {
  local hash_all=""
  local hash_one=""
  local all_num=""
  local c_num=""
  local only_prog_num=0
  local check_num=""
  local no_c_num=0
  local hash_cprog

  [[ -d "$SYZ_FOLDER" ]] || {
    print_err "$SYZ_FOLDER does not exist, exit!" "$SUMMARIZE_LOG"
    exit 1
  }

  hash_all=$(ls -1 $SYZ_FOLDER)
  HASH_CPROGS=$(find $SYZ_FOLDER -name "$SYZ_REPRO_C" \
          | awk -F "/" '{print $(NF-1)}')
  HASH_PROG=$(find $SYZ_FOLDER -name "$SYZ_REPRO_PROG" \
            | awk -F "/" '{print $(NF-1)}')
  all_num=$(ls -1 $SYZ_FOLDER | wc -l)

  c_num=$(find $SYZ_FOLDER -name "$SYZ_REPRO_C" | wc -l)

  for hash_cprog in $HASH_CPROGS; do
    HASH_C="$HASH_C $hash_cprog"
  done

  for hash_one in $hash_all; do
    if [[ "$HASH_C" == *"$hash_one"* ]]; then
      continue
    else
      # if issue doesn't have repro.cprog but has repro.prog, will generate c
      if [[ "$HASH_PROG" ==  *"$hash_one"* ]]; then
        HASH_C="$HASH_C $hash_one"
        syz-prog2c -prog ${SYZ_FOLDER}/${hash_one}/repro.prog > ${SYZ_FOLDER}/${hash_one}/rep.c
        [[ $? -eq 0 ]] || print_err "syz-prog2c $hash_one repro.prog error" "$SUMMARIZE_LOG"
        ((only_prog_num+=1))
        continue
      fi

      if [[ "$no_c_num" -eq 0 ]]; then
        HASH_NO_C="$hash_one"
      else
        HASH_NO_C="$HASH_NO_C $hash_one"
      fi
      ((no_c_num+=1))
    fi
  done

  check_num=$((no_c_num+c_num+only_prog_num))

  print_log "check:$check_num, all:$all_num, c:$c_num, only_prog:$only_prog_num no_c:$no_c_num" "$SUMMARIZE_LOG"
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
  local new_ker_hash=""

  cd ${SYZ_FOLDER}/${one_hash}
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
      # report should contain the first reproduce kernel
      fker_content=""

      fker_content=$(grep "PID:" report* 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq | head -n 1)
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      fker_content=$(grep "PID:" repro.report 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq | head -n 1)
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      fker_content=$(cat report* 2>/dev/null | grep "#" | head -n 1| awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}')
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      #fker_content=$(cat repro.report 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | head -n 1)
      #if [[ -n "$fker_content" ]]; then
      #  FKER_CONTENT="$fker_content"
      #  HASH_LINE="${HASH_LINE},${fker_content}"
      #  return 0
      #fi

      #fker_content=$(cat repro.log 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | head -n 1)
      #if [[ -n "$fker_content" ]]; then
      #  FKER_CONTENT="$fker_content"
      #  HASH_LINE="${HASH_LINE},${fker_content}"
      #  return 0
      #fi

      fker_content=$(cat repro.log 2>/dev/null | grep Kernel | cut -d ' ' -f 2| head -n 1)
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

      [[ -z "$fker_content" ]] && {
        [[ -e "${SYZ_FOLDER}/${one_hash}/machineInfo0" ]] || {
          print_err "report, repro.log repro.report and ${SYZ_FOLDER}/${one_hash}/machineInfo0 does not exist!" "$SUMMARIZE_LOG"
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
      NKERS=""
      nkers_content=$(grep "PID:" report* 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq)

      [[ -z "$nkers_content" ]] && {
        nmac_info=$(ls -ltra machineInfo* 2>/dev/null | awk -F " " '{print $NF}' | tail -n 1)
        [[ -z "$nmac_info" ]] && {
          print_log "All kernels: No ${one_hash}/machineInfo fill $FKER_CONTENT" "$SUMMARIZE_LOG"
          NKERS=$FKER_CONTENT
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
        NKERS=$nkers
      HASH_LINE="${HASH_LINE},${nkers}"
      ;;
    nker_hash)
      NKER_HASH=""

      if [[ "$NKERS" == *"bzImage"* ]]; then
        new_ker_hash=$(echo $NKERS | awk -F "bzImage_" '{print $NF}' | awk -F "|" '{print $1}' | awk -F "_" '{print $NF}')
        [[ -z "$new_ker_hash" ]] && print_err "Solve $NKERS with bzImage to null:$new_ker_hash"
        NKER_HASH=$new_ker_hash
        HASH_LINE="${HASH_LINE},${new_ker_hash}"
        return 0
      fi
      new_ker_hash=$(echo $NKERS | awk -F "+|" '{print $(NF-1)}' 2>/dev/null| awk -F "-" '{print $NF}')
      [[ -z "$new_ker_hash" ]] && print_err "Solve $NKERS with +| to null:$new_ker_hash"
      NKER_HASH=$new_ker_hash
      HASH_LINE="${HASH_LINE},${new_ker_hash}"
      ;;
    iker_tag_4)
      cd $KER_SOURCE
      I_TAG=""
      M_TAG=""
      i_commit=""
      m_commit=""

      # if $NKERS is null situation, fill null
      [[ -z "$NKER_HASH" ]] && {
        HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL"

        return 0
      }

      I_TAG=$(git show-ref --tags  | grep $NKER_HASH | grep "intel" | awk -F "/" '{print $NF}' | tail -n 1)
      if [[ -z "$I_TAG" ]]; then
        I_TAG=$(git ls-remote | grep $NKER_HASH | grep "intel" | awk -F "/" '{print $NF}' | tail -n 1)
        [[ -z "$I_TAG" ]] && {
          print_err "git ls-remote could not get I_TAG with $NKER_HASH in $KER_SOURCE" "$SUMMARIZE_LOG"
          HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL"
          return 0
        }
        print_log "git fetch origin $I_TAG" "$SUMMARIZE_LOG"
        git fetch origin $I_TAG
        git fetch origin
      fi

      HASH_LINE="${HASH_LINE},${I_TAG}"

      M_TAG=$(echo "$I_TAG" | awk -F "intel-" '{print $2}' | awk -F "-20" '{print $1}' | tail -n 1)
      M_TAG="v${M_TAG}"
      HASH_LINE="${HASH_LINE},${M_TAG}"

      i_commit=$(git show "$I_TAG" | grep "^commit"| head -n 1 | awk -F " " '{print $2}')
      HASH_LINE="${HASH_LINE},${i_commit}"

      m_commit=$(git show "$M_TAG" | grep "^commit"| head -n 1 | awk -F " " '{print $2}')
      HASH_LINE="${HASH_LINE},${m_commit}"
      ;;
    c_file)
      if [[ -e "${SYZ_FOLDER}/${one_hash}/repro.cprog" ]]; then
        HASH_LINE="${HASH_LINE},repro.cprog"
      else
        if [[ -e "${SYZ_FOLDER}/${one_hash}/rep.c" ]]; then
          HASH_LINE="${HASH_LINE},rep.c"
        else
          print_err "C_HASH:one_hash didn't find repro.cprog or rep.c!" "$SUMMARIZE_LOG"
          HASH_LINE="${HASH_LINE},$NULL"
        fi
      fi
      ;;
    bi_8)
      bi_content=""
      if [[ -e "$BI_RES_FILE" ]]; then
        bi_content=$(cat "$BI_RES_FILE" | grep $one_hash | tail -n 1)
        if [[ -z "$bi_content" ]]; then
          HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
        else
          HASH_LINE="${HASH_LINE},${bi_content}"
        fi
      else
        if [[ -e "$BI_RES_BAK" ]]; then
          bi_content=$(cat "$BI_RES_FILE" | grep $one_hash | tail -n 1)
          if [[ -z "$bi_content" ]]; then
            HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
          else
            HASH_LINE="${HASH_LINE},${bi_content}"
          fi
        else
          HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
          #print_log "No $BI_RES_FILE & $BI_RES_BAK, bisect result is $NULL" "$SUMMARIZE_LOG"
        fi
      fi
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

  #print_log "$hash_one_c" "$SUMMARIZE_LOG"
  fill_line "$hash_one_c" "description"
  fill_line "$hash_one_c" "key_word"
  fill_line "$hash_one_c" "key_ok"
  fill_line "$hash_one_c" "repro_kernel"
  fill_line "$hash_one_c" "all_kernels"
  fill_line "$hash_one_c" "nker_hash"
  fill_line "$hash_one_c" "iker_tag_4"
  fill_line "$hash_one_c" "c_file"
  fill_line "$hash_one_c" "bi_8"
  echo "$HASH_LINE" >> $SUMMARY_C_CSV
}

fill_no_c() {
  local hash_one_no_c=$1

  # init HASH_LINE in each loop
  HASH_LINE=""
  HASH_LINE="$hash_one_no_c"

  #print_log "$hash_one_c" "$SUMMARIZE_LOG"
  fill_line "$hash_one_no_c" "description"
  fill_line "$hash_one_no_c" "key_word"
  fill_line "$hash_one_no_c" "key_ok"
  fill_line "$hash_one_no_c" "repro_kernel"
  fill_line "$hash_one_no_c" "all_kernels"
  fill_line "$hash_one_no_c" "nker_hash"
  fill_line "$hash_one_no_c" "iker_tag_4"
  echo "$HASH_LINE" >> $SUMMARY_NO_C_CSV
}

summarize_no_c() {
  local hash_one_no_c=""
  local no_c_header=""

  no_c_header="HASH,description,key_word,key_ok,repro_kernel,all_kers,nker_hash,i_tag,m_tag,i_commit,m_commit"
  echo "$no_c_header" > $SUMMARY_NO_C_CSV
  print_log "----->  No C header: $no_c_header" "$SUMMARIZE_LOG"
  for hash_one_no_c in $HASH_NO_C; do
    fill_no_c "$hash_one_no_c"
  done
}

summarize_c() {
  local hash_one_c=""
  local c_header=""

  c_header="HASH,description,key_word,key_ok,repro_kernel,all_kers,nker_hash,i_tag,m_tag,i_commit,m_commit,c_file,bi_hash,bi_commit,bi_path,rep_time,mainline_result,bi_result,bad_commit,bi_comment"
  echo "$c_header" > $SUMMARY_C_CSV
  print_log "----->  C header:$c_header" "$SUMMARIZE_LOG"
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
