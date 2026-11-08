import SwiftUI
import UIKit

struct ReaderNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var audio = false
}

extension View {
    func readerAccessories() -> some View { modifier(ReaderAccessories()) }
    func readerNotice() -> some View { modifier(ReaderNoticeOverlay()) }
}

private struct ReaderAccessories: ViewModifier {
    @EnvironmentObject private var player: AudioPlayerModel
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.book != nil { AudioMiniPlayer().padding(.horizontal, 16).padding(.vertical, 8) }
        }.readerNotice()
    }
}

private struct ReaderNoticeOverlay: ViewModifier {
    @EnvironmentObject private var navigation: ReaderNavigation
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let notice = navigation.notice {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: L10n.text(notice.title)).font(.subheadline.weight(.semibold))
                            Text(notice.message).font(.footnote).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { navigation.notice = nil } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.accessibilityLabel(Text(verbatim: L10n.text("Закрыть")))
                    }
                    Button {
                        navigation.libraryScope = notice.audio ? "audio" : "books"
                        navigation.tab = .library
                        navigation.notice = nil
                        dismiss()
                    } label: {
                        Text(verbatim: L10n.text("В библиотеку")).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }.padding(14).foregroundStyle(.white)
                    .background(ReaderStyle.raised, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ReaderStyle.line))
                    .padding(16).shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .accessibilityElement(children: .contain)
                    .task(id: notice.id) {
                        // Keep the action reachable longer for assistive technology.
                        guard !UIAccessibility.isVoiceOverRunning else { return }
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        if navigation.notice?.id == notice.id { navigation.notice = nil }
                    }
            }
        }
    }
}

private struct AudioMiniPlayer: View {
    @EnvironmentObject private var player: AudioPlayerModel
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    var body: some View {
        if let book = player.book {
            HStack(spacing: 0) {
                Button { navigation.playerPresented = true } label: {
                    HStack(spacing: 10) {
                        BookArtwork(title: book.title, author: book.author, coverURL: book.coverURL, width: 34, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.chapters.indices.contains(player.chapterIndex) ? player.chapters[player.chapterIndex].title : book.author)
                                .font(.caption).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, 12).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint(Text(verbatim: L10n.text("Открыть плеер")))
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(Color(hex: accentHex)).frame(width: 52, height: 60)
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: L10n.text(player.isPlaying ? "Пауза" : "Продолжить прослушивание")))
            }.foregroundStyle(.white)
                .background(ReaderStyle.raised, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ReaderStyle.line))
        }
    }
}
