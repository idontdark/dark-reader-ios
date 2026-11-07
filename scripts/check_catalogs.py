#!/usr/bin/env python3
"""One-shot live catalog compatibility checks (stdlib only). No books are stored."""
import json
import urllib.request
import urllib.parse
import urllib.error
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

checks = [
    ("Flibusta primary OPDS root", "https://flibusta.is/opds", "xml"),
    ("Flibusta primary title search", "https://flibusta.is/opds/search?searchTerm=" + urllib.parse.quote("Толстой"), "xml"),
    ("Flibusta mirror search", "https://flub.flibusta.is/opds/search?searchTerm=" + urllib.parse.quote("Толстой"), "xml"),
    ("Project Gutenberg OPDS root", "https://www.gutenberg.org/ebooks/search.opds/", "xml"),
    ("Project Gutenberg OPDS query", "https://www.gutenberg.org/ebooks/search.opds/?query=austen", "xml"),
    ("Gutendex author search", "https://gutendex.com/books/?search=austen", "json"),
    ("Gutendex title search", "https://gutendex.com/books/?search=pride", "json"),
    ("Open Library metadata search", "https://openlibrary.org/search.json?title=War%20and%20Peace&limit=1", "json"),
]
out = []
for name, url, kind in checks:
    result = {"name": name, "url": url, "ok": False}
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "DarkReader-API-compatibility-check/0.1 (GitHub Actions; one request)",
            "Accept": "application/atom+xml,application/xml,application/json;q=0.9,*/*;q=0.5",
        })
        with urllib.request.urlopen(req, timeout=15) as response:
            body = response.read(1100000)
            result["status"] = response.status
            result["final_url"] = response.url
            result["content_type"] = response.headers.get("content-type", "")
        result["bytes_read"] = len(body)
        if kind == "json":
            parsed = json.loads(body)
            books = parsed.get("results", parsed.get("docs", []))
            result["records"] = len(books)
            result["epub_links"] = sum(
                1 for b in books if any("epub" in key and str(value).startswith("https://")
                    for key, value in b.get("formats", {}).items())
            )
            result["ok"] = isinstance(books, list) and result["status"] == 200
        else:
            root = ET.fromstring(body)
            atom_ns = "{http://www.w3.org/2005/Atom}"
            entries = root.findall(f".//{atom_ns}entry")
            result["root"] = root.tag
            result["entries"] = len(entries)
            result["epub_links"] = sum(
                1 for e in entries for a in e.findall(f"{atom_ns}link")
                if "acquisition" in a.attrib.get("rel", "") and "epub+zip" in a.attrib.get("type", "")
            )
            links = root.findall(f"{atom_ns}link")
            result["search_templates"] = [
                a.attrib.get("href") for a in links if "search" in a.attrib.get("rel", "")
            ][:3]
            result["ok"] = "feed" in root.tag.lower() and result["status"] == 200
    except Exception as e:
        result["error"] = (type(e).__name__ + ": " + str(e))[:280]
    out.append(result)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)

report = {"checked_at": datetime.now(timezone.utc).isoformat(), "checks": out}
with open("catalog-check.json", "w", encoding="utf-8") as file:
    json.dump(report, file, ensure_ascii=False, indent=2)
print("Completed checks:", len(out), flush=True)

# Diagnostic-only exploration of the OPDS navigation layer and EPUB links.
for r in out:
    if not (r["name"].startswith("Flibusta primary title") or r["name"].startswith("Project Gutenberg OPDS query")):
        continue
    try:
        with urllib.request.urlopen(urllib.request.Request(r["url"], headers={"User-Agent": "DarkReader-Test/0.1", "Accept": "application/atom+xml"}), timeout=12) as response:
            feed = ET.fromstring(response.read(2000000))
        atom_ns = "{http://www.w3.org/2005/Atom}"
        entries = feed.findall(f"{atom_ns}entry")
        details = []
        links_to_visit = []
        for entry in entries[:4]:
            title = (entry.findtext(f"{atom_ns}title") or "")[:90]
            links = []
            for link in entry.findall(f"{atom_ns}link"):
                href = urllib.parse.urljoin(r["url"], link.attrib.get("href", ""))
                relation = link.attrib.get("rel", "")
                mime = link.attrib.get("type", "")
                links.append({"href": href[:210], "rel": relation, "type": mime})
                if ("atom+xml" in mime or "/opds/" in href) and "searchTerms" not in href and href.startswith("https://"):
                    links_to_visit.append(href)
            details.append({"title": title, "links": links[:6]})
        print("OPDS-EXPLORE:", json.dumps({"name": r["name"], "entries": details}, ensure_ascii=False), flush=True)
        for follow in list(dict.fromkeys(links_to_visit))[:2]:
            try:
                with urllib.request.urlopen(urllib.request.Request(follow, headers={"User-Agent":"DarkReader-Test/0.1","Accept":"application/atom+xml"}), timeout=12) as response:
                    nested = ET.fromstring(response.read(1200000))
                    code = response.status
                samples=[]
                for e in nested.findall(f"{atom_ns}entry")[:2]:
                    samples.append({
                        "title":(e.findtext(f"{atom_ns}title") or "")[:100],
                        "links":[{
                            "rel":l.attrib.get("rel",""),
                            "type":l.attrib.get("type",""),
                            "href":urllib.parse.urljoin(follow,l.attrib.get("href",""))[:190]
                        } for l in e.findall(f"{atom_ns}link")[:5]]
                    })
                print("OPDS-FOLLOW:", json.dumps({"url":follow,"status":code,"entry_count":len(nested.findall(f"{atom_ns}entry")),"entries":samples}, ensure_ascii=False),flush=True)
            except Exception as e:
                print("OPDS-FOLLOW-ERROR:", str(e), follow, flush=True)
    except Exception as e:
        print("OPDS-EXPLORE-ERROR:", r["name"], str(e), flush=True)

# Test direct book-search results instead of navigating the search menu.
for term in ["Дубровский", "Капитанская дочка", "война и мир"]:
    params=urllib.parse.urlencode({"searchType":"books","searchTerm":term})
    url="https://flibusta.is/opds/search?" + params
    try:
        req=urllib.request.Request(url,headers={"User-Agent":"DarkReader-Test/0.1","Accept":"application/atom+xml"})
        with urllib.request.urlopen(req,timeout=12) as reply:
            feed=ET.fromstring(reply.read(1800000))
        ns="{http://www.w3.org/2005/Atom}"
        entries=feed.findall(f"{ns}entry")
        booklinks=[]
        for e in entries:
            title=e.findtext(f"{ns}title") or ""
            for l in e.findall(f"{ns}link"):
                mime=l.attrib.get("type","")
                if "epub" in mime or "fb2" in mime:
                    booklinks.append({"book":title[:85],"type":mime,"rel":l.attrib.get("rel",""),"url":urllib.parse.urljoin(url,l.attrib.get("href",""))})
        print("FLIBUSTA-BOOKS:",json.dumps({"term":term,"status":200,"entries":len(entries),"epub_or_fb2_links":len(booklinks),"samples":booklinks[:4]},ensure_ascii=False),flush=True)
        if booklinks:
            # Only read the first four bytes; never download a whole third-party book.
            epub=next((link for link in booklinks if "epub" in link["type"]),None)
            if epub and epub["url"].startswith("https://"):
                try:
                    request=urllib.request.Request(epub["url"],headers={"User-Agent":"DarkReader-Test/0.1","Range":"bytes=0-3"})
                    with urllib.request.urlopen(request,timeout=12) as response:
                        header=response.read(4)
                        print("FLIBUSTA-DOWNLOAD:",json.dumps({"status":response.status,"content_type":response.headers.get("content-type"),"zip_header":header.startswith(b"PK"),"final_url":response.url},ensure_ascii=False),flush=True)
                except Exception as err:
                    print("FLIBUSTA-DOWNLOAD-ERROR:",str(err),flush=True)
            break
    except Exception as err:
        print("FLIBUSTA-BOOKS-ERROR:",str(err),term,flush=True)

# Verify a real Gutendex EPUB acquisition URL and Gutenberg's per-book OPDS.
try:
    with urllib.request.urlopen("https://gutendex.com/books/?search=pride",timeout=15) as response:
        books=json.load(response).get("results",[])
    candidate=next((v for b in books for k,v in b.get("formats",{}).items() if "epub" in k and v.startswith("https://")),None)
    print("GUTENDEX-LINK:",json.dumps({"result_count":len(books),"first_epub_url":candidate},ensure_ascii=False),flush=True)
    if candidate:
        try:
            req=urllib.request.Request(candidate,headers={"Range":"bytes=0-3","User-Agent":"DarkReader-Test/0.1"})
            with urllib.request.urlopen(req,timeout=15) as response:
                first=response.read(4)
                print("GUTENDEX-DOWNLOAD:",json.dumps({"status":response.status,"zip_header":first.startswith(b"PK"),"content_type":response.headers.get("content-type"),"url":response.url},ensure_ascii=False),flush=True)
        except Exception as e:
            print("GUTENDEX-DOWNLOAD-ERROR:",str(e),flush=True)
except Exception as e:
    print("GUTENDEX-LINK-ERROR:",str(e),flush=True)

try:
    with urllib.request.urlopen("https://www.gutenberg.org/ebooks/1342.opds",timeout=15) as response:
        root=ET.fromstring(response.read(1000000))
        ns="{http://www.w3.org/2005/Atom}"
        links=[{"rel":l.attrib.get("rel"),"type":l.attrib.get("type"),"href":l.attrib.get("href")} for l in root.findall(f".//{ns}link")]
        print("GUTENBERG-BOOK-OPDS:",json.dumps({"status":response.status,"root":root.tag,"epub_links":[l for l in links if "epub" in str(l["type"]).lower()][:3],"total_links":len(links)},ensure_ascii=False),flush=True)
except Exception as e:
    print("GUTENBERG-BOOK-OPDS-ERROR:",str(e),flush=True)
