#!/bin/bash

find . -iname '*.png' | while read png; do
  out="${png%.*}"
  txt="$out.txt"
  if [ "$png" -nt "$txt" ]; then
    echo "$png -> $txt"
    tesseract "$png" "$out"
  fi
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

