import SwiftUI
import UniformTypeIdentifiers

enum ReaderTab: Int, CaseIterable, Hashable {
    case library, catalog, add, settings
}

@MainActor
final class ReaderNavigation: ObservableObject {
    @Published var tab: ReaderTab = .library
    @Published var authorToSearch: String?
}

@main
struct DarkReaderApp: App {
    @StateObject private var library = DarkReaderAppState.shared.books
    @StateObject private var sync = DarkReaderAppState.shared.sync
    @StateObject private var navigation = ReaderNavigation()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("appAppearance") private var appearance = "dark"
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("onboardingSchemaVersion") private var onboardingSchemaVersion = 0
    @AppStorage("appLanguage") private var appLanguage = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @AppStorage("wantsBooks") private var wantsBooks = true
    @AppStorage("wantsAudiobooks") private var wantsAudio = false
    @State private var importError: String?

    init() { CloudBackgroundSync.register() }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $navigation.tab) {
                LibraryScreen()
                    .tabItem { Label("Библиотека", systemImage: "books.vertical.fill") }
                    .tag(ReaderTab.library)
                CatalogScreen()
                    .tabItem { Label("Каталог", systemImage: "magnifyingglass") }
                    .tag(ReaderTab.catalog)
                ImportScreen()
                    .tabItem { Label("Добавить", systemImage: "square.and.arrow.down") }
                    .tag(ReaderTab.add)
                SettingsScreen()
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
                    .tag(ReaderTab.settings)
            }
            .tint(Color(hex: accentHex))
            .toolbarBackground(ReaderStyle.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
            .environmentObject(library)
            .environmentObject(sync)
            .environmentObject(navigation)
            .environment(\.locale, Locale(identifier: appLanguage))
            .fullScreenCover(isPresented: Binding(
                get: { onboardingSchemaVersion < 2 },
                set: { if !$0 {
                    onboardingSchemaVersion = 2
                    didFinishOnboarding = true
                } }
            )) {
                OnboardingFlow {
                    onboardingSchemaVersion = 2
                    didFinishOnboarding = true
                }
            }
            .task { if sync.automatic { _ = await sync.syncNow() } }
            .onChange(of: appLanguage) { _, value in
                sync.settingsChanged(key: "appLanguage", value: value)
            }
            .onChange(of: bookLanguage) { _, value in
                sync.settingsChanged(key: "preferredBookLanguage", value: value)
            }
            .onChange(of: genresJSON) { _, value in
                sync.settingsChanged(key: "preferredGenresJSON", value: value)
            }
            .onChange(of: authorsJSON) { _, value in
                sync.settingsChanged(key: "preferredAuthorsJSON", value: value)
            }
            .onChange(of: wantsBooks) { _, value in
                sync.settingsChanged(key: "wantsBooks", value: String(value))
            }
            .onChange(of: wantsAudio) { _, value in
                sync.settingsChanged(key: "wantsAudiobooks", value: String(value))
            }
            .onOpenURL { url in
                if url.isFileURL {
                    do {
                        try library.addImportedFile(
                            from: url, title: url.deletingPathExtension().lastPathComponent
                        )
                        navigation.tab = .library
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
            .alert("Не удалось импортировать", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if sync.automatic { Task { _ = await sync.syncNow() } }
                case .background:
                    if sync.automatic { CloudBackgroundSync.schedule() }
                default: break
                }
            }
        }
    }
}
