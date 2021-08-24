#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just call update.sh and summary.sh

export PATH=${PATH}:/root/bzimage_bisect
UPDATE_LOG="/root/update_bzimage_bisect.log"

update.sh
echo "summary.sh" >> "$UPDATE_LOG"
summary.sh
