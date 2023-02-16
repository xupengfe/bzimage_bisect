#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just call update.sh and run_syz.sh

export PATH=${PATH}:/root/bzimage_bisect
UPDATE_LOG="/root/update_bzimage_bisect.log"
source "bisect_common.sh"

# TAG or END/HEAD COMMIT both ok
TAG=$1
# Specific kernel source folder path on target platform
SPECIFIC_KER=$2
START_COMMIT=$3
END_COMMIT=""
IP=$(ip a | grep inet | grep brd | grep dyn | awk -F " " '{print $2}' | cut -d '/' -f 1)
HOST=$(hostname)
SUMMARY_C_CSV="/root/summary_c_${IP}_${HOST}.csv"

# Backup previous test results and clean for new test commit kernel
move_pre_csv_crashes() {
  local pre_ker_src=$1
  local pre_end_commit=$2
  local pre_end_tag=$3

  if [[ -z "$pre_end_tag" ]]; then
    print_log "No end tag will use end commit: mkdir ${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_commit}"  "$UPDATE_LOG"
    # Previous backup is useless and clean to make sure next move successfully
    rm -rf "${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_commit}"
    print_log "mv ${SYZ_FOLDER}  ${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_commit}" "$UPDATE_LOG"
    mv "${SYZ_FOLDER}"  "${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_commit}"
    mkdir -p "${SYZ_FOLDER}"

    # Move BI_CSV under IMAGE_FOLDER
    mv "$BISECT_CSV" "${IMAGE_FOLDER}/${BI_CSV}${pre_ker_src}_${pre_end_commit}"
    head -n 1 "${IMAGE_FOLDER}/${BI_CSV}${pre_ker_src}_${pre_end_commit}" > "$BISECT_CSV"
  else
    print_log "Has end tag:$pre_end_tag, mkdir ${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_tag}" "$UPDATE_LOG"
    rm -rf "${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_tag}"
    print_log "mv ${SYZ_FOLDER}  ${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_tag}" "$UPDATE_LOG"
    mv "${SYZ_FOLDER}"  "${SYZ_WORKDIR}/crashes_${pre_ker_src}_${pre_end_tag}"
    mkdir -p "${SYZ_FOLDER}"

    # Move BI_CSV under IMAGE_FOLDER
    mv "$BISECT_CSV" "${IMAGE_FOLDER}/${BI_CSV}${pre_ker_src}_${pre_end_tag}"
    head -n 1 "${IMAGE_FOLDER}/${BI_CSV}${pre_ker_src}_${pre_end_tag}" > "$BISECT_CSV"
  fi
}

recover_pre_match_csv_crashes() {
  [[ -d "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${TAG}" ]] && {
    print_log "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${TAG} exist, will copy"  "$UPDATE_LOG"
    cp -rf "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${TAG}" "${SYZ_FOLDER}"
  }

  [[ -d "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${END_COMMIT}" ]] && {
    print_log "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${END_COMMIT} exist, will copy"  "$UPDATE_LOG"
    cp -rf "${SYZ_WORKDIR}/crashes_${SPECIFIC_KER}_${END_COMMIT}" "${SYZ_FOLDER}"
  }

  if [[ -e "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${TAG}" ]]; then
    print_log "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${TAG} exist, will copy"  "$UPDATE_LOG"
    cp -rf "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${TAG}" "$BISECT_CSV"
  else
    # Only tag csv doesn't exist, will copy the commit id csv to recover
    [[ -e "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${END_COMMIT}" ]] && {
      print_log "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${END_COMMIT} exist, will copy"  "$UPDATE_LOG"
      cp -rf "${IMAGE_FOLDER}/${BI_CSV}${SPECIFIC_KER}_${END_COMMIT}" "$BISECT_CSV"
    }
  fi
}

# If End commit didn't change, will not back up, and copy previous csv and crashes
# IF End commit changed, will move csv and crashes for back up and clean new one for test
check_backup() {
  local pre_end_tag=""
  local pre_end_commit=""
  local pre_ker_src=""

  pre_end_tag=$(cat "$TAG_ORIGIN" 2>/dev/null)
  pre_end_commit=$(cat "$ECOM_FILE" 2>/dev/null)
  pre_ker_src=$(cat "$KSRC_FILE" 2>/dev/null)
  pre_ker_src=$(echo "$pre_ker_src" | tr "/" "_")

  if [[ -z "$pre_ker_src" ]]; then
    print_log "[ERROR]Previous ker src:$pre_ker_src is null! Exit!" "$UPDATE_LOG"
    return 0
  fi

  if [[ -z "$pre_end_commit" ]]; then
    print_log "[WARN]Previous end commit:$pre_end_commit is null! Skip check commit!" "$UPDATE_LOG"
  else
    if [[ "$END_COMMIT" == "$pre_end_commit" ]]; then
      print_log "End commit:$END_COMMIT is same as previous:$pre_end_commit. Do nothing." "$UPDATE_LOG"
    else
      print_log "End commit:$END_COMMIT is not previous:$pre_end_commit, backup." "$UPDATE_LOG"
      move_pre_csv_crashes "$pre_ker_src" "$pre_end_commit" "$pre_end_tag"
      # Only commit kernel changed will recover after move
      recover_pre_match_csv_crashes
    fi
  fi
}

check_summary_csv_backup() {
  local pre_end_commit=""
  local pre_end_tag=""
  local pre_end_tag_csv=""
  local pre_end_com_csv=""

  if [[ -e "$PRE_ECOM_FILE" ]]; then
    pre_end_commit=$(cat "$PRE_ECOM_FILE")
    [[ -e "$PRE_TAG_ORIGIN" ]] && pre_end_tag=$(cat "$PRE_TAG_ORIGIN")
    if [[ "$END_COMMIT" == "$pre_end_commit" ]]; then
      print_log "End commit:$END_COMMIT same as previous, skip." "$UPDATE_LOG"
    else
      mkdir -p "$BACKUP_CSV"
      if [[ -n "$pre_end_tag" ]]; then
        pre_end_tag_csv="${BACKUP_CSV}/summary_c_${IP}_${HOST}_${SPECIFIC_KER}_${pre_end_tag}.csv"
        print_log "End commit:$END_COMMIT not same pre:$pre_end_commit, backup to $pre_end_tag_csv." "$UPDATE_LOG"
        mv "$SUMMARY_C_CSV" "$pre_end_tag_csv"
        head -n 1 "$pre_end_tag_csv" > "$SUMMARY_C_CSV"
      else
        pre_end_com_csv="${BACKUP_CSV}/summary_c_${IP}_${HOST}_${SPECIFIC_KER}_${pre_end_commit}.csv"
        print_log "End commit:$END_COMMIT not same pre:$pre_end_commit, backup to $pre_end_com_csv." "$UPDATE_LOG"
        mv "$SUMMARY_C_CSV" "$pre_end_com_csv"
        head -n 1 "$pre_end_com_csv" > "$SUMMARY_C_CSV"
      fi
    fi
  else
    print_log "No pre end commit file:$PRE_ECOM_FILE, skip $SUMMARY_C_CSV backup" "$UPDATE_LOG"
  fi
}

# run_syzkaller.sh start from here
update.sh
print_log "TAG:$TAG  KER:$SPECIFIC_KER START_COMMIT:$START_COMMIT" "$UPDATE_LOG"
print_log "start_scan_service" "$UPDATE_LOG"
start_scan_service

if [[ -z "$START_COMMIT" ]]; then
  if [[ -n "$SPECIFIC_KER"  ]]; then
    print_err "$SPECIFIC_KER is not null, but start commit is null:$START_COMMIT" "$UPDATE_LOG"
    return 1
  fi
  print_log "run_syz.sh -t $TAG" >> "$UPDATE_LOG"
  run_syz.sh -t "$TAG"
else
  print_log "3 items are filled will fill $SCOM_FILE: $TAG, $SPECIFIC_KER, $START_COMMIT" "$UPDATE_LOG"
  cd "$SPECIFIC_KER"  || {
    print_log "[ERROR]cd $SPECIFIC_KER failed!" "$UPDATE_LOG"
    return 1
  }
  git fetch origin
  sleep 2
  # tag means end commit id!
  tag=$(git show $TAG | grep "^commit" | head -n 1 | awk -F " " '{print $NF}')
  start_commit=$(git show $START_COMMIT | grep "^commit" | head -n 1 | awk -F " " '{print $NF}')
  [[ -z "$start_commit" ]] && {
    print_log "[ERROR]start_commit:$start_commit is null!" "$UPDATE_LOG"
    return 1
  }

  # tag means end commit id!
  print_log "First check END COMMIT: $TAG -> $tag" "$UPDATE_LOG"
  [[ -n "$tag" ]] && {
    print_log "END COMMIT: $TAG -> $tag" "$UPDATE_LOG"
    END_COMMIT=$tag
  }

  check_backup

  [[ -n "$start_commit" ]] && {
    print_log "START COMMIT:$START_COMMIT -> $start_commit, TAG:$TAG" "$UPDATE_LOG"
    START_COMMIT=$start_commit
  }
  cp -rf "$ECOM_FILE" "$PRE_ECOM_FILE"
  cp -rf "$TAG_ORIGIN" "$PRE_TAG_ORIGIN"
  cp -rf "$KSRC_FILE" "$PRE_KSRC_FILE"
  cp -rf "$SCOM_FILE" "$PRE_SCOM_FILE"

  check_summary_csv_backup

  echo "$END_COMMIT" > "$ECOM_FILE"
  echo "$TAG" > "$TAG_ORIGIN"
  echo "$SPECIFIC_KER" > "$KSRC_FILE"
  echo "$START_COMMIT" > "$SCOM_FILE"

  print_log "run_syz.sh -t $END_COMMIT -k $SPECIFIC_KER"  "$UPDATE_LOG"
  run_syz.sh -t "$END_COMMIT" -k "$SPECIFIC_KER"
fi
