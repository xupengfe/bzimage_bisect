#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Start up scan_bisect.sh service

syzkaller_log="/root/setup_syzkaller.log"
BZ_PATH="/root/bzimage_bisect"
SCAN_SCRIPT="scan_bisect.sh"
SCAN_SRV="scansyz.service"

start_scan_service() {
  local scan_service="/etc/systemd/system/${SCAN_SRV}"
  local check_scan_pid=""

  check_scan_pid=$(ps -ef | grep scan_bisect \
                  | grep sh \
                  | awk -F " " '{print $2}' \
                  | head -n 1)

  [[ -e "$scan_service" ]] && [[ -e "/usr/bin/${SCAN_SCRIPT}" ]] && {
    if [[ -z "$check_scan_pid" ]];then
      echo "no $SCAN_SCRIPT pid, will reinstall"
    else
      echo "$scan_service & /usr/bin/$SCAN_SCRIPT and pid:$SCAN_SCRIPT exist, no need reinstall $SCAN_SRV service"
      echo "$scan_service & /usr/bin/$SCAN_SCRIPT and pid:$SCAN_SCRIPT exist, no need reinstall $SCAN_SRV service" >> "$syzkaller_log"
      return 0
    fi
  }

  [[ -z "$check_scan_pid" ]] || {
    echo "Clean old scan pid:$check_scan_pid"
    kill -9 $check_scan_pid
  }

  echo "BZ_PATH:$BZ_PATH"
  [[ -d "$BZ_PATH" ]] || {
    echo "No $BZ_PATH folder!"
    exit 1
  }

  echo "ln -s ${BZ_PATH}/${SCAN_SCRIPT} /usr/bin/${SCAN_SCRIPT}"
  rm -rf /usr/bin/${SCAN_SCRIPT}
  ln -s ${BZ_PATH}/${SCAN_SCRIPT} /usr/bin/${SCAN_SCRIPT}

echo "[Service]" > $scan_service
echo "Type=simple" >> $scan_service
echo "ExecStart=${BZ_PATH}/${SCAN_SCRIPT}" >> $scan_service
echo "[Install]" >> $scan_service
echo "WantedBy=multi-user.target graphical.target" >> $scan_service

sleep 1

systemctl daemon-reload
systemctl enable $SCAN_SRV
systemctl start $SCAN_SRV

systemctl status $SCAN_SRV
}

start_scan_service
