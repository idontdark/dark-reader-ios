import SwiftUI
import UniformTypeIdentifiers

struct CloudSyncScreen: View {
    @EnvironmentObject private var cloud: CloudSyncManager
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var pickingFolder = false
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Синхронизация")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Сохраните библиотеку в iCloud Drive и восстановите её после переустановки.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Хранилище")
                    ReaderCard {
                        HStack(spacing: 13) {
                            Image(systemName: "icloud")
                                .foregroundStyle(Color(hex: accentHex))
                                .font(.title2)
                                .frame(width: 35)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("iCloud Drive").font(.headline)
                                Text(cloud.folderName ?? "Папка не подключена")
                                    .font(.footnote)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                            Spacer()
                            Image(systemName: cloud.isConnected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(cloud.isConnected ? .green : ReaderStyle.secondary)
                        }
                        .padding(.bottom, 15)
                        PurpleAction(
                            title: cloud.isConnected ? "Изменить папку" : "Выбрать папку",
                            icon: "folder"
                        ) {
                            pickingFolder = true
                        }
                    }
                    Text("Книги и прогресс будут сохраняться в выбранном хранилище.")
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Автоматическое сохранение")
                    ReaderCard {
                        Toggle("Синхронизировать автоматически", isOn: Binding(
                            get: { cloud.automatic },
                            set: { cloud.setAutomatic($0) }
                        ))
                        .disabled(!cloud.isConnected)
                        .padding(.vertical, 8)
                        ReaderDivider()
                        HStack(spacing: 10) {
                            if cloud.isSyncing {
                                ProgressView().tint(Color(hex: accentHex))
                            } else {
                                Image(systemName: cloud.isConnected ? "checkmark.icloud" : "icloud.slash")
                                    .foregroundStyle(Color(hex: accentHex))
                            }
                            Text(cloud.status)
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 14)
                        if let date = cloud.lastSavedAt {
                            ReaderDivider()
                            HStack {
                                Text("Последнее сохранение")
                                    .font(.subheadline)
                                Spacer()
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                            .padding(.vertical, 14)
                        }
                        ReaderDivider()
                        Button {
                            Task { _ = await cloud.syncNow() }
                        } label: {
                            ReaderRow(icon: "arrow.triangle.2.circlepath",
                                      title: "Синхронизировать сейчас",
                                      subtitle: nil) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!cloud.isConnected || cloud.isSyncing)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Восстановление")
                    ReaderCard {
                        Button {
                            if cloud.isConnected {
                                Task { _ = await cloud.syncNow() }
                            } else {
                                pickingFolder = true
                            }
                        } label: {
                            ReaderRow(icon: "arrow.counterclockwise.icloud",
                                      title: "Восстановить библиотеку",
                                      subtitle: cloud.restoredBooks > 0
                                        ? "Восстановлено книг: \(cloud.restoredBooks)" : nil) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("После переустановки снова выберите ту же папку. Файлы останутся в iCloud Drive, даже если предыдущая IPA перестала запускаться.")
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                if cloud.isConnected {
                    Button("Отключить папку", role: .destructive) {
                        confirmDisconnect = true
                    }
                    .font(.subheadline)
                    .padding(.top, 5)
                }

                Text("Запись файлов в папку не означает, что iOS уже закончила выгрузку в iCloud. Фоновая синхронизация зависит от системы.")
                    .font(.caption)
                    .foregroundStyle(ReaderStyle.secondary)
                    .padding(.bottom, 15)
            }
            .padding(20)
        }
        .readerCanvas()
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let folders):
                guard let folder = folders.first else { return }
                Task { await cloud.chooseFolder(folder) }
            case .failure:
                break
            }
        }
        .confirmationDialog("Отключить папку?", isPresented: $confirmDisconnect) {
            Button("Отключить", role: .destructive) {
                cloud.forgetFolder()
            }
        } message: {
            Text("Книги, уже сохранённые в iCloud Drive, не удалятся.")
        }
    }
}
