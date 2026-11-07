#!/usr/bin/env python3
"""Follow-up public API diagnosis, 3-second gaps for LibriVox requests."""
import urllib.request,urllib.error,json,time
tests=[
 ("LibriVox known id via query", "https://librivox.org/api/feed/audiobooks/?id=52&format=json"),
 ("LibriVox 1 newest via query", "https://librivox.org/api/feed/audiobooks/?limit=1&sort_order=desc&format=json"),
 ("LibriVox known id via path", "https://librivox.org/api/feed/audiobooks/id/52/format/json"),
 ("LibriVox RSS known id", "https://librivox.org/rss/52"),
]
for i,(name,url) in enumerate(tests):
 if i: time.sleep(3)
 req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0 (compatible; DarkReaderApiCheck/1.0)","Accept":"application/json,application/xml;q=0.9,*/*;q=0.5"})
 try:
  with urllib.request.urlopen(req,timeout=16) as r:
   b=r.read(128000)
   out={"test":name,"status":r.status,"ct":r.headers.get("content-type"),"size":len(b),"sample":b[:90].decode("utf-8","replace")}
   if "json" in r.headers.get("content-type",""):
    obj=json.loads(b);out["keys"]=list(obj)[:8] if isinstance(obj,dict) else []
   print(json.dumps(out,ensure_ascii=False),flush=True)
 except Exception as e:
  print(json.dumps({"test":name,"error":str(e)[:220]},ensure_ascii=False),flush=True)
