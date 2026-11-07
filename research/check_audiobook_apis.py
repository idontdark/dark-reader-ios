#!/usr/bin/env python3
"""Live public audiobook API health probe. Metadata and only 32 media bytes.
This research script does not ship in the app and avoids bulk downloading."""
import json, time, urllib.request, urllib.parse, urllib.error, xml.etree.ElementTree as ET
from datetime import datetime, timezone

USER_AGENT="DarkReaderResearch/0.1 (GitHub Actions; short API interoperability check)"
results=[]

def probe(name,url,parse=None,timeout=24,media=False):
    report={"provider":name,"endpoint":url,"ok":False}
    started=time.monotonic()
    try:
        headers={"User-Agent":USER_AGENT,"Accept":"application/json,application/atom+xml,application/xml,*/*;q=0.3"}
        if media:
            headers["Range"]="bytes=0-31"
        req=urllib.request.Request(url,headers=headers)
        with urllib.request.urlopen(req,timeout=timeout) as response:
            body=response.read(32 if media else 1600000)
            report.update(status=response.status,content_type=response.headers.get("Content-Type",""),
                          final_url=response.url,read_bytes=len(body))
        report["latency_ms"]=int((time.monotonic()-started)*1000)
        if media:
            report["magic"]=body[:12].hex()
            report["ok"]=(report["status"] in (200,206)) and len(body)>=3 and (
                body.startswith(b"ID3") or (body[0]==255 and body[1]&224==224)
                or body.startswith(b"OggS") or body.startswith(b"fLaC")
                or b"audio" in report["content_type"].encode().lower()
            )
        elif parse=="json":
            decoded=json.loads(body)
            report["json_type"]=type(decoded).__name__
            report["top_keys"]=list(decoded)[:12] if isinstance(decoded,dict) else []
            report["ok"]=report["status"]==200
            return report,decoded
        elif parse=="rss":
            root=ET.fromstring(body)
            report["xml_root"]=root.tag
            report["ok"]=report["status"]==200
        else:
            report["ok"]=report["status"]==200
    except Exception as exc:
        report["error"]=type(exc).__name__+": "+str(exc)[:170]
        report["latency_ms"]=int((time.monotonic()-started)*1000)
    return report,None

# A single small LibriVox query covers book search + chapter/ZIP metadata.
url="https://librivox.org/api/feed/audiobooks/?title=Sherlock&format=json&limit=2&extended=1&coverart=1"
book_report,book_json=probe("LibriVox title search",url,parse="json")
lvbook=None
if isinstance(book_json,dict):
    entries=book_json.get("books",[])
    book_report["results"]=len(entries)
    if entries:
        lvbook=entries[0]
        book_report["sample_title"]=lvbook.get("title")
        book_report["sample_language"]=lvbook.get("language")
        book_report["sample_project_id"]=lvbook.get("id")
        book_report["chapters_in_extended"]=len(lvbook.get("sections") or [])
        book_report["zip_declared"]=bool(lvbook.get("url_zip_file"))
        book_report["cover_declared"]=bool(lvbook.get("coverart_jpg"))
results.append(book_report)
print(json.dumps(book_report,ensure_ascii=False),flush=True)
if lvbook and lvbook.get("id"):
    time.sleep(3) # LibriVox requests spaced to respect shared volunteer API
    t_report,t_json=probe("LibriVox chapters","https://librivox.org/api/feed/audiotracks/?project_id="+str(lvbook["id"])+"&format=json",parse="json")
    if isinstance(t_json,dict):
        tracks=t_json.get("tracks",t_json.get("audiotracks",[]))
        t_report["tracks"]=len(tracks) if isinstance(tracks,list) else 0
        t_report["audio_link_declared"]=any(bool(t.get("listen_url") or t.get("url")) for t in tracks) if isinstance(tracks,list) else False
    results.append(t_report)
    print(json.dumps(t_report,ensure_ascii=False),flush=True)

q=urllib.parse.urlencode({"q":"collection:librivoxaudio AND mediatype:audio","rows":"2","page":"1","output":"json"})
url="https://archive.org/advancedsearch.php?"+q+"&fl%5B%5D=identifier&fl%5B%5D=title"
ar_report,archive_json=probe("Internet Archive advanced search",url,parse="json")
archive_id=None
if isinstance(archive_json,dict):
    docs=archive_json.get("response",{}).get("docs",[])
    ar_report["matches"]=archive_json.get("response",{}).get("numFound")
    ar_report["samples"]=len(docs)
    if docs: archive_id=docs[0].get("identifier")
results.append(ar_report)
print(json.dumps(ar_report,ensure_ascii=False),flush=True)

if archive_id:
    md_report,md_json=probe("Internet Archive metadata","https://archive.org/metadata/"+urllib.parse.quote(archive_id,safe=""),parse="json")
    if isinstance(md_json,dict):
        audio=[f for f in md_json.get("files",[]) if f.get("name","").lower().endswith((".mp3",".ogg",".m4b"))]
        md_report["audio_tracks"]=len(audio)
        md_report["licenseurl"]=md_json.get("metadata",{}).get("licenseurl")
        md_report["public_domain_flag"]=md_json.get("metadata",{}).get("licenseurl","").lower().find("publicdomain")>=0
        if audio:
            file_name=audio[0]["name"]
            audio_url=("https://archive.org/download/"+urllib.parse.quote(archive_id,safe="")+"/"
                        +urllib.parse.quote(file_name,safe="/"))
            media_report,_=probe("Internet Archive audio GET 32 bytes",audio_url,media=True)
            results.append(media_report)
            print(json.dumps(media_report,ensure_ascii=False),flush=True)
    results.append(md_report)
    print(json.dumps(md_report,ensure_ascii=False),flush=True)

for name,url,mode in [
    ("Gutenberg audiobook OPDS metadata","https://www.gutenberg.org/ebooks/search.opds/?query=audiobook","rss"),
    ("Lit2Go catalog site (no supported API advertised)","https://etc.usf.edu/lit2go/","html")
]:
    entry,_=probe(name,url,parse=mode)
    results.append(entry)
    print(json.dumps(entry,ensure_ascii=False),flush=True)

with open("audiobook-api-test-results.json","w",encoding="utf-8") as file:
    json.dump({"checked_at":datetime.now(timezone.utc).isoformat(),"results":results},
              file,ensure_ascii=False,indent=2)

print("CHECKS_FINISHED",len(results),"SUCCESS",sum(x["ok"] for x in results),flush=True)
