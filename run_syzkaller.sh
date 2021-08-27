#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just call update.sh and run_syz.sh

export PATH=${PATH}:/root/bzimage_bisect
UPDATE_LOG="/root/update_bzimage_bisect.log"

# TAG or END/HEAD COMMIT both ok
TAG=$1
# Specific kernel source folder path on target platform
SPECIFIC_KER=$2

update.sh
echo "run_syz.sh -t $TAG" -k "$SPECIFIC_KER" >> "$UPDATE_LOG"
run_syz.sh -t "$TAG"
