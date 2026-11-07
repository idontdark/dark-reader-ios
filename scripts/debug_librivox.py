import urllib.request,urllib.parse,urllib.error,json,time
samples=[("title","Sherlock"),("title","Pride"),("title","Alice"),("title","Adventures"),("title","The"),("author","Doyle"),("author","Austen"),("author","Verne"),("title","War"),("id","52")]
for key,term in samples:
    url="https://librivox.org/api/feed/audiobooks/?"+urllib.parse.urlencode({key:term,"format":"json","limit":"5"})
    try:
        req=urllib.request.Request(url,headers={"User-Agent":"DarkReader-iOS/0.7"})
        with urllib.request.urlopen(req,timeout=15) as r:
            data=r.read(200000)
            obj=json.loads(data)
            rows=obj.get("books",[])
            print(key,repr(term),"HTTP",r.status,"rows",len(rows),"sample",str(rows[0].get("title",""))[:55] if rows else None,flush=True)
    except Exception as e:print(key,repr(term),"ERROR",str(e),flush=True)
    time.sleep(0.4)
