#!/usr/bin/env bash
set -euo pipefail
mkdir -p out pages

echo "Starting FlareSolverr..."
docker run -d --name flr -p 8191:8191 ghcr.io/flaresolverr/flaresolverr:latest
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8191/health >/dev/null; then echo ready; break; fi
  sleep 2
done

fetch_page() {
  local page=$1
  local url="https://www.mjtoysinc.com/wp-json/wc/store/v1/products?per_page=100&page=${page}&_fields=id,sku,name,prices,is_in_stock,add_to_cart,permalink"
  python3 - "$url" "pages/page_$(printf '%03d' "$page").json" <<'PY'
import json,sys,urllib.request
url,out=sys.argv[1],sys.argv[2]
payload=json.dumps({
  "cmd":"request.get",
  "url":url,
  "maxTimeout":60000,
}).encode()
req=urllib.request.Request("http://127.0.0.1:8191/v1", data=payload, headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req, timeout=90) as r:
    data=json.load(r)
sol=data.get("solution") or {}
status=sol.get("status")
body=sol.get("response") or ""
print("flaresolverr status", status, "body_len", len(body), "msg", data.get("message"))
# strip html wrapper if any; find JSON array
start=body.find("["); end=body.rfind("]")
if start>=0 and end>start:
    open(out,"w").write(body[start:end+1])
    print("wrote", out)
else:
    open(out,"w").write(body[:2000])
    print("NO_JSON")
    sys.exit(2)
PY
}

page=1
total=0
while true; do
  echo "Fetching page ${page}..."
  if ! fetch_page "$page"; then
    echo "STOP page=${page} fetch failed"
    break
  fi
  n=$(python3 -c "import json; print(len(json.load(open('pages/page_$(printf '%03d' $page).json'))))")
  echo "page ${page}: ${n} items"
  if [ "$n" = "0" ]; then
    rm -f "pages/page_$(printf '%03d' "$page").json"
    break
  fi
  total=$((total+n))
  if [ "$n" -lt 100 ]; then
    break
  fi
  page=$((page+1))
  sleep 1
done
echo "TOTAL_RAW_PAGES=${page} TOTAL=${total}"
python3 build.py
docker rm -f flr || true
