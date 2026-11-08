import SwiftUI

/// Downloading is independent of the current player and survives closing this view.
struct AudioDownloadAction: View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    let book: AudioBook
    let chapters: [AudioChapter]
    @EnvironmentObject private var player: AudioPlayerModel
    @AppStorage("appLanguage") private var language = "ru"

    private var complete: Bool {
        !chapters.isEmpty && chapters.allSatisfy { player.localURL(for: $0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if player.downloadingBookID == book.id {
                ProgressView(value: min(Double(player.totalDownloads),Double(player.completedDownloads)+(player.downloadExpectedBytes>0 ? min(1,Double(player.downloadBytes)/Double(player.downloadExpectedBytes)):0)), total: Double(max(1, player.totalDownloads)))
                    .tint(Color(hex: accentHex))
                Text(verbatim:bytes(player.downloadBytes)+(player.downloadExpectedBytes>0 ? " / "+bytes(player.downloadExpectedBytes):""))
                    .font(.caption.monospacedDigit()).foregroundStyle(ReaderStyle.secondary)
                HStack {
                    Text(verbatim: String(format: L10n.text("Скачано глав: %d из %d", language: language), player.completedDownloads, player.totalDownloads))
                        .font(.caption).foregroundStyle(ReaderStyle.secondary)
                    Spacer()
                    Button(L10n.text("Отмена", language: language)) { player.cancelDownload() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            } else if complete {
                Label(L10n.text("Доступно без интернета", language: language), systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(ReaderStyle.secondary).frame(minHeight: 44)
            } else {
                PurpleAction(title: "Скачать аудиокнигу", icon: "arrow.down.to.line") {
                    player.startDownload(book, tracks: chapters)
                }.disabled(chapters.isEmpty || player.downloadingBookID != nil)
                if player.downloadingBookID != nil {
                    Text(verbatim: L10n.text("Дождитесь завершения текущей загрузки.", language: language))
                        .font(.caption).foregroundStyle(ReaderStyle.secondary)
                }
            }
            if let error = player.downloadError {
                Text(verbatim: error).font(.caption).foregroundStyle(ReaderStyle.secondary)
            }
        }
    }
    private func bytes(_ value:Int64)->String {
        String(format:"%.1f",locale:Locale(identifier:language),Double(max(0,value))/1_048_576)+" "+L10n.text("МБ",language:language)
    }

}
