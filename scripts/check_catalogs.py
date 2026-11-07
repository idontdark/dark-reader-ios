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
