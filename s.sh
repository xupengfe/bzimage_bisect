#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Just summary c csv hash issues

DEFAULT_PATH="/home/summary"
SUMMARY_CSV="${DEFAULT_PATH}/summary.csv"
SUMMARY_CSV_BAK="${DEFAULT_PATH}/summary_bak.csv"

summary_file() {
  local file=$1
  local content=""
  local summary_hashs=""
  local tar_hashs=""
  local tar_hash=""
  local sum_hash_line=""
  local tar_hash_line=""
  local bi_result=""
  local bad_commit=""

  cd "$DEFAULT_PATH"
  content=$(cat $SUMMARY_CSV)
  [[ -z "$content" ]] && {
    echo "$SUMMARY_CSV is null, just copy firest one in it"
    cp -rf $file $SUMMARY_CSV
    echo "sed -i s/$/,${file}/ summary.csv"
    sed -i "s/$/",${file}"/" summary.csv
    return 0
  }

  summary_hashs=$(cat "$SUMMARY_CSV" | awk -F "," '{print $1}')
  tar_hashs=$(cat "$file" | awk -F "," '{print $1}')

  for tar_hash in $tar_hashs; do
    [[ "$tar_hash" == "HASH" ]] && continue
    tar_hash_line=""
    tar_hash_line=$(cat "$file" | grep "$tar_hash" | tail -n 1)
    if [[ "$summary_hashs" == *"$tar_hash"* ]]; then
      bi_result=""
      sum_hash_line=""
      sum_hash_line=$(cat "$SUMMARY_CSV" | grep "$tar_hash" | tail -n 1)
      bi_result=$(echo "$sum_hash_line" | awk -F "," '{print $19}')
      [[ "$bi_result" == "pass" ]] && {
        echo "Alrady include $tar_hash with bisect pass, continue"
        continue
      }
      bad_commit=$(echo "$tar_hash_line" | awk -F "," '{print $20}')
      if [[ "$bad_commit" == "null" ]]; then
        echo "$tar_hash bad_commit is null, do nothing"
      elif [[ -z "$bad_commit" ]]; then
        echo "$tar_hash bad_commit:$bad_commit is zero, do nothing"
      else
        echo "$tar_hash bad_commit:$bad_commit, fill this line from $file"
        sed -i "/^${tar_hash}/d"  summary.csv
        echo "${tar_hash_line},${file}" >> $SUMMARY_CSV
      fi

      echo "Alrady include $tar_hash with fail, do nothing"
    else
      echo "Add new $tar_hash from $file"
      echo "${tar_hash_line},${file}" >> $SUMMARY_CSV
    fi
  done
}

summary_c_csv() {
  local c_files=""
  local c_file=""

  cd "$DEFAULT_PATH"
  c_files=$(ls -1 summary_c_*.csv)

  cp -rf "$SUMMARY_CSV" "$SUMMARY_CSV_BAK"
  cat /dev/null > "$SUMMARY_CSV"

  for c_file in $c_files; do
    summary_file "$c_file"
  done
}

cd "$DEFAULT_PATH"
${DEFAULT_PATH}/collect.sh

summary_c_csv
