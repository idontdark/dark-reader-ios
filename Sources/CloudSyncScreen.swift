import SwiftUI
import UniformTypeIdentifiers

/// Uses the system Files directory picker. The selected directory can be in
/// iCloud Drive and remains accessible through a persistent security bookmark.
struct CloudSyncScreen: View {
    @EnvironmentObject private var cloud: CloudSyncManager
    @State private var pickingFolder = false
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Папка", value: cloud.folderName ?? "Не выбрана")
                Button {
                    pickingFolder = true
                } label: {
                    Label(
                        cloud.isConnected ? "Изменить папку" : "Выбрать папку",
                        systemImage: "folder"
                    )
                }
            } header: {
                Text("iCloud Drive")
            } footer: {
                Text("Выберите папку в разделе iCloud Drive приложения «Файлы». Dark Reader создаст внутри неё папку «Dark Reader» и будет хранить там книги и настройки.")
            }

            Section {
                Toggle(
                    "Автоматическая синхронизация",
                    isOn: Binding(
                        get: { cloud.automatic },
                        set: { cloud.setAutomatic($0) }
                    )
                )
                .disabled(!cloud.isConnected)

                HStack(spacing: 10) {
                    if cloud.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: cloud.isConnected ? "checkmark.icloud" : "icloud.slash")
                            .foregroundStyle(.secondary)
                    }
                    Text(cloud.status)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                if let saved = cloud.lastSavedAt {
                    LabeledContent("Последняя запись") {
                        Text(saved.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                }

                Button {
                    Task { await cloud.syncNow() }
                } label: {
                    Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!cloud.isConnected || cloud.isSyncing)
            } header: {
                Text("Синхронизация")
            } footer: {
                Text("Изменения сохраняются автоматически. iOS самостоятельно отправляет файлы из iCloud Drive в облако, поэтому запись в папку ещё не гарантирует завершение выгрузки.")
            }

            Section {
                Button {
                    if cloud.isConnected {
                        Task { await cloud.syncNow() }
                    } else {
                        pickingFolder = true
                    }
                } label: {
                    Label("Восстановить библиотеку", systemImage: "arrow.counterclockwise.icloud")
                }

                if cloud.restoredBooks > 0 {
                    Label(
                        "Восстановлено книг: \(cloud.restoredBooks)",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            } footer: {
                Text("После переустановки приложения снова выберите прежнюю папку в iCloud Drive. Книги, позиции чтения, закладки и настройки будут восстановлены без замены более новых данных.")
            }

            if cloud.isConnected {
                Section {
                    Button("Отключить эту папку", role: .destructive) {
                        confirmDisconnect = true
                    }
                } footer: {
                    Text("Отключение не удаляет сохранённые книги из iCloud Drive.")
                }
            }
        }
        .navigationTitle("Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $pickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let folder = urls.first else { return }
                Task { await cloud.chooseFolder(folder) }
            case .failure:
                break
            }
        }
        .confirmationDialog(
            "Отключить синхронизацию?",
            isPresented: $confirmDisconnect
        ) {
            Button("Отключить папку", role: .destructive) {
                cloud.forgetFolder()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ваши данные останутся в выбранной папке.")
        }
    }
}
