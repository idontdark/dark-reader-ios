#!/usr/bin/env python3
"""A range-enabled, throttled EPUB endpoint for native pause/restart tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io,json,time,zipfile
buffer=io.BytesIO()
with zipfile.ZipFile(buffer,"w",compression=zipfile.ZIP_STORED) as z:
    z.writestr("mimetype","application/epub+zip")
    z.writestr("META-INF/container.xml",'<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr("book.opf",'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">qa</dc:identifier><dc:title>QA</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-11-07T00:00:00Z</meta></metadata><manifest><item id="text" href="text.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="text"/></spine></package>')
    z.writestr("text.xhtml",'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>QA</title></head><body><p>Resume fixture.</p></body></html>')
    z.writestr("nav.xhtml",'<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>QA</title></head><body><nav epub:type="toc"><ol><li><a href="text.xhtml">Chapter</a></li></ol></nav></body></html>')
    z.writestr("padding.bin",bytes(4_000_000))
DATA=buffer.getvalue()
STATS={"ranges":[],"requests":0}
class Handler(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def do_GET(self):
        if self.path=="/stats":
            data=json.dumps(STATS).encode();self.send_response(200);self.send_header("Content-Length",len(data));self.end_headers();self.wfile.write(data);return
        STATS["requests"]+=1
        start=0
        if self.headers.get("Range"):
            start=int(self.headers["Range"].split("=")[1].split("-")[0]);STATS["ranges"].append(start)
        self.send_response(206 if start else 200)
        self.send_header("Content-Type","application/epub+zip")
        self.send_header("Content-Length",len(DATA)-start)
        self.send_header("Accept-Ranges","bytes")
        self.send_header("ETag",'"dark-reader-qa-080"')
        self.send_header("Last-Modified","Fri, 06 Nov 2026 00:00:00 GMT")
        if start:self.send_header("Content-Range",f"bytes {start}-{len(DATA)-1}/{len(DATA)}")
        self.end_headers()
        try:
            for offset in range(start,len(DATA),32768):
                self.wfile.write(DATA[offset:offset+32768]);self.wfile.flush();time.sleep(.04)
        except (BrokenPipeError,ConnectionResetError):pass
    def log_message(self,*args):pass
ThreadingHTTPServer(("127.0.0.1",8765),Handler).serve_forever()
