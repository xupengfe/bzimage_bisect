#!/bin/bash

echo "gcc -o repro repro.c"
gcc -o repro repro.c
for((i=0; ;i++)); do
  echo "$i times ./repro"
  ./repro
done
