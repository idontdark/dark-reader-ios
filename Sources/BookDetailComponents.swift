import SwiftUI

struct BookDetailHero:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let title:String
    let author:String
    let coverURL:URL?
    var tags:[String]=[]
    var body:some View {
        HStack(alignment:.top,spacing:15) {
            BookArtwork(title:title,author:author,coverURL:coverURL,width:118,height:178)
            VStack(alignment:.leading,spacing:10) {
                Text(title).font(.system(size:21,weight:.bold)).tracking(-0.4).foregroundStyle(.white).lineLimit(4)
                Text(verbatim:L10n.authorName(author)).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).lineLimit(3)
                if !tags.isEmpty {
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:5) {ForEach(tags.prefix(2),id:\.self) {tag in tagLabel(tag)}}
                        VStack(alignment:.leading,spacing:5) {ForEach(tags.prefix(2),id:\.self) {tag in tagLabel(tag)}}
                    }.padding(.top,4)
                }
                Spacer(minLength:0)
            }.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:160,alignment:.top)
        }
    }
    private func tagLabel(_ value:String)->some View {
        Text(verbatim:L10n.render(value,language:localizationLanguage)).font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal,7).padding(.vertical,4).background(Color.white.opacity(0.07),in:Capsule())
    }
}
struct BookFavoriteButton:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let favorite:Bool
    let action:()->Void
    var body:some View {
        Button(action:action) {
            Label(L10n.render(favorite ? "Удалить из избранного":"Добавить в избранное",language:localizationLanguage),systemImage:favorite ? "star.fill":"star")
                .font(.system(size:13,weight:.medium)).foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth:.infinity).frame(height:42)
                .background(Color.white.opacity(0.018),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.white.opacity(0.23),lineWidth:0.8))
        }.buttonStyle(.plain)
    }
}
enum BookDescription {
    static func catalog(_ book: CatalogBook, language: String) async -> String? {
        let original = clean(book.summary ?? "")
        if !original.isEmpty { return original }
        if let url = book.navigationURL,
           let entries = try? await OPDSClient(searchEndpoint: "", queryParameter: "").browse(url),
           let detailed = entries.first(where: { $0.id == book.id || sameEdition(title:$0.title,author:$0.author,title:book.title,author:book.author) }) {
            let summary = clean(detailed.summary ?? "")
            if !summary.isEmpty { return summary }
        }
        // A description from another service is accepted only after matching both title and author.
        let title = book.title.replacingOccurrences(of:"\\[[^\\]]*\\]",with:"",options:.regularExpression)
        guard !["", "Автор не указан", "Неизвестный автор"].contains(book.author),
              var parts = URLComponents(string:"https://openlibrary.org/search.json") else { return nil }
        parts.queryItems = [URLQueryItem(name:"title",value:title),URLQueryItem(name:"author",value:book.author),
                            URLQueryItem(name:"limit",value:"5"),URLQueryItem(name:"fields",value:"key,title,author_name")]
        guard let url=parts.url else {return nil}
        do {
            let (data,response)=try await URLSession.shared.data(for:URLRequest(url:url,timeoutInterval:8))
            guard (response as? HTTPURLResponse)?.statusCode == 200,data.count<500_000,
                  let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let docs=object["docs"] as? [[String:Any]] else {return nil}
            for doc in docs {
                guard let candidateTitle=doc["title"] as? String,let authors=doc["author_name"] as? [String],
                      authors.contains(where:{sameEdition(title:candidateTitle,author:$0,title:title,author:book.author)}),
                      let key=doc["key"] as? String,key.hasPrefix("/works/") else {continue}
                return await workDescription(key,language:language)
            }
        } catch {}
        return nil
    }
    static func sameEdition(title lhsTitle:String,author lhsAuthor:String,title rhsTitle:String,author rhsAuthor:String)->Bool {
        SearchQueryPolicy.normalized(lhsTitle) == SearchQueryPolicy.normalized(rhsTitle) &&
        Set(SearchQueryPolicy.normalized(lhsAuthor).split(separator:" ")) == Set(SearchQueryPolicy.normalized(rhsAuthor).split(separator:" "))
    }
    static func clean(_ text:String)->String {
        text.replacingOccurrences(of:"(?i)<br\\s*/?>|</p>",with:"\n",options:.regularExpression)
            .replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&amp;",with:"&")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func discovery(_ book:DiscoveryBook,language:String) async ->String? {
        guard book.id.hasPrefix("openlibrary:/works/") else {return nil}
        return await workDescription(String(book.id.dropFirst("openlibrary:".count)),language:language)
    }
    private static func workDescription(_ path:String,language:String) async ->String? {
        guard path.hasPrefix("/works/"),let url=URL(string:"https://openlibrary.org"+path+".json") else{return nil}
        do {
            var request=URLRequest(url:url);request.timeoutInterval=10
            let (data,response)=try await URLSession.shared.data(for:request)
            guard let response=response as? HTTPURLResponse,(200..<300).contains(response.statusCode),data.count<1_000_000,
                  let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{return nil}
            let raw=object["description"] as? String ?? (object["description"] as? [String:Any])?["value"] as? String
            guard let raw else{return nil}
            let text=clean(raw)
            if language == "ru",text.range(of:"[А-Яа-яЁё]",options:.regularExpression) == nil{return nil}
            return text.isEmpty ? nil:text
        } catch{return nil}
    }
}
