import SwiftUI
import UniformTypeIdentifiers
import UIKit
import GoogleSignInSwift

struct CloudSyncScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var cloud:CloudSyncManager
    @ObservedObject private var google=GoogleDriveBackup.shared
    @State private var deleteGoogle=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:19) {
                Text(verbatim:L10n.render("Резервные копии",language:localizationLanguage)).font(.system(size:27,weight:.bold))
                Text(verbatim:L10n.render("Сохраняйте электронные книги, закладки, прогресс и настройки. Аудиофайлы в эти копии не входят.",language:localizationLanguage))
                    .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
                LocalBackupCard()
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
}
