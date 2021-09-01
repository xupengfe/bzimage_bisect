#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just call update.sh and run_syz.sh

export PATH=${PATH}:/root/bzimage_bisect
UPDATE_LOG="/root/update_bzimage_bisect.log"

readonly KSRC_FILE="/opt/ker_src"
readonly ECOM_FILE="/opt/end_commit"
readonly SCOM_FILE="/opt/start_commit"

# TAG or END/HEAD COMMIT both ok
TAG=$1
# Specific kernel source folder path on target platform
SPECIFIC_KER=$2
START_COMMIT=$3

update.sh
echo "run_syz.sh -t $TAG -k $SPECIFIC_KER -s $START_COMMIT" >> "$UPDATE_LOG"

if [[ -z "$START_COMMIT" ]]; then
  if [[ -n "$SPECIFIC_KER"  ]]; then
    echo "$SPECIFIC_KER is not null, but start commit is null:$START_COMMIT"
    echo "$SPECIFIC_KER is not null, but start commit is null:$START_COMMIT" >> "$UPDATE_LOG"
    return 1
  fi
  echo "run_syz.sh -t $TAG" >> "$UPDATE_LOG"
  run_syz.sh -t "$TAG"
else
  echo "3 items are filled: $TAG, $SPECIFIC_KER, $START_COMMIT" >> "$UPDATE_LOG"
  echo $TAG > $ECOM_FILE
  echo $SPECIFIC_KER > $KSRC_FILE
  echo $START_COMMIT > $SCOM_FILE
  echo "run_syz.sh -t $TAG -k $SPECIFIC_KER -s $START_COMMIT" >> "$UPDATE_LOG"
  run_syz.sh -t "$TAG" -k "$SPECIFIC_KER" -s "$START_COMMIT"
fi
