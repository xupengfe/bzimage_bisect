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
BISECT_HASHS=""

filter_bisect_hashs() {
  local one_hash=""
  local has_bisect=""

  if [[ -z "$ISSUE_HASHS" ]]; then
    print_log "No any cprog issues in ISSUE_HASH:$ISSUE_HASHS" "$SCAN_LOG"
  else
    for one_hash in $ISSUE_HASHS; do
      # get bisect result column 18, and check it's not null
      has_bisect=$(cat $SUMMARY_C_CSV | grep $one_hash | awk -F "," '{print $18}')
      case $has_bisect in


      esac

    done
  fi
}


scan_bisect() {
  local result=""
  local hash=""

  for (;;); do

    summary.sh
    if [[ -e "$SUMMARY_C_CSV" ]]; then
      ISSUE_HASHS=""
      ISSUE_HASHS=$(cat "$SUMMARY_C_CSV" | grep repro.cprog | awk -F "," '{print $1}')
      filter_bisect_hashs

      # list all repro.cprog issues hashs and bisect
      for hash in $BISECT_HASHS; do
        prepare_bisect_cmd
        execute_bisect
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
