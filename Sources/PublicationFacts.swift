import SwiftUI

struct PublicationFacts: View {
    var language: String?
    var date: String?
    var series: String?
    var number: Double?
    private var languageName: String {
        guard let language else { return L10n.text("Язык не указан источником") }
        guard let code = GenreTaxonomy.language(language) else { return language }
        let locale = Locale(identifier: L10n.language)
        return (locale.localizedString(forLanguageCode: code) ?? language).capitalized(with: locale)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(languageName, systemImage: "globe")
            if let year = PublicationDate.year(date) { Label(String(year), systemImage: "calendar") }
            if let series, !series.isEmpty {
                Label(series + (number.map { " · " + String(format: "%g", $0) } ?? ""), systemImage: "books.vertical")
            }
        }.font(.caption).foregroundStyle(ReaderStyle.secondary)
    }
}
