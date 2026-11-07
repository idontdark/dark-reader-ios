import SwiftUI
import UniformTypeIdentifiers

enum ReaderTab: Int, CaseIterable, Hashable {
    case library, catalog, add, settings
}

@MainActor
final class ReaderNavigation: ObservableObject {
    @Published var tab: ReaderTab = .library
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
            .fullScreenCover(isPresented: Binding(
                get: { !didFinishOnboarding },
                set: { if !$0 { didFinishOnboarding = true } }
            )) {
                WelcomeScreen { didFinishOnboarding = true }
            }
            .task { if sync.automatic { _ = await sync.syncNow() } }
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
