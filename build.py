#!/usr/bin/env python3
import json, csv
from pathlib import Path
products=[]
for p in sorted(Path('pages').glob('page_*.json')):
    try:
        data=json.loads(p.read_text())
        if isinstance(data, list):
            products.extend(data)
    except Exception as e:
        print('skip', p, e)
seen=set(); uniq=[]
for pr in products:
    i=pr.get('id')
    if i in seen: continue
    seen.add(i); uniq.append(pr)

def price_of(pr):
    prices=pr.get('prices') or {}
    raw=prices.get('price') or '0'
    minor=int(prices.get('currency_minor_unit') or 2)
    try: return float(raw)/(10**minor)
    except: return 0.0

Path('out').mkdir(exist_ok=True)
with open('out/mj_storeapi_full.csv','w',newline='',encoding='utf-8') as f:
    w=csv.writer(f)
    w.writerow(['id','sku','name','price_usd','is_in_stock','case_multiple','permalink'])
    for pr in uniq:
        atc=pr.get('add_to_cart') or {}
        w.writerow([pr.get('id',''),pr.get('sku',''),pr.get('name',''),f'{price_of(pr):.2f}','true' if pr.get('is_in_stock') else 'false','' if atc.get('multiple_of') is None else atc.get('multiple_of'),pr.get('permalink','')])
instock=[p for p in uniq if p.get('is_in_stock')]
oos=[p for p in uniq if not p.get('is_in_stock')]
instock.sort(key=price_of, reverse=True)
oos.sort(key=price_of, reverse=True)
with open('out/mj_urls_instock_first.txt','w',encoding='utf-8') as f:
    for pr in instock+oos:
        if pr.get('permalink'): f.write(pr['permalink']+'\n')
meta={'total':len(uniq),'in_stock':len(instock),'price_above_0':sum(1 for p in uniq if price_of(p)>0),'pages':len(list(Path('pages').glob('page_*.json')))}
Path('out/meta.json').write_text(json.dumps(meta,indent=2))
print(meta)
