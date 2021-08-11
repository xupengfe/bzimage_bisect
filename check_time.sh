#!/bin/bash

FILE=$1
POINT=$2
TIME=""

check_time() {
  local dmesg_file=$1
  local result=""
  local time=""

  [[ -e "$dmesg_file" ]] || {
    echo "dmesg_file:$dmesg_file is not exist, exit"
    exit 1
  }

  result=$(cat $dmesg_file | grep "$POINT" | head -n 1)
  [[ -n "$result" ]] || {
    echo "No $POINT dmesg info:$result, exit"
    exit 1
  }

  time=$(echo "$result" | awk -F " " '{print $2}' | cut -d '.' -f 1)
  echo "Found time:$time!"
  if [[ "$time" -le 20 ]]; then
    TIME=20
  elif [[ "$time" -le 60 ]]; then
    TIME=$time
  else
    TIME=$((time+60))
  fi
  echo "Set TIME:$TIME"
}

[[ -n "$POINT" ]] || {
  echo "POINT:$POINT is null, exit"
  exit 1
}

check_time "$FILE"
