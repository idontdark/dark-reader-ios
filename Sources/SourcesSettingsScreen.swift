import SwiftUI

struct SourcesSettingsScreen: View {
    @AppStorage("appLanguage") private var language = "ru"
    var body: some View {
        ScrollView {
            ReaderInsetGroup {
                NavigationLink { SourceListScreen(kind: .books) } label: {
                    ReaderRow(icon: "book", title: "Источники книг", subtitle: nil) { Image(systemName: "chevron.right") }
                }
                ReaderDivider()
                NavigationLink { SourceListScreen(kind: .audio) } label: {
                    ReaderRow(icon: "headphones", title: "Источники аудиокниг", subtitle: nil) { Image(systemName: "chevron.right") }
                }
            }.buttonStyle(.plain).padding(20)
        }.readerCanvas().readerNavigationTitle("Источники")
    }
}
struct SourceListScreen: View {
    let kind: SourceKind
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage(SourcePreferences.key) private var enabledData = Data()
    @AppStorage(SourcePreferences.healthKey) private var healthData = Data()
    @State private var checking = Set<String>()
    @State private var checkingAll = false
    private var sources: [SourceDescriptor] { SourceCatalog.all.filter { $0.kind == kind } }
    private var enabled: Set<String> { _ = enabledData; return Set(SourcePreferences.enabled(kind).map(\.id)) }
    private var health: [String: SourceHealthResult] { _ = healthData; return SourcePreferences.health() }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Button("Проверить включённые источники") { Task { await checkAll() } }
                    .frame(minHeight: 44).disabled(checkingAll || enabled.isEmpty)
                ForEach(sources) { source in sourceCard(source) }
                vpnNote
            }.padding(20)
        }.readerCanvas().readerNavigationTitle(kind == .books ? "Источники книг" : "Источники аудиокниг")
    }
    private func sourceCard(_ source: SourceDescriptor) -> some View {
        ReaderCard {
            Toggle(isOn: Binding(get: { enabled.contains(source.id) }, set: { value in
                SourcePreferences.set(source, enabled: value)
                GoogleDriveBackup.shared.requestBackup()
            })) {
                Label(source.name, systemImage: kind == .books ? "book" : "headphones").font(.headline)
            }
            Text(source.domain).font(.caption).foregroundStyle(ReaderStyle.secondary).padding(.top, 4)
            if let result = health[source.id] {
                Text(verbatim: L10n.text(statusTitle(result.state), language: language)).font(.subheadline.weight(.medium)).padding(.top, 10)
                Text(verbatim: L10n.render(result.message, language: language)).font(.caption).foregroundStyle(ReaderStyle.secondary)
                Text(L10n.date(result.checkedAt)).font(.caption2).foregroundStyle(ReaderStyle.secondary).padding(.top, 4)
                if result.searchSucceeded || result.detailSucceeded {
                    Text(verbatim: capabilities(result)).font(.caption).foregroundStyle(ReaderStyle.secondary).padding(.top, 6)
                }
                vpnNote.padding(.top, 8)
            } else {
                Text(verbatim: L10n.text(source.defaultEnabled ? "Ещё не проверен" : "Источник не проверен и выключен по умолчанию.", language: language)).font(.caption).foregroundStyle(ReaderStyle.secondary).padding(.top, 8)
            }
            HStack {
                Button("Проверить") { Task { await check(source) } }.disabled(checking.contains(source.id)).frame(minHeight: 44)
                if checking.contains(source.id) { ProgressView().controlSize(.small) }
            }
        }
    }
    private var vpnNote: some View {
        Text(verbatim: L10n.text("Некоторые сервисы могут не отвечать при проверке, но оставаться рабочими из-за региональных ограничений или особенностей подключения. Попробуйте повторить проверку с VPN.", language: language))
            .font(.caption).foregroundStyle(ReaderStyle.secondary)
    }
    private func statusTitle(_ state: SourceHealthState) -> String {
        switch state { case .working: "Работает"; case .partial: "Частично доступен"; case .unverified: "Не удалось проверить" }
    }
    private func capabilities(_ result: SourceHealthResult) -> String {
        [(result.searchSucceeded, "Поиск"), (result.detailSucceeded, "Карточки"),
         (result.downloadSucceeded, "Скачивание"), (result.playbackSucceeded, "Прослушивание")]
            .filter(\.0).map { L10n.text($0.1, language: language) }.joined(separator: " · ")
    }
    private func check(_ source: SourceDescriptor) async {
        guard checking.insert(source.id).inserted else { return }
        defer { checking.remove(source.id) }
        let result = await SourceHealthChecker.check(source)
        SourcePreferences.saveHealth(result, source: source)
    }
    private func checkAll() async {
        checkingAll = true; defer { checkingAll = false }
        for source in SourcePreferences.enabled(kind) {
            guard !Task.isCancelled else { return }
            await check(source)
        }
    }
}
