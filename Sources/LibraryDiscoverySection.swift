import SwiftUI

struct LibraryDiscoverySection: View {
    let audio: Bool
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAudioGenresJSON") private var audioGenresJSON = ""
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: L10n.text("Откройте новое", language: language))
                .font(.title3.weight(.bold)).foregroundStyle(.white)
            ReaderInsetGroup {
                NavigationLink {
                    if audio {
                        AudioCollectionScreen(title: "Для вас", genres: RecommendationProfile.genres(ReaderPreferences.array(audioGenresJSON.isEmpty ? genresJSON : audioGenresJSON), kind: .audio), personalized: true)
                    } else {
                        DiscoveryCollectionScreen(title: "Для вас", genres: RecommendationProfile.genres(ReaderPreferences.array(genresJSON)), personalized: true)
                    }
                } label: { row("Для вас", icon: "sparkles") }
                ReaderDivider()
                NavigationLink {
                    if audio { AudioCollectionScreen(title: "Популярное") }
                    else { DiscoveryCollectionScreen(title: "Популярное", genres: [], sort: "readinglog") }
                } label: { row("Популярное", icon: "flame") }
                ReaderDivider()
                NavigationLink {
                    if audio { AudioCollectionScreen(title: "Новинки", newest: true) }
                    else { DiscoveryCollectionScreen(title: "Новинки", genres: [], sort: "new") }
                } label: { row("Новинки", icon: "sparkle") }
                ReaderDivider()
                NavigationLink { CatalogGenresScreen(audio: audio) } label: { row("Жанры", icon: "square.stack.3d.up") }
            }.buttonStyle(.plain)

        }
    }

    private func row(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 23).foregroundStyle(Color(hex: accentHex).shade(0.25))
            Text(verbatim: L10n.text(title, language: language)).font(.subheadline.weight(.medium))
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(ReaderStyle.secondary)
        }.foregroundStyle(.white).frame(minHeight: 44).padding(.vertical, 2).contentShape(Rectangle())
    }

}
