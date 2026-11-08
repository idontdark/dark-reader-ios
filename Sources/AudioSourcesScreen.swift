import SwiftUI

struct AudioSourcesScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @AppStorage("disabledAudioSources") private var disabled = ""
    @State private var status: [AudioSource: String] = [:]
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(AudioSource.online) { source in
                    ReaderCard {
                        Toggle(isOn: Binding(get: { !disabled.components(separatedBy: ",").contains(source.rawValue) },
                                             set: { enabled in
                            var values = Set(disabled.components(separatedBy: ",").filter { !$0.isEmpty })
                            if enabled { values.remove(source.rawValue) } else { values.insert(source.rawValue) }
                            disabled = values.sorted().joined(separator: ",")
                        })) {
                            Label(source.title, systemImage: "headphones").font(.headline)
                        }
                        .accessibilityIdentifier("audio-source-"+source.rawValue)
                        Text(verbatim:L10n.render(source == .librivox ? "Записи добровольцев, преимущественно классика" : source == .knigavuhe ? "Русскоязычные аудиокниги. Встроенный плеер и загрузка." : source == .akniga ? "Поиск по русскоязычному каталогу. Прослушивание на сайте." : "Архив аудиозаписей; доступность зависит от прав и региона",language:localizationLanguage))
                            .font(.caption).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 8)
                        Text(verbatim:L10n.render(status[source] ?? "Ещё не проверен",language:localizationLanguage)).font(.caption)
                        Button("Проверить подключение") {
                            status[source] = "Проверяем…"
                            Task {
                                do {
                                    _ = try await AudioCatalogService.featured(source: source, language: "ru")
                                    status[source] = "Каталог отвечает"
                                } catch { status[source] = "Нет соединения с каталогом" }
                            }
                        }.font(.subheadline).padding(.top, 8)
                    }
                }
                ReaderCard {
                    Text(verbatim:L10n.render("Новые поставщики появятся после проверки API и разрешения на воспроизведение в стороннем приложении.",language:localizationLanguage))
                        .font(.footnote).foregroundStyle(ReaderStyle.secondary)
                }
            }.padding(20)
        }.readerCanvas().readerNavigationTitle("Аудиокниги — источники")
    }
}
