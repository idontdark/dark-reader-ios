import SwiftUI
import UniformTypeIdentifiers
import UIKit
import GoogleSignInSwift

struct CloudSyncScreen:View {
    @EnvironmentObject private var cloud:CloudSyncManager
    @ObservedObject private var google=GoogleDriveBackup.shared
    @State private var pickingFolder=false
    @State private var deleteGoogle=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:19) {
                Text("Резервные копии").font(.system(size:27,weight:.bold))
                Text("Сохраняйте электронные книги, закладки, прогресс и настройки. Аудиофайлы в эти копии не входят.")
                    .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
                ReaderCard {
                    Label("iCloud Drive",systemImage:"icloud").font(.headline)
                    Text(cloud.isConnected ? "Папка Dark Reader подключена":"Создадим папку Dark Reader в выбранном месте iCloud Drive.")
                        .font(.system(size:13)).foregroundStyle(ReaderStyle.secondary).padding(.vertical,12)
                    PurpleAction(title:cloud.isConnected ? "Изменить папку":"Подключить iCloud Drive",icon:"folder") {
                        Task {if !(await cloud.connectDefaultFolder()) {pickingFolder=true}}
                    }
                    Text("Если iOS попросит выбрать место, откройте iCloud Drive и нажмите «Открыть». Папка Dark Reader появится автоматически; повторно выбирать её не нужно.")
                        .font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).padding(.vertical,12)
                    if cloud.isConnected {
                        Toggle("Сохранять автоматически",isOn:Binding(get:{cloud.automatic},set:cloud.setAutomatic))
                            .font(.system(size:14)).padding(.vertical,8)
                        HStack {
                            Button("Сохранить сейчас") {Task {_ = await cloud.syncNow()}}
                            Spacer()
                            Button("Восстановить") {Task {_ = await cloud.syncNow()}}
                        }.font(.system(size:13,weight:.semibold)).padding(.vertical,10).disabled(cloud.isSyncing)
                        Button("Отключить папку") {cloud.forgetFolder()}.font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
                    }
                    Text(cloud.status).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).padding(.top,12)
                    if let date=cloud.lastSavedAt {Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(ReaderStyle.secondary).padding(.top,6)}
                }
                ReaderCard {
                    Label("Google Drive",systemImage:"externaldrive").font(.headline)
                    Text("Копия хранится в скрытой области Dark Reader. Доступ к остальным файлам вашего Диска не запрашивается.")
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
                    Text(google.status).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary).padding(.top,12)
                    if let date=google.lastSaved {Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(ReaderStyle.secondary).padding(.top,6)}
                }.disabled(google.busy)
                Text("iOS сама определяет время фоновой передачи. Для больших библиотек оставьте приложение открытым до завершения сохранения.")
                    .font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
            }.padding(20)
        }.readerCanvas().navigationTitle("Резервные копии").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$pickingFolder) {
                CloudFolderPicker {result in
                    pickingFolder=false
                    if case .success(let url)=result {Task {await cloud.chooseFolder(url)}}
                }.ignoresSafeArea()
            }
            .alert("Удалить копию Google Drive?",isPresented:$deleteGoogle) {
                Button("Удалить",role:.destructive) {Task {await google.deleteBackup()}}
                Button("Отмена",role:.cancel) {}
            } message:{Text("Копия в облаке будет удалена. Книги на этом устройстве останутся.")}
    }
}
private struct CloudFolderPicker:UIViewControllerRepresentable {
    let result:(Result<URL,Error>)->Void
    func makeCoordinator()->Coordinator {Coordinator(result)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
        picker.allowsMultipleSelection=false;picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController:UIDocumentPickerViewController,context:Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let result:(Result<URL,Error>)->Void
        init(_ result:@escaping(Result<URL,Error>)->Void) {self.result=result}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
            if let url=urls.first {result(.success(url))}
        }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {result(.failure(CocoaError(.userCancelled)))}
    }
}
