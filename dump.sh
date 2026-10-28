#!/usr/bin/env bash
set -euo pipefail
mkdir -p out pages
page=1
total=0
while true; do
  url="https://www.mjtoysinc.com/wp-json/wc/store/v1/products?per_page=100&page=${page}&_fields=id,sku,name,prices,is_in_stock,add_to_cart,permalink"
  echo "Fetching page ${page}..."
  code=$(curl -sS -A 'Mozilla/5.0 (compatible; 7ExchangeBot/1.0)' -o "pages/page_$(printf '%03d' "$page").json" -w '%{http_code}' "$url" || echo fail)
  echo "http=${code}"
  if [ "$code" != "200" ]; then
    echo "STOP page=${page} http=${code}"
    head -c 300 "pages/page_$(printf '%03d' "$page").json" || true
    echo
    break
  fi
  n=$(python3 -c "import json; print(len(json.load(open('pages/page_$(printf '%03d' $page).json'))))")
  echo "page ${page}: ${n} items"
  if [ "$n" = "0" ]; then
    rm -f "pages/page_$(printf '%03d' "$page").json"
    break
  fi
  total=$((total+n))
  page=$((page+1))
  sleep 1
done
echo "TOTAL_RAW_PAGES=$((page-1)) TOTAL=${total}"
python3 build.py
