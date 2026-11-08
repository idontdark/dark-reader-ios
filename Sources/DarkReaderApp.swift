import SwiftUI
import UniformTypeIdentifiers
import GoogleSignIn

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
    @Published var libraryScope = "books"
    @Published var catalogScope = "books"
}

@main
struct DarkReaderApp: App {
    init() {
        CloudBackgroundSync.register()
        let defaults=UserDefaults.standard
        if defaults.string(forKey:"accentHex")?.uppercased() == "#8755E8" {defaults.set(ReaderStyle.defaultAccent,forKey:"accentHex")}
        if !["percent","pages"].contains(defaults.string(forKey:"readerProgressDisplay") ?? "") {
            defaults.set("percent",forKey:"readerProgressDisplay")
        }
        let appearance=UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor=UIColor(ReaderStyle.background)
        appearance.shadowColor=UIColor.white.withAlphaComponent(0.06)
        for item in [appearance.stackedLayoutAppearance,appearance.inlineLayoutAppearance,appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor=UIColor(red:0.57,green:0.52,blue:0.62,alpha:1)
            item.normal.titleTextAttributes=[.font:UIFont.systemFont(ofSize:9,weight:.medium),.foregroundColor:UIColor(red:0.57,green:0.52,blue:0.62,alpha:1)]
            item.selected.titleTextAttributes=[.font:UIFont.systemFont(ofSize:9,weight:.medium)]
        }
        UITabBar.appearance().standardAppearance=appearance
        UITabBar.appearance().scrollEdgeAppearance=appearance
        let bar=UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor=UIColor(ReaderStyle.background)
        bar.shadowColor = .clear
        bar.titleTextAttributes=[.font:UIFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:UIColor.white]
        UINavigationBar.appearance().standardAppearance=bar
        UINavigationBar.appearance().scrollEdgeAppearance=bar
    }

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
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }
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
    @AppStorage("catalog.wishlistJSON") private var wishlistJSON="[]"
    @AppStorage("catalog.favoritesJSON") private var catalogFavoritesJSON="[]"
    @AppStorage("discovery.wishlistJSON") private var discoveryWishlistJSON="[]"
    @AppStorage("savedOPDSCatalogs") private var savedCatalogsJSON="[]"
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
            .onChange(of: appLanguage) { old, value in
                if bookLanguage == "auto" { bookLanguage = value }
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
            .onChange(of:savedCatalogsJSON) {_,value in sync.settingsChanged(key:"savedOPDSCatalogs",value:value)}
            .onChange(of:wishlistJSON) {_,value in sync.settingsChanged(key:"catalog.wishlistJSON",value:value)}
            .onChange(of:catalogFavoritesJSON) {_,value in sync.settingsChanged(key:"catalog.favoritesJSON",value:value)}
            .onChange(of:discoveryWishlistJSON) {_,value in sync.settingsChanged(key:"discovery.wishlistJSON",value:value)}
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
                DownloadQueue.shared.attach(library)
                await GoogleDriveBackup.shared.restoreConnection()
                if bookLanguage == "auto" { bookLanguage = appLanguage }
                if UserDefaults.standard.object(forKey: "preferredAudioSource") == nil {
                    UserDefaults.standard.set(appLanguage == "ru" ? AudioSource.archive.rawValue : AudioSource.librivox.rawValue, forKey: "preferredAudioSource")
                }
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
        if GIDSignIn.sharedInstance.handle(url) {return}
        guard url.isFileURL else { return }
        Task { @MainActor in
            do {
                if AudioImportStore.extensions.contains(url.pathExtension.lowercased()) {
                    do {
                        _ = try await AudioImportStore.importFiles([url])
                        navigation.tab = .library
                        return
                    } catch {
                        if url.pathExtension.lowercased() != "zip" { throw error }
                    }
                }
                try await library.addImportedFile(
                    from: url, title: url.deletingPathExtension().lastPathComponent
                )
                navigation.tab = .library
            } catch {
                importError = L10n.errorDescription(error)
            }
        }
    }
}
