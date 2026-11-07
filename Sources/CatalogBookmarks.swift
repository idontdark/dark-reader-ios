import Foundation

enum CatalogBookmarks {
    static let wishlistKey="catalog.wishlistJSON"
    static let favoritesKey="catalog.favoritesJSON"
    static func decode(_ raw:String)->[CatalogBook] {
        raw.data(using:.utf8).flatMap { try? JSONDecoder().decode([CatalogBook].self,from:$0) } ?? []
    }
    static func encode(_ books:[CatalogBook])->String {
        (try? JSONEncoder().encode(books)).map { String(decoding:$0,as:UTF8.self) } ?? "[]"
    }
    static func toggle(_ book:CatalogBook,key:String) {
        var books=decode(UserDefaults.standard.string(forKey:key) ?? "[]")
        if books.contains(where:{$0.id == book.id}) { books.removeAll {$0.id == book.id} }
        else {
            books.insert(book,at:0)
            RecommendationProfile.record(title:book.title,author:book.author,weight:key == favoritesKey ? 4:1)
        }
        UserDefaults.standard.set(encode(books),forKey:key)
    }
    static func downloaded(_ book:CatalogBook) {
        let books=decode(UserDefaults.standard.string(forKey:wishlistKey) ?? "[]").filter {$0.id != book.id}
        UserDefaults.standard.set(encode(books),forKey:wishlistKey)
    }
}
