#!/usr/bin/env bash
set -euo pipefail
mkdir -p out pages

echo "Starting FlareSolverr..."
docker run -d --name flr -p 8191:8191 -e LOG_LEVEL=info ghcr.io/flaresolverr/flaresolverr:latest
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8191/health >/dev/null; then echo ready; break; fi
  sleep 2
done

# Create a persistent browser session so CF is solved once
SESSION=$(python3 - <<'PY'
import json,urllib.request
payload=json.dumps({"cmd":"sessions.create"}).encode()
req=urllib.request.Request("http://127.0.0.1:8191/v1", data=payload, headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req, timeout=60) as r:
    data=json.load(r)
print(data.get("session") or "")
PY
)
echo "SESSION=${SESSION}"

python3 - "$SESSION" <<'PY'
import json, sys, time, urllib.request, urllib.error
from pathlib import Path

session = sys.argv[1]
base = "https://www.mjtoysinc.com/wp-json/wc/store/v1/products"
pages_dir = Path("pages")
pages_dir.mkdir(exist_ok=True)

def flr_get(url, tries=4):
    last = None
    for attempt in range(1, tries+1):
        payload = {
            "cmd": "request.get",
            "url": url,
            "maxTimeout": 120000,
        }
        if session:
            payload["session"] = session
        body = json.dumps(payload).encode()
        req = urllib.request.Request(
            "http://127.0.0.1:8191/v1",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=150) as r:
                data = json.load(r)
        except Exception as e:
            last = e
            print(f"  attempt {attempt} error: {e}")
            time.sleep(5 * attempt)
            continue
        sol = data.get("solution") or {}
        status = sol.get("status")
        text = sol.get("response") or ""
        print(f"  attempt {attempt}: flr msg={data.get('message')!r} http={status} len={len(text)}")
        start = text.find("[")
        end = text.rfind("]")
        if status == 200 and start >= 0 and end > start:
            return json.loads(text[start:end+1])
        last = data.get("message") or status
        time.sleep(5 * attempt)
    raise RuntimeError(f"failed after retries: {last}")

page = 1
total = 0
consecutive_fail = 0
while page <= 200:
    out = pages_dir / f"page_{page:03d}.json"
    url = f"{base}?per_page=100&page={page}&_fields=id,sku,name,prices,is_in_stock,add_to_cart,permalink"
    print(f"Fetching page {page}...")
    try:
        data = flr_get(url)
    except Exception as e:
        consecutive_fail += 1
        print(f"STOP-ISH page={page} err={e} fails={consecutive_fail}")
        if consecutive_fail >= 3:
            print("Too many consecutive failures; stopping.")
            break
        time.sleep(10)
        continue
    consecutive_fail = 0
    out.write_text(json.dumps(data, ensure_ascii=False))
    n = len(data)
    print(f"page {page}: {n} items")
    if n == 0:
        out.unlink(missing_ok=True)
        break
    total += n
    if n < 100:
        break
    page += 1
    time.sleep(1)

print(f"TOTAL_RAW_PAGES={page} TOTAL={total}")

# destroy session
if session:
    try:
        payload = json.dumps({"cmd": "sessions.destroy", "session": session}).encode()
        req = urllib.request.Request("http://127.0.0.1:8191/v1", data=payload, headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        print("session destroy", e)
PY

python3 build.py
docker rm -f flr || true
