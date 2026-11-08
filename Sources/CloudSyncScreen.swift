import SwiftUI
import UniformTypeIdentifiers
import UIKit
import GoogleSignInSwift

struct CloudSyncScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var cloud:CloudSyncManager
    @ObservedObject private var google=GoogleDriveBackup.shared
    @StateObject private var folderPicker=CloudFolderPickerPresenter()
    @State private var deleteGoogle=false
    @State private var connectingICloud=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:19) {
                Text(verbatim:L10n.render("Резервные копии",language:localizationLanguage)).font(.system(size:27,weight:.bold))
                Text(verbatim:L10n.render("Сохраняйте электронные книги, закладки, прогресс и настройки. Аудиофайлы в эти копии не входят.",language:localizationLanguage))
                    .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
                ReaderCard {
                    Label("iCloud Drive",systemImage:"icloud").font(.headline)
                    Toggle("Сохранять в iCloud",isOn:Binding(get:{cloud.enabled},set:{value in
                        connectingICloud=true
                        Task {
                            if !(await cloud.setEnabled(value)) {presentFolderPicker()}
                            connectingICloud=false
                        }
                    })).disabled(connectingICloud || cloud.isSyncing || cloud.isConnecting || folderPicker.presented).padding(.top,14)
                    if connectingICloud || cloud.isSyncing || cloud.isConnecting {ProgressView().padding(.top,8)}
                    Text(verbatim:L10n.render(cloud.enabled ? "Резервные копии сохраняются в папке Dark Reader.":"Папка Dark Reader будет создана после включения сохранения.",language:localizationLanguage))
                        .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary).padding(.vertical,12)
                    Text(verbatim:L10n.render("При первом включении iOS может попросить выбрать место в iCloud Drive. Папка Dark Reader создастся автоматически. Повторно выбирать её не потребуется.",language:localizationLanguage))
                        .font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).padding(.vertical,12)
                    if cloud.enabled,cloud.isConnected {
                        HStack {
                            Button("Сохранить сейчас") {Task {_ = await cloud.syncNow()}}
                            Spacer()
                            Button("Восстановить") {Task {_ = await cloud.syncNow()}}
                        }.font(.system(size:13,weight:.semibold)).padding(.vertical,10).disabled(cloud.isSyncing)
                        Button("Изменить папку") {presentFolderPicker()}.font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
                    }
                    Text(verbatim:L10n.render(cloud.status,language:localizationLanguage)).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).padding(.top,12)
                    if let date=cloud.lastSavedAt {Text(L10n.date(date)).font(.caption2).foregroundStyle(ReaderStyle.secondary).padding(.top,6)}
                }
                ReaderCard {
                    Label("Google Drive",systemImage:"externaldrive").font(.headline)
                    Text(verbatim:L10n.render("Копия хранится в скрытой области Dark Reader. Доступ к остальным файлам вашего Диска не запрашивается.",language:localizationLanguage))
                        .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary).padding(.vertical,12)
                    if google.connected {
                        Text(google.account).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).padding(.bottom,10)
                        Toggle("Сохранять автоматически",isOn:Binding(get:{google.automatic},set:google.setAutomatic)).font(.system(size:14))
                        PurpleAction(title:"Сохранить копию",icon:"icloud.and.arrow.up") {Task {await google.save()}}.padding(.top,14)
                        Button("Восстановить библиотеку") {Task {await google.restore()}}.font(.system(size:14,weight:.semibold)).padding(.vertical,14)
                        HStack {
                            Button("Отключить") {google.disconnect()}
                            Spacer()
                            Button("Удалить копию",role:.destructive) {deleteGoogle=true}
                        }.font(.system(size:12))
                    } else {
                        GoogleSignInButton {Task {await google.connect()}}
                    }
                    if google.busy {ProgressView().padding(.top,12)}
                    Text(verbatim:L10n.render(google.status,language:localizationLanguage)).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).padding(.top,12)
                    if let date=google.lastSaved {Text(L10n.date(date)).font(.caption2).foregroundStyle(ReaderStyle.secondary).padding(.top,6)}
                }.disabled(google.busy)
                Text(verbatim:L10n.render("iOS сама определяет время фоновой передачи. Для больших библиотек оставьте приложение открытым до завершения сохранения.",language:localizationLanguage))
                    .font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
            }.padding(20)
        }.readerCanvas().readerNavigationTitle("Резервные копии").navigationBarTitleDisplayMode(.inline)
            .alert("Удалить копию Google Drive?",isPresented:$deleteGoogle) {
                Button("Удалить",role:.destructive) {Task {await google.deleteBackup()}}
                Button("Отмена",role:.cancel) {}
            } message:{Text(verbatim:L10n.render("Копия в облаке будет удалена. Книги на этом устройстве останутся.",language:localizationLanguage))}
    }
    private func presentFolderPicker() {
        folderPicker.present {url in
        guard let url else{return}
        let scoped=url.startAccessingSecurityScopedResource()
        Task {
            await cloud.chooseFolder(url)
            if scoped {url.stopAccessingSecurityScopedResource()}
        }
        }
    }
}
