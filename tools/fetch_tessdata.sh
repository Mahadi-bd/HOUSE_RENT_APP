#!/usr/bin/env bash
# Downloads the Tesseract language data (English + Bengali, "tessdata_fast", Apache-2.0)
# into assets/tessdata/. Needs internet and curl. Safe to run again.
set -euo pipefail
mkdir -p assets/tessdata
for lang in eng ben; do
  target="assets/tessdata/${lang}.traineddata"
  if [ -s "$target" ]; then echo "have $target"; continue; fi
  curl -fL --retry 3 -o "$target" "https://github.com/tesseract-ocr/tessdata_fast/raw/main/${lang}.traineddata"
  echo "downloaded $target ($(wc -c < "$target") bytes)"
done
