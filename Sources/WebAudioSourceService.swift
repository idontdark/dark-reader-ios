import Foundation

/// Public catalog pages only. No JavaScript execution or access-control bypass.
enum WebAudioSourceService {
    static func captures(_ pattern:String,_ text:String)->[[String]] {
        guard let regex=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive,.dotMatchesLineSeparators]) else{return []}
        return regex.matches(in:text,range:NSRange(text.startIndex..<text.endIndex,in:text)).map {m in
            (1..<m.numberOfRanges).map {index in Range(m.range(at:index),in:text).map {String(text[$0])} ?? ""}
        }
    }
    static func first(_ pattern:String,_ text:String)->String? {captures(pattern,text).first?.first}
    static func clean(_ html:String)->String {
        var text=html.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
        for (key,value) in ["&lt;":"<","&gt;":">","&nbsp;":" ","&amp;":"&","&quot;":"\"","&#039;":"'","&#39;":"'","&laquo;":"«","&raquo;":"»","&ndash;":"–","&mdash;":"—"] {text=text.replacingOccurrences(of:key,with:value)}
        return text.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func page(_ url: URL) async throws -> String {
        let response = try await SourceHTTPClient.shared.load(url)
        guard let html = SourceHTTPClient.html(response) else { throw AudioCatalogError.invalidReply }
        return html
    }

    static func search(source:AudioSource,query:String,byAuthor:Bool=false) async throws -> [AudioBook] {
        guard let url=AudioWebCatalog.search(host:source == .knigavuhe ? "knigavuhe.org":"akniga.org",query:query)?.url else {throw AudioCatalogError.invalidSearch}
        var found:[AudioBook]=[];var seen=Set<String>()
        let pages=query.isEmpty ? 1:3
        for number in 1...pages {
            try Task.checkCancellation()
            var parts=URLComponents(url:url,resolvingAgainstBaseURL:false)!
            if number>1 {parts.queryItems=(parts.queryItems ?? [])+[URLQueryItem(name:"page",value:String(number))]}
            guard let pageURL=parts.url else {break}
            let batch:[AudioBook]
            do {batch=parse(try await page(pageURL),source:source)}
            catch {if found.isEmpty {throw error};break}
            if batch.isEmpty {break}
            for book in batch where seen.insert(book.id).inserted {found.append(book)}
        }
        if byAuthor {
            let terms=RecommendationProfile.normalized(query).split(separator:" ").map(String.init)
            return found.filter {book in let name=RecommendationProfile.normalized(book.author);return terms.allSatisfy {name.contains($0)}}
        }
        return found
    }
    static func featured(source:AudioSource,genres:[String],newest:Bool) async throws -> [AudioBook] {
        let knig=["romance":"roman-proza","detective":"detektivy-trillery","thriller":"uzhasy-mistika","fantasy":"fantastika","classics":"klassika","children":"dlja-detejj","history":"istorija","biography":"biografii-memuary","adventure":"prikljuchenija","nonfiction":"nauchno-populjarnoe"]
        let ak=["romance":"roman","detective":"detective","thriller":"uzhasy_mistika","fantasy":"fantasy","classics":"classic","children":"detskie","history":"istoriya","biography":"biography","adventure":"priklucheniya","nonfiction":"nauchno_populyarnye"]
        var parts=URLComponents();parts.scheme="https";parts.host=source == .knigavuhe ? "knigavuhe.org":"akniga.org"
        if let genre=genres.first,let slug=(source == .knigavuhe ? knig:ak)[genre] {
            parts.path=(source == .knigavuhe ? "/genre/":"/section/")+slug+"/"
        } else {parts.path=source == .knigavuhe ? (newest ? "/new/":"/popular/"):(newest ? "/":"/index/top/")}
        guard let url=parts.url else {throw AudioCatalogError.invalidReply}
        return parse(try await page(url),source:source)
    }
    static func parse(_ html:String,source:AudioSource)->[AudioBook] {
        let blocks:[String]
        if source == .knigavuhe {blocks=Array(html.components(separatedBy:"<div class=\"bookkitem\">").dropFirst())}
        else {blocks=Array(html.components(separatedBy:"<div class=\"content__main__articles--item").dropFirst())}
        var seen=Set<String>()
        return blocks.compactMap {block in
            let address:String?
            let title:String?
            let author:String?
            let cover:String?
            if source == .knigavuhe {
                address=first("href=\"(/book/[^\"?#]+)\"",block).map {"https://knigavuhe.org"+$0}
                title=first("<a[^>]*class=\"bookkitem_name\"[^>]*>(.*?)</a>",block).map(clean)
                author=first("<a[^>]*href=\"/author/[^\"]*\"[^>]*>(.*?)</a>",block).map(clean)
                cover=first("<img[^>]*class=\"bookkitem_cover_img\"[^>]*src=\"([^\"]+)\"",block)
                    ?? first("<img[^>]*src=\"([^\"]+)\"",block)
            } else {
                address=first("href=\"(https://akniga\\.org/[^\"]+)\"",block)
                let heading=first("<h2[^>]*>(.*?)</h2>",block).map(clean) ?? ""
                let parts=heading.components(separatedBy:" – ")
                title=parts.count>1 ? parts.dropFirst().joined(separator:" – "):heading
                author=parts.count>1 ? parts[0]:nil
                cover=first("<img[^>]*src=\"([^\"]+)\"",block)
            }
            guard let address,let url=URL(string:clean(address)),let title,!title.isEmpty,seen.insert(address).inserted else{return nil}
            let id=source.rawValue+":"+url.path
            return AudioBook(id:id,source:source,sourceID:url.path,title:title,author:author.flatMap {$0.isEmpty ? nil:$0} ?? "Неизвестный автор",
                             description:source == .knigavuhe ? clean(first("<div class=\"bookkitem_about\">(.*?)</div>",block) ?? ""):"",
                             coverURL:cover.flatMap {URL(string:clean($0))},language:nil,feedURL:url)
        }
    }
    static func chapters(for book:AudioBook) async throws -> [AudioChapter] {
        if book.source == .akniga {return try await aknigaChapters(book)}
        guard book.source == .knigavuhe,let url=book.feedURL else {throw WebAudioError.unavailable}
        return try parseChapters(try await page(url),book:book)
    }
    static func parseChapters(_ html:String,book:AudioBook) throws -> [AudioChapter] {
        guard let range=html.range(of:"new BookPlayer("),let start=html[range.upperBound...].firstIndex(of:"[") else {throw AudioCatalogError.noTracks}
        // Find the complete JSON array; don't split on brackets occurring in strings.
        var depth=0,quoted=false,escaped=false
        var end:String.Index?
        for index in html[start...].indices {
            let ch=html[index]
            if quoted {
                if escaped {escaped=false} else if ch == "\\" {escaped=true} else if ch == "\"" {quoted=false}
            } else if ch == "\"" {quoted=true}
            else if ch == "[" {depth+=1}
            else if ch == "]" {depth-=1;if depth == 0 {end=html.index(after:index);break}}
        }
        guard let end,let data=String(html[start..<end]).data(using:.utf8),
              let list=try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else {throw AudioCatalogError.invalidReply}
        let tracks=list.compactMap {item -> AudioChapter? in
            guard (item["error"] as? Int ?? 0) == 0,let address=item["url"] as? String,let media=URL(string:address),media.scheme == "https",
                  let id=item["id"] as? Int else{return nil}
            return AudioChapter(id:book.id+":\(id)",title:item["title"] as? String ?? book.title,url:media,durationSeconds:item["duration_float"] as? Double ?? item["duration"] as? Double)
        }
        guard !tracks.isEmpty else {throw AudioCatalogError.noTracks}
        return tracks
    }

    /// Use only the site's normal anonymous player flow. A rejected request is
    /// surfaced to the UI with an option to open the original website.
    private static func aknigaChapters(_ book:AudioBook) async throws -> [AudioChapter] {
        guard let url=book.feedURL else {throw WebAudioError.unavailable}
        let html=try await page(url)
        guard let bid=first("book--player[^>]*book-id-(\\d+)",html),
              let csrf=first("LIVESTREET_SECURITY_KEY\\s*=\\s*['\"]([^'\"]+)",html) else {throw WebAudioError.unavailable}
        let token=try await post("player/token",values:["bid":bid,"ts":String(Int64(Date().timeIntervalSince1970*1000)),"security_ls_key":csrf],referer:url)
        guard let value=token["token"] as? String else {throw WebAudioError.unavailable}
        let result=try await post("b/"+bid,values:["bid":bid,"token":value,"hls":"false","security_ls_key":csrf],referer:url)
        guard result["preview_url"] == nil else {throw WebAudioError.unavailable}
        let list:[[String:Any]]
        if let encoded=result["items"] as? String,let data=encoded.data(using:.utf8) {
            list=(try JSONSerialization.jsonObject(with:data)) as? [[String:Any]] ?? []
        } else {list=result["items"] as? [[String:Any]] ?? []}
        let tracks=list.enumerated().compactMap {index,item -> AudioChapter? in
            guard let address=(item["url"] ?? item["file"]) as? String,let media=URL(string:address),media.scheme == "https",
                  ["mp3","m4a","m4b"].contains(media.pathExtension.lowercased()) else{return nil}
            return AudioChapter(id:book.id+":\(index)",title:item["title"] as? String ?? book.title,url:media,durationSeconds:item["time"] as? Double)
        }
        guard !tracks.isEmpty else {throw WebAudioError.unavailable}
        return tracks
    }
    private static func post(_ path:String,values:[String:String],referer:URL) async throws -> [String:Any] {
        let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body=values.sorted {$0.key<$1.key}.map {key,value in
            (key.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")+"="+(value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")
        }.joined(separator:"&")
        var request=URLRequest(url:URL(string:"https://akniga.org/ajax/"+path)!);request.httpMethod="POST";request.httpBody=Data(body.utf8);request.timeoutInterval=25
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",forHTTPHeaderField:"Content-Type")
        request.setValue("XMLHttpRequest",forHTTPHeaderField:"X-Requested-With")
        request.setValue(referer.absoluteString,forHTTPHeaderField:"Referer")
        request.setValue("https://akniga.org",forHTTPHeaderField:"Origin")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",forHTTPHeaderField:"User-Agent")
        let response = try await SourceHTTPClient.shared.load(request, cached: false)
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw WebAudioError.unavailable }
        return json
    }
}

enum WebAudioError:LocalizedError {
    case unavailable
    var errorDescription:String? {L10n.text("Источник не предоставил аудиофайлы приложению. Откройте книгу на сайте.")}
}
