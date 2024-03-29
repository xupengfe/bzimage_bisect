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
SUMMARY_WARN_LOG="/root/warn_summary.log"
[[ -z "IP" ]] && {
  print_log "WARN: IP:$IP is null, sleep 5 to fetch again" "$SUMMARY_WARN_LOG"
  IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
  print_log "Fetch IP again:$IP" "$SUMMARY_WARN_LOG"
}
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"
SUMMARY_NO_C_CSV="/root/summary_no_c_${IP}_${HOST}.csv"
# Hard code kernel source, will improve in future
if [[ -e "$KSRC_FILE" ]]; then
  KER_SOURCE=$(cat $KSRC_FILE 2>/dev/null)
  cd $KER_SOURCE
  git fetch origin
else
  print_log "Error! No $KSRC_FILE file will use /root/os.linux.intelnext.kernel" "$SUMMARIZE_LOG"
  KER_SOURCE="/root/os.linux.intelnext.kernel"
fi
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
# the latest report
REPO=""

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-k KERNEL][-m COMMIT][-s START_COMMIT][-h]
  -k  KERNEL SPECIFIC source folder(optional)
  -m  COMMIT SPECIFIC END COMMIT ID(optional)
  -s  START COMMIT(optional)
  -h  show this
__EOF
  exit 1
}

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
  local kers_content=""
  local nmac_info=""
  local kers=""
  local ker=""
  local nker=""
  local new_ker_hash=""
  local ndate=""
  # latest logX file
  local log_file=""

  cd ${SYZ_FOLDER}/${one_hash}
  case $item_file in
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

      # Sample "      Not tainted 6.1.0-rc5-094226ad94f4 #1"
      fker_content=$(grep "Not tainted" repro.report | head -n 1 | awk -F "Not tainted " '{print $2}' | cut -d " " -f 1)
      if [[ -n "$fker_content" ]]; then
        FKER_CONTENT="$fker_content"
        HASH_LINE="${HASH_LINE},${fker_content}"
        return 0
      fi

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
      kers_content=""
      kers=""
      NKERS=""
      kers_content=$(grep "PID:" report* 2>/dev/null | grep "#" | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}' | uniq)

      [[ -z "$kers_content" ]] && {
        nmac_info=$(ls -ltra machineInfo* 2>/dev/null | awk -F " " '{print $NF}' | tail -n 1)
        [[ -z "$nmac_info" ]] && {
          print_log "All kernels: No ${one_hash}/machineInfo fill $FKER_CONTENT" "$SUMMARIZE_LOG"
          NKERS=$FKER_CONTENT
          HASH_LINE="${HASH_LINE},|${FKER_CONTENT}|"
          return 0
        }
        kers_content=$(cat $nmac_info | grep bzImage | awk -F "kernel\" \"" '{print $2}' | awk -F "\"" '{print $1}' | uniq)
      }

      # kers_content may be several kernels with enter, maybe same, solve them
      for ker in $kers_content; do
        [[ "$kers" == *"$ker"* ]] && continue
        kers="${kers}|${ker}"
      done
        kers="${kers}|"
        NKERS=$kers
      HASH_LINE="${HASH_LINE},${kers}"
      ;;
    nker_hash)
      NKER_HASH=""
      REPO=""

      # get latest report file name
      REPO=$(ls -ltra ${SYZ_FOLDER}/${one_hash}/report* 2>/dev/null| tail -n 1 | awk -F "/" '{print $NF}')
      if [[ -n "$REPO" ]]; then
        nker=$(cat ${SYZ_FOLDER}/${one_hash}/${REPO} | grep "Not tainted" | head -n 1 | awk -F " #" '{print $(NF-1)}' | awk -F " " '{print $NF}')
        if [[ -n "$nker" ]]; then
          new_ker_hash=$(echo $nker | awk -F "+|" '{print $(NF-1)}' 2>/dev/null| awk -F "-" '{print $NF}')
          [[ -z "$new_ker_hash" ]] && print_err "Solve nker $nker with +| to null:$new_ker_hash"
          NKER_HASH=$new_ker_hash
          HASH_LINE="${HASH_LINE},${new_ker_hash}"
          return 0
        else
          print_log "WARN: ${SYZ_FOLDER}/${one_hash}/${REPO} no kernel:$nker" "$SUMMARIZE_LOG"
        fi
      else
	      print_log "WARN: ${SYZ_FOLDER}/${one_hash}/${REPO} no report!" "$SUMMARIZE_LOG"
      fi

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
      KER_SOURCE=$(cat $KSRC_FILE 2>/dev/null)
      cd $KER_SOURCE
      git fetch origin
      I_TAG=""
      M_TAG=""
      i_commit=""
      m_commit=""

      # if $NKERS is null situation, fill null
      [[ -z "$NKER_HASH" ]] && {
        HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL"

        return 0
      }

      # will always use the COMMIT_SPECIFIC and START_COMMIT
      [[ -e "$ECOM_FILE" ]] && \
        COMMIT_SPECIFIC=$(cat $ECOM_FILE 2>/dev/null)

      [[ -e "$SCOM_FILE" ]] && \
        START_COMMIT=$(cat $SCOM_FILE 2>/dev/null)

    # For SPECIFIC COMMIT and branch
    [[ -z "$KERNEL_SPECIFIC" ]] || {
      #print_log "Check specific kernel: $KERNEL_SPECIFIC" "$SUMMARIZE_LOG"
      if [[ -d "$KERNEL_SPECIFIC" ]]; then
        [[ "$COMMIT_SPECIFIC" == *"$NKER_HASH"* ]] && {
          I_TAG="$COMMIT_SPECIFIC"
          M_TAG="$START_COMMIT"
          i_commit="$COMMIT_SPECIFIC"
          m_commit="$START_COMMIT"
          HASH_LINE="${HASH_LINE},${I_TAG},${M_TAG},${i_commit},${m_commit}"
          #print_log "Specific branch fill END:$COMMIT_SPECIFIC start:$START_COMMIT" "$SUMMARIZE_LOG"

          return 0
        }
        # for CET branch
        [[ "$NKER_HASH" == "cetkvm" ]] && {
          I_TAG="$COMMIT_SPECIFIC"
          M_TAG="$START_COMMIT"
          i_commit="$COMMIT_SPECIFIC"
          m_commit="$START_COMMIT"
          HASH_LINE="${HASH_LINE},${I_TAG},${M_TAG},${i_commit},${m_commit}"
          print_log "CET branch fill END:$COMMIT_SPECIFIC start:$START_COMMIT" "$SUMMARIZE_LOG"

          return 0
        }
      fi
    }
      # will always use commit id for I_TAG
      I_TAG="$COMMIT_SPECIFIC"
      #I_TAG=$(git show-ref --tags  | grep $NKER_HASH | grep "intel" | awk -F "/" '{print $NF}' | tail -n 1)
      if [[ -z "$I_TAG" ]]; then
        I_TAG=$(git ls-remote | grep $NKER_HASH | grep "intel" | awk -F "/" '{print $NF}' | tail -n 1)
        [[ -z "$I_TAG" ]] && {
          I_TAG=$(git show $NKER_HASH | grep commit | cut -d " " -f 2)
          [[ -z "$I_TAG" ]] && {
            print_err "git ls-remote could not get I_TAG with $NKER_HASH in $KER_SOURCE" "$SUMMARIZE_LOG"
            HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL"
            return 0
          }
        }
        # print_log "git fetch origin $I_TAG" "$SUMMARIZE_LOG"
        git fetch origin $I_TAG
        git fetch origin
      fi

      HASH_LINE="${HASH_LINE},${I_TAG}"

      # will always use start commit id for M_TAG
      M_TAG="$START_COMMIT"
      HASH_LINE="${HASH_LINE},${M_TAG}"
      #M_TAG=$(echo "$I_TAG" | awk -F "intel-" '{print $2}' | awk -F "-20" '{print $1}' | tail -n 1)
      #if [[ -n "$M_TAG" ]]; then
      #  M_TAG="v${M_TAG}"
      #  # v5.14-final should change to v5.14
      #  [[ "$M_TAG" == *"-final"* ]] && {
      #    print_log "Main line:$M_TAG contain -final will remove" "$SUMMARIZE_LOG"
      #    M_TAG=$(echo "$M_TAG" | awk -F "-final" '{print $1}')
      #  }
      #  HASH_LINE="${HASH_LINE},${M_TAG}"
      #else
      #  [[ -n "$START_COMMIT" ]] && {
      #    M_TAG==$(git show "$START_COMMIT" | grep "^commit"| head -n 1 | awk -F " " '{print $2}')
      #  }
      #  [[ -n  "$M_TAG" ]] || {
      #    print_log "Could not find M_TAG or commit:$M_TAG" "$SUMMARIZE_LOG"
      #    return 0
      #  }
      #fi

      i_commit=$(git show "$I_TAG" | grep "^commit"| head -n 1 | awk -F " " '{print $2}')
      [[ -z "$i_commit" ]] && {
        print_log "ERROR: i_tag/commit:$I_TAG $i_commit null, will use $COMMIT_SPECIFIC" "$SUMMARIZE_LOG"
        i_commit=$COMMIT_SPECIFIC
      }
      HASH_LINE="${HASH_LINE},${i_commit}"

      m_commit=$(git show "$M_TAG" | grep "^commit"| head -n 1 | awk -F " " '{print $2}')
      [[ -z "$m_commit" ]] && {
        print_log "ERROR: m_tag/commit:$M_TAG $m_commit null will use $START_COMMIT" "$SUMMARIZE_LOG"
        m_commit=$START_COMMIT
      }
      HASH_LINE="${HASH_LINE},${m_commit}"
      print_log "i_tag/commit:$I_TAG $i_commit, m_tag/commit:$M_TAG $m_commit" "$SUMMARIZE_LOG"
      ;;
    ndate)
      if [[ -n "$REPO" ]]; then
        ndate=$(ls -lt ${SYZ_FOLDER}/${one_hash}/${REPO} \
                | awk -F " " '{print $6,$7,$8}')
        HASH_LINE="${HASH_LINE},${ndate}"
        return 0
      fi

      log_file=$(ls -ltra ${SYZ_FOLDER}/${one_hash}/log* 2>/dev/null \
                | tail -n 1 | awk -F "/" '{print $NF}')
      if [[ -n "$log_file" ]]; then     
        ndate=$(ls -lt ${SYZ_FOLDER}/${one_hash}/${log_file} \
                 | awk -F " " '{print $6,$7,$8}')
        HASH_LINE="${HASH_LINE},${ndate}"
        return 0
      fi

      log_file=$(ls -ltra ${SYZ_FOLDER}/${one_hash}/description 2>/dev/null \
                | tail -n 1 | awk -F "/" '{print $NF}')
      if [[ -n "$log_file" ]]; then
        ndate=$(ls -lt ${SYZ_FOLDER}/${one_hash}/${log_file} \
                 | awk -F " " '{print $6,$7,$8}')
        HASH_LINE="${HASH_LINE},${ndate}"
        return 0
      fi
      print_err "No report/log/description in ${SYZ_FOLDER}/${one_hash}, fill null!!!" "$SUMMARIZE_LOG"
      HASH_LINE="${HASH_LINE},${NULL}"
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
      if [[ -e "$BISECT_CSV" ]]; then
        bi_content=$(cat "$BISECT_CSV" | grep $one_hash | tail -n 1)
        if [[ -z "$bi_content" ]]; then
          HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
        else
          HASH_LINE="${HASH_LINE},${bi_content}"
        fi
      else
        if [[ -e "$BISECT_BAK" ]]; then
          bi_content=$(cat "$BISECT_BAK" | grep $one_hash | tail -n 1)
          if [[ -z "$bi_content" ]]; then
            HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
          else
            HASH_LINE="${HASH_LINE},${bi_content}"
          fi
        else
          HASH_LINE="${HASH_LINE},$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL,$NULL"
          #print_log "No $BISECT_CSV & $BISECT_BAK, so $NULL" "$SUMMARIZE_LOG"
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
  fill_line "$hash_one_c" "ndate"
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
  fill_line "$hash_one_no_c" "ndate"
  echo "$HASH_LINE" >> $SUMMARY_NO_C_CSV
}

summarize_no_c() {
  local hash_one_no_c=""
  local no_c_header=""

  no_c_header="HASH,description,key_word,key_ok,repro_kernel,all_kers,nker_hash,i_tag,m_tag,i_commit,m_commit,ndate"
  echo "$no_c_header" > $SUMMARY_NO_C_CSV
  print_log "----->  No C header: $no_c_header" "$SUMMARIZE_LOG"
  for hash_one_no_c in $HASH_NO_C; do
    fill_no_c "$hash_one_no_c"
  done
}

summarize_c() {
  local hash_one_c=""
  local c_header=""

  c_header="HASH,description,key_word,key_ok,repro_kernel,all_kers,nker_hash,i_tag,m_tag,i_commit,m_commit,ndate,c_file,bi_hash,bi_commit,bi_path,rep_time(s),mainline_result,bi_result,bad_commit,bi_comment"
  echo "$c_header" > $SUMMARY_C_CSV
  print_log "----->  C header:$c_header" "$SUMMARIZE_LOG"
  for hash_one_c in $HASH_C; do
    fill_c "$hash_one_c"
  done
}

parm_check() {
  [[ -z "$KERNEL_SPECIFIC" ]] && \
    KERNEL_SPECIFIC=$(cat $KSRC_FILE 2>/dev/null)

  [[ -z "$COMMIT_SPECIFIC" ]] && \
    COMMIT_SPECIFIC=$(cat $ECOM_FILE 2>/dev/null)

  [[ -z "$START_COMMIT" ]] && \
    START_COMMIT=$(cat $SCOM_FILE 2>/dev/null)

  [[ -z "$KERNEL_SPECIFIC" ]] || {
    [[ -d "$KERNEL_SPECIFIC" ]] || \
      print_err "KERNEL_SPECIFIC:$KERNEL_SPECIFIC does not exist!" "$SUMMARIZE_LOG"
  }
  cat /dev/null > $SUMMARIZE_LOG
}


summarize_issues() {
  source /root/.bashrc
  source $ENVIRONMENT
  init_hash_issues
  summarize_c
  summarize_no_c
  cp -rf "$BISECT_CSV" "$BISECT_BAK"
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
      # similar as above
      START_COMMIT=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

parm_check
summarize_issues
