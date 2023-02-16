#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just update git

RUNSYZ_FOLDER="/root/bzimage_bisect"
UPDATE_LOG="/root/update_bzimage_bisect.log"

source /etc/environment
cd "$RUNSYZ_FOLDER"
git pull
