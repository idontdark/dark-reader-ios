#!/usr/bin/env python3
"""Bounded live probes. HTTP success is never reported as playback success."""
import concurrent.futures, datetime, hashlib, io, json, pathlib, re, urllib.request, urllib.parse, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/"qa-results"
OUT.mkdir(exist_ok=True)
def get(url, limit=3_000_000, headers=None):
    req=urllib.request.Request(url,headers={"User-Agent":"DarkReader-QA/0.8 (catalog compatibility)",**(headers or {})})
    with urllib.request.urlopen(req, timeout=18) as r:
        data=r.read(limit+1)
        if len(data)>limit: raise ValueError("response exceeds bound")
        return {"status":r.status,"url":r.url,"type":r.headers.get("Content-Type"),"data":data}
def probe(url):
    try:
        r=get(url)
        text=r["data"].decode("utf-8",errors="replace")
        return {"requested":url,"status":r["status"],"url":r["url"],"type":r["type"],"bytes":len(r["data"]),
                "forms":re.findall(r'<form\b[^>]*>',text,re.I)[:8],
                "integration":"Not cleared: no provider agreement or documented playback API verified"}
    except Exception as e:return {"requested":url,"error":str(e)}
sites=["https://akniga.org/","https://knigavuhe.org/","https://audiokniga.one/","https://knigi-audio.ru/","https://uknig.com/","https://zvukbook.com/","https://www.audiobook24.ru/","https://www.digitalbook.io/ru","https://ru.audioreads.org/","https://audio-knigki.ru/"]
report={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"sites":list(concurrent.futures.ThreadPoolExecutor(10).map(probe,sites))}
queries=["Богатый папа, бедный папа","Мастер и Маргарита","Преступление и наказание","Война и мир","Анна Каренина"]
def audio_search(term):
    q='mediatype:audio AND (collection:librivoxaudio OR collection:audio_bookspoetry OR subject:audiobooks) AND ('+" AND ".join('title:'+w+'*' for w in re.findall(r'\w+',term.lower()))+') AND language:(rus OR ru OR Russian)'
    url="https://archive.org/advancedsearch.php?"+urllib.parse.urlencode({"q":q,"output":"json","rows":3,"fl[]":["identifier","title","language"]},doseq=True)
    try:
        r=get(url);d=json.loads(r["data"])["response"]
        return {"query":term,"url":url,"total":d["numFound"],"results":d["docs"],"playback":"not tested"}
    except Exception as e:return {"query":term,"error":str(e)}
report["audio_search"]=list(concurrent.futures.ThreadPoolExecutor(5).map(audio_search,queries))
report["opds"]=[probe(u) for u in ["http://flibusta.is/opds","https://flibusta.is/opds","https://www.gutenberg.org/ebooks/search.opds/?query=Doyle"]]
def ebooks():
    r=get("https://gutendex.com/books/?languages=ru")
    books=json.loads(r["data"])["results"]
    assert books and all("ru" in b["languages"] for b in books)
    result={"status":r["status"],"russian_results":len(books),"downloaded":[]}
    for b in books:
        epub=next((v for k,v in b["formats"].items() if "epub" in k),None)
        if not epub:continue
        r=get(epub,limit=50_000_000)
        with zipfile.ZipFile(io.BytesIO(r["data"])) as z:
            assert z.read("mimetype")==b"application/epub+zip"
            assert z.testzip() is None
        path=OUT/(str(b["id"])+".epub");path.write_bytes(r["data"])
        result["downloaded"].append({"id":b["id"],"title":b["title"],"url":r["url"],"sha256":hashlib.sha256(r["data"]).hexdigest(),"bytes":len(r["data"]),"opened_in_reader":False})
        if len(result["downloaded"])==3:break
    assert result["downloaded"]
    return result
try:report["gutendex"]=ebooks()
except Exception as e:report["gutendex"]={"error":str(e)}
for lang in ["ru","en"]:
    code="rus" if lang=="ru" else "eng"
    url="https://openlibrary.org/search.json?"+urllib.parse.urlencode({"q":"language:"+code+" subject:adventure","lang":lang,"fields":"key,author_name,cover_i,editions,editions.key,editions.title,editions.language,editions.cover_i","limit":4})
    try:
        r=get(url);d=json.loads(r["data"])
        report["discovery_"+lang]={"url":url,"docs":d.get("docs",[])[:4]}
    except Exception as e:report["discovery_"+lang]={"error":str(e)}
(OUT/"live-probes.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(report,ensure_ascii=False,indent=2))
