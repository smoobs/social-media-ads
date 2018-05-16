#!/bin/bash

find . -iname '*.pdf' | while read pdf; do
  out="${pdf%.*}"
  echo "$pdf -> $out"
  pdfimages "$pdf" -png "$out"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

