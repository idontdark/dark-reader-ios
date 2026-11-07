import SwiftUI
import UniformTypeIdentifiers

enum ReaderTab: Int, CaseIterable, Hashable {
    case library, catalog, search, settings
}

@MainActor
final class ReaderNavigation: ObservableObject {
    @Published var tab: ReaderTab = .library
    @Published var authorToSearch: String?
    @Published var bookToSearch: String?
    @Published var genreToBrowse: String?
    @Published var searchScope = "books"
}

@main
struct DarkReaderApp: App {
    init() { CloudBackgroundSync.register() }

    var body: some Scene {
        WindowGroup {
            RootReaderView()
        }
    }
}

/// A small tab container prevents the SwiftUI generic view body from becoming enormous.
private struct RootTabs: View {
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("appAppearance") private var appearance = "dark"

    var body: some View {
        TabView(selection: $navigation.tab) {
            LibraryScreen()
                .tabItem { Label("Библиотека", systemImage: "books.vertical.fill") }
                .tag(ReaderTab.library)

            CatalogHomeScreen()
                .tabItem { Label("Каталог", systemImage: "square.stack.3d.up") }
                .tag(ReaderTab.catalog)

            UnifiedSearchScreen()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(ReaderTab.search)

            SettingsScreen()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(ReaderTab.settings)
        }
        .tint(Color(hex: accentHex))
        .toolbarBackground(ReaderStyle.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(appearance == "light" ? .light :
            appearance == "system" ? nil : .dark)
    }
}

private struct RootReaderView: View {
    @StateObject private var library = DarkReaderAppState.shared.books
    @StateObject private var sync = DarkReaderAppState.shared.sync
    @StateObject private var navigation = ReaderNavigation()
    @StateObject private var audioPlayer = AudioPlayerModel()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("onboardingSchemaVersion") private var onboardingSchemaVersion = 0
    @AppStorage("appLanguage") private var appLanguage = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @AppStorage("favoriteBooksJSON") private var favoriteBooksJSON = "[]"
    @AppStorage("wantsBooks") private var wantsBooks = true
    @AppStorage("wantsAudiobooks") private var wantsAudio = false
    @State private var importError: String?

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { onboardingSchemaVersion < 3 },
            set: { if !$0 { completeOnboarding() } }
        )
    }

    private func completeOnboarding() {
        onboardingSchemaVersion = 3
        didFinishOnboarding = true
    }

    private var tabs: some View {
        RootTabs()
            .environmentObject(library)
            .environmentObject(sync)
            .environmentObject(navigation)
            .environmentObject(audioPlayer)
            .environment(\.locale, Locale(identifier: appLanguage))
            .fullScreenCover(isPresented: onboardingBinding) {
                OnboardingFlow { completeOnboarding() }
            }
    }

    private var preferenceObservers: some View {
        tabs
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
    }

    private var additionalObservers: some View {
        preferenceObservers
            .onChange(of: favoriteBooksJSON) { _, value in
                sync.settingsChanged(key: "favoriteBooksJSON", value: value)
            }
            .onChange(of: wantsBooks) { _, value in
                sync.settingsChanged(key: "wantsBooks", value: String(value))
            }
            .onChange(of: wantsAudio) { _, value in
                sync.settingsChanged(key: "wantsAudiobooks", value: String(value))
            }
    }

    var body: some View {
        additionalObservers
            .task {
                if sync.automatic { _ = await sync.syncNow() }
            }
            .onOpenURL(perform: handleIncomingURL)
            .alert("Не удалось импортировать", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
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

    private func handleIncomingURL(_ url: URL) {
        guard url.isFileURL else { return }
        Task { @MainActor in
            do {
                try await library.addImportedFile(
                    from: url, title: url.deletingPathExtension().lastPathComponent
                )
                navigation.tab = .library
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
