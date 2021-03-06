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
  print_log "3 items are filled: $TAG, $SPECIFIC_KER, $START_COMMIT" "$UPDATE_LOG"
  echo $TAG > $ECOM_FILE
  echo $SPECIFIC_KER > $KSRC_FILE
  echo $START_COMMIT > $SCOM_FILE
  print_log "run_syz.sh -t $TAG -k $SPECIFIC_KER -s $START_COMMIT" "$UPDATE_LOG"
  run_syz.sh -t "$TAG" -k "$SPECIFIC_KER" -s "$START_COMMIT"
fi
