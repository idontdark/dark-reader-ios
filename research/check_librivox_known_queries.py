import urllib.request,urllib.parse,urllib.error,json,time
queries=[
 ("known title",{"title":"Letters of Two Brides","format":"json","limit":"2"}),
 ("known author",{"author":"Balzac","format":"json","limit":"2"}),
 ("chapters by ID",{"id":"52","format":"json","limit":"1","extended":"1","coverart":"1"})
]
for i,(name,params) in enumerate(queries):
 if i:time.sleep(4)
 url="https://librivox.org/api/feed/audiobooks/?"+urllib.parse.urlencode(params)
 try:
  req=urllib.request.Request(url,headers={"User-Agent":"DarkReader-API-compatibility/0.1","Accept":"application/json"})
  with urllib.request.urlopen(req,timeout=18) as r:
   data=json.loads(r.read(800000))
   books=data.get("books",[])
   result={"case":name,"http_status":r.status,"results":len(books),"first_title":books[0].get("title") if books else None}
   if books and "sections" in books[0]:
    sections=books[0].get("sections") or []
    result["chapters"]=len(sections)
    result["audio_url_present"]=bool(sections and sections[0].get("listen_url"))
    result["cover_present"]=bool(books[0].get("coverart_jpg"))
   print(json.dumps(result,ensure_ascii=False),flush=True)
 except Exception as e:print(json.dumps({"case":name,"error":str(e)},ensure_ascii=False),flush=True)
