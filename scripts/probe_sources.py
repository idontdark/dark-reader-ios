#!/usr/bin/env python3
"""Independent public audiobook service probes, intentionally bounded and read-only."""
import json, sys, time, urllib.error, urllib.parse, urllib.request, xml.etree.ElementTree as ET

HEADERS={"User-Agent":"DarkReader-QA/0.7 (public API compatibility)","Accept":"application/json, application/xml, application/rss+xml, */*"}
def load(url, timeout=18, limit=2_000_000):
    req=urllib.request.Request(url,headers=HEADERS)
    with urllib.request.urlopen(req,timeout=timeout) as r:
        data=r.read(limit+1)
        if len(data)>limit: raise ValueError("response too large")
        return r.status,r.headers.get("Content-Type",""),data
def json_url(url):
    status,ct,data=load(url)
    value=json.loads(data)
    return status,value
def status(name, fn):
    try:
        result=fn()
        report[name]={"status":"ok","details":str(result)[:450]}
    except Exception as exc:
        report[name]={"status":"unavailable","details":f"{type(exc).__name__}: {str(exc)[:220]}"}
    print(f"{name}: {report[name]['status']}: {report[name]['details']}",flush=True)

report={}
# 1. LibriVox. Search realistic author/title, then obtain actual tracks.
def librivox():
    u="https://librivox.org/api/feed/audiobooks/?"+urllib.parse.urlencode({"title":"Sherlock","format":"json","limit":5,"coverart":"1"})
    _, d=json_url(u)
    books=d.get("books",[])
    assert books and any("sherlock" in x.get("title","").lower() for x in books), "title search yielded no Sherlock books"
    b=books[0]
    _,t=json_url("https://librivox.org/api/feed/audiotracks/?"+urllib.parse.urlencode({"project_id":str(b["id"]),"format":"json"}))
    tracks=t.get("sections",[])
    assert any(x.get("listen_url","").startswith("http") for x in tracks), "no track URLs"
    return f"{len(books)} matches; {len(tracks)} tracks; {b['title'][:60]}"
status("LibriVox title search + tracks",librivox)
# 2. Internet Archive. Query title or subject in audio-book poetry, incl librivox as fallback, inspect an item file.
def internet_archive():
    q='mediatype:audio AND (title:sherlock OR subject:sherlock) AND (collection:audio_bookspoetry OR collection:librivoxaudio)'
    u="https://archive.org/advancedsearch.php?"+urllib.parse.urlencode({"q":q,"fl[]":["identifier","title"],"rows":15,"page":1,"output":"json"},doseq=True)
    _,d=json_url(u)
    docs=d.get("response",{}).get("docs",[])
    assert docs,"no titles in live search"
    tested=0
    for x in docs[:5]:
        item=x["identifier"]
        _,metadata=json_url("https://archive.org/metadata/"+urllib.parse.quote(item))
        mp3=[f for f in metadata.get("files",[]) if f.get("name","").lower().endswith((".mp3",".m4b"))]
        tested+=1
        if mp3:return f"{len(docs)} matches; {len(mp3)} audio files in {item}"
    raise ValueError(f"no mp3/m4b in {tested} archive search results")
status("Internet Archive title search + metadata",internet_archive)
# 3. AudiobookDB. Metadata-only. Never install without written third-party agreement.
def audiobookdb():
    s,ct,b=load("https://audiobookdb.org/api/books?take=2",timeout=15)
    d=json.loads(b)
    return f"HTTP {s}; JSON {str(d)[:120]}; requires integration agreement"
status("AudiobookDB metadata only (license restricted)",audiobookdb)
# 4. Storynory. Podcast RSS is audio but content rights can restrict republishing.
def storynory():
    s,ct,b=load("https://www.storynory.com/feed/",timeout=18)
    root=ET.fromstring(b)
    enclosures=[x.attrib.get("url") for x in root.findall(".//enclosure") if x.attrib.get("url")]
    if not enclosures:raise ValueError("feed has no audio enclosures")
    return f"HTTP {s}; {len(enclosures)} enclosure URLs (rights not cleared)"
status("Storynory RSS (rights not cleared)",storynory)
# 5. LoyalBooks public feed, nonstandard endpoint.
def loyalbooks():
    s,ct,b=load("https://www.loyalbooks.com/rss",timeout=18)
    root=ET.fromstring(b)
    ens=root.findall(".//enclosure")
    if not ens:raise ValueError("no RSS audio enclosures")
    return f"HTTP {s}; {len(ens)} audio enclosures"
status("LoyalBooks RSS",loyalbooks)
# 6. DigitalBook, discovery platform, no stable official API documented.
def digitalbook():
    s,ct,b=load("https://www.digitalbook.io/",timeout=18)
    return f"HTTP {s}; HTML homepage, no documented stable JSON audio API"
status("Digitalbook.io metadata availability",digitalbook)
# 7. Test a metadata recommendation service with cover URLs and language/genre topic.
def gutendex():
    url="https://gutendex.com/books/?"+urllib.parse.urlencode({"topic":"science fiction","languages":"en"})
    _,d=json_url(url)
    books=[x for x in d.get("results",[]) if any("epub" in k for k in x.get("formats",{}))]
    assert books,"no EPUB in genre"
    covered=[x for x in books if any("image" in k for k in x.get("formats",{}))]
    return f"{len(books)} books with EPUB, {len(covered)} with cover image formats"
status("Gutendex genre + EPUB + covers",gutendex)
# 8. Open Library subject discovery (reference-only, not a download source).
def openlibrary():
    _,d=json_url("https://openlibrary.org/subjects/science_fiction.json?limit=10")
    works=d.get("works",[])
    assert works,"no subject works"
    covers=[x for x in works if x.get("cover_id")]
    return f"{len(works)} genre works; {len(covers)} cover ids"
status("Open Library subjects + covers",openlibrary)
print("REPORT_JSON="+json.dumps(report,ensure_ascii=False))
mandatory=["LibriVox title search + tracks","Internet Archive title search + metadata"]
if not all(report[k]["status"]=="ok" for k in mandatory):
    sys.exit("Required playable catalog searches failed")
