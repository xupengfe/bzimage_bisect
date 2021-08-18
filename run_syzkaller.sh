#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just call update.sh and run_syz.sh

export PATH=${PATH}:/root/bzimage_bisect
UPDATE_LOG="/root/update_bzimage_bisect.log"

TAG=$1

update.sh
echo "run_syz.sh -t $TAG" >> "$UPDATE_LOG"
run_syz.sh -t "$TAG"
