#!/usr/bin/env python3
"""Bounded live probes. HTTP success is never reported as playback success."""
import concurrent.futures, datetime, hashlib, io, json, pathlib, re, urllib.request, urllib.parse, zipfile, xml.etree.ElementTree as ET
from html.parser import HTMLParser
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
class SearchForm(HTMLParser):
    def __init__(self):
        super().__init__();self.forms=[];self.current=None
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=="form":self.current={"attrs":attrs,"fields":{}}
        if tag=="input" and self.current is not None and attrs.get("name"):
            self.current["fields"][attrs["name"]]=attrs.get("value","")
    def handle_endtag(self,tag):
        if tag=="form" and self.current is not None:
            self.forms.append(self.current);self.current=None
def website_search(args):
    site,term=args
    try:
        r=get(site);parser=SearchForm();parser.feed(r["data"].decode("utf-8",errors="replace"))
        names=["q","query","s","story","search"]
        chosen=next((f for f in parser.forms if f["attrs"].get("method","get").lower()=="get" and any(n in f["fields"] for n in names)),None)
        if chosen is None:return {"site":site,"query":term,"result":"No public GET search form found"}
        fields=chosen["fields"].copy();name=next(n for n in names if n in fields)
        fields[name]=term
        action=urllib.parse.urljoin(site,chosen["attrs"].get("action",""))
        url=action+("?" if "?" not in action else "&")+urllib.parse.urlencode(fields)
        r=get(url);html=r["data"].decode("utf-8",errors="replace")
        title=re.search(r"<title[^>]*>(.*?)</title>",html,re.I|re.S)
        return {"site":site,"query":term,"url":r["url"],"status":r["status"],"bytes":len(r["data"]),
                "page_title":re.sub("<[^>]+>","",title[1]).strip() if title else "",
                "note":"Search page fetched; title echo alone is not a confirmed book match, stream, or integration permission"}
    except Exception as e:return {"site":site,"query":term,"error":str(e)}
report["website_search"]=list(concurrent.futures.ThreadPoolExecutor(10).map(website_search,
    [(s,q) for s in [sites[0],sites[1],sites[2],sites[4],sites[8]] for q in ["Богатый папа","Толстой"]]))
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
def opds_download():
    ns={"a":"http://www.w3.org/2005/Atom"}
    url="http://flibusta.is/opds/search?"+urllib.parse.urlencode({"searchType":"books","searchTerm":"Преступление и наказание"})
    feed=get(url);root=ET.fromstring(feed["data"]);rows=[]
    for entry in root.findall(".//a:entry",ns)[:8]:
        links=entry.findall("a:link",ns)
        if not any("acquisition" in l.get("rel","") for l in links):
            nav=next((l for l in links if "atom+xml" in l.get("type","")),None)
            if nav is not None:
                page=get(urllib.parse.urljoin(feed["url"],nav.get("href","")));nested=ET.fromstring(page["data"])
                entry=nested.find(".//a:entry",ns) if nested.tag.endswith("feed") else nested
                if entry is None:continue
                links=entry.findall("a:link",ns)
        for link in links:
            mime=link.get("type","").lower();rel=link.get("rel","")
            if "acquisition" not in rel or any(x in rel for x in ["/buy","/borrow","/sample"]):continue
            if not any(x in mime for x in ["epub","fb2","fictionbook"]):continue
            target=urllib.parse.urljoin(feed["url"],link.get("href",""));r=get(target,50_000_000)
            data=r["data"];kind=None
            if data.startswith(b"PK"):
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    assert z.testzip() is None
                    if "mimetype" in z.namelist() and z.read("mimetype")==b"application/epub+zip":kind="epub"
                    else:
                        fb2=next((n for n in z.namelist() if n.lower().endswith(".fb2")),None)
                        if fb2:ET.fromstring(z.read(fb2));kind="fb2.zip"
            else:
                xml=ET.fromstring(data)
                if xml.tag.endswith("FictionBook"):kind="fb2"
            if not kind:raise ValueError("Acquisition is not EPUB or FB2")
            path=OUT/("opds-"+str(len(rows))+"."+kind);path.write_bytes(data)
            rows.append({"title":entry.findtext("a:title",default="",namespaces=ns),"url":r["url"],"format":kind,
                         "bytes":len(data),"sha256":hashlib.sha256(data).hexdigest(),"opened_in_reader":False})
            if len(rows)>=2:return rows
    return rows
try:report["opds_downloads"]=opds_download()
except Exception as e:report["opds_downloads"]={"error":str(e)}
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
