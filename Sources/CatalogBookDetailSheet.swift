import SwiftUI

struct CatalogBookDetailSheet: View {
    let book: CatalogBook
    let onClose: () -> Void
    @EnvironmentObject private var library: BookshelfStore
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var downloading = false
    @State private var fraction = 0.0
    @State private var downloaded = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    HStack(alignment: .top, spacing: 18) {
                        BookArtwork(title: book.title, author: book.author,
                                    coverURL: book.coverURL, width: 116, height: 167)
                        VStack(alignment: .leading, spacing: 11) {
                            Text(book.title)
                                .font(.title3.weight(.bold))
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                            Label("Электронная книга", systemImage: "book")
                                .font(.footnote)
                                .foregroundStyle(Color(hex: accentHex))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Описание")
                        let summary = book.summary?.replacingOccurrences(
                            of: "<[^>]+>", with: "", options: .regularExpression
                        ) ?? ""
                        Text(summary.isEmpty ? "Описание пока недоступно." : summary)
                            .font(.body)
                            .foregroundStyle(summary.isEmpty ? ReaderStyle.secondary : Color.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if downloading {
                        ProgressView(value: fraction).tint(Color(hex: accentHex))
                        Text(fraction > 0 ? "Загружено \(Int(fraction * 100))%" : "Начинаем загрузку…")
                            .font(.footnote)
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                    if downloaded {
                        Label("Книга сохранена. Откройте библиотеку, чтобы начать чтение.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                        PurpleAction(title: "Готово", icon: "checkmark") { onClose() }
                    } else if book.epubURL != nil {
                        PurpleAction(title: downloading ? "Загружаем…" : "Скачать книгу",
                                     icon: "arrow.down.to.line") {
                            Task { await download() }
                        }
                        .disabled(downloading)
                    } else {
                        Text("Откройте раздел каталога, чтобы выбрать формат книги.")
                            .font(.subheadline)
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                }
                .padding(20)
            }
            .readerCanvas()
            .navigationTitle("О книге")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { onClose() }
                }
            }
        }
    }

    private func download() async {
        downloading = true
        defer { downloading = false }
        do {
            try await library.download(book) { fraction = $0 }
            downloaded = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorText = "Не удалось загрузить книгу. Проверьте соединение и повторите попытку."
        }
    }
}
