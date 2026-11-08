import SwiftUI

struct LibraryDiscoverySection: View {
    let audio: Bool
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("catalogProvider") private var provider = "flibusta"
    @AppStorage("preferredAudioSource") private var audioSource: AudioSource = .archive
    @AppStorage("disabledAudioSources") private var disabledSources = ""
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: L10n.text("Откройте новое", language: language))
                .font(.title3.weight(.bold)).foregroundStyle(.white)
            ReaderInsetGroup {
                NavigationLink {
                    if audio {
                        AudioCollectionScreen(title: "Для вас", genres: RecommendationProfile.genres(ReaderPreferences.array(genresJSON)), personalized: true)
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
            HStack(spacing: 10) {
                if audio {
                    source("LibriVox", icon: "headphones") { openAudio(.librivox) }
                    source("Internet Archive", icon: "waveform") { openAudio(.archive) }
                } else {
                    source("Флибуста", icon: "sailboat") { openBooks("flibusta") }
                    source("Project Gutenberg", icon: "building.columns") { openBooks("gutendex") }
                }
            }
            if audio {
                HStack(spacing:10) {
                    source("Книга в ухе",icon:"headphones") {openAudio(.knigavuhe)}
                    source("Аудиокниги Клуб",icon:"headphones") {openAudio(.akniga)}
                }
            }
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

    private func source(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(Color(hex: accentHex).shade(0.25))
                Text(verbatim: L10n.text(title, language: language)).font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(ReaderStyle.secondary)
            }.foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ReaderStyle.cardGradient, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ReaderStyle.line, lineWidth: 0.8))
        }.buttonStyle(.plain)
    }

    private func openBooks(_ source: String) {
        provider = source
        navigation.searchScope = "books"
        navigation.tab = .search
    }

    private func openAudio(_ source: AudioSource) {
        disabledSources = disabledSources.components(separatedBy: ",").filter { $0 != source.rawValue }.joined(separator: ",")
        UserDefaults.standard.set("", forKey: "preferredAudioCatalogID")
        audioSource = source
        navigation.searchScope = "audio"
        navigation.tab = .search
    }
}
