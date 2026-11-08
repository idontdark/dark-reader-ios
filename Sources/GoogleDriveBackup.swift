import Foundation
import SwiftUI
import UIKit
import GoogleSignIn

@MainActor
final class GoogleDriveBackup: ObservableObject {
    static let shared = GoogleDriveBackup()
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    static let clientID = "183748481353-7vbvbe3o7u1pgtg4vet7g3o86dg7lfsq.apps.googleusercontent.com"
    @Published private(set) var connected = false
    @Published private(set) var account = ""
    @Published private(set) var busy = false
    @Published private(set) var status = "Подключите Google, чтобы сохранять резервные копии."
    @Published private(set) var lastSaved = UserDefaults.standard.object(forKey:"google.lastSaved") as? Date
    @Published private(set) var automatic = UserDefaults.standard.bool(forKey:"google.automatic")
    private weak var library: BookshelfStore?
    private weak var cloud: CloudSyncManager?
    private var pending: Task<Void,Never>?
    private var savingAgain = false

    func attach(_ library: BookshelfStore, cloud: CloudSyncManager) {
        self.library=library; self.cloud=cloud
        GIDSignIn.sharedInstance.configuration=GIDConfiguration(clientID:Self.clientID)
    }
    func restoreConnection() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do { let user=try await GIDSignIn.sharedInstance.restorePreviousSignIn(); update(user) }
        catch { status="Войдите в Google повторно." }
    }
    private func update(_ user:GIDGoogleUser) {
        connected=user.grantedScopes?.contains(Self.scope) == true
        account=user.profile?.email ?? "Google Drive"
        status=connected ? "Google Drive подключён. Можно сохранить или восстановить копию." : "Разрешите доступ к резервным копиям приложения."
    }
    func connect() async {
        guard !busy, let controller=presenter() else { return }
        busy=true; defer {busy=false}
        do {
            let result=try await GIDSignIn.sharedInstance.signIn(withPresenting:controller,hint:nil,additionalScopes:[Self.scope])
            update(result.user)
        } catch {status="Вход не завершён: \(error.localizedDescription)"}
    }
    func disconnect() {
        pending?.cancel(); GIDSignIn.sharedInstance.signOut()
        connected=false;account="";automatic=false
        UserDefaults.standard.set(false,forKey:"google.automatic")
        status="Google отключён. Созданная копия осталась в вашем Диске."
    }
    func setAutomatic(_ value:Bool) {
        automatic=value;UserDefaults.standard.set(value,forKey:"google.automatic")
        if value {requestBackup()} else {pending?.cancel()}
    }
    func requestBackup() {
        guard automatic,connected else {return}
        if busy {savingAgain=true;return}
        pending?.cancel()
        pending=Task { [weak self] in
            do {try await Task.sleep(for:.seconds(3));try Task.checkCancellation()} catch {return}
            await self?.save()
        }
    }
    func save() async {
        guard !busy,connected,let library,let snapshot=cloud?.makeSnapshot() else{return}
        busy=true;status="Сохраняем копию в Google Drive…"
        defer {busy=false;if savingAgain {savingAgain=false;requestBackup()}}
        do {
            var files=try await list()
            for (index,book) in snapshot.books.enumerated() {
                try Task.checkCancellation()
                status="Сохраняем книги: \(index+1) из \(snapshot.books.count)…"
                let name="book_\(book.id.uuidString).epub"
                if files[name] == nil {
                    let bytes=try Data(contentsOf:library.fileURL(for:book),options:.mappedIfSafe)
                    guard bytes.count<=50*1024*1024 else {throw CloudSyncError.badBook}
                    files[name]=try await upload(name:name,id:nil,data:bytes,mime:"application/epub+zip")
                }
            }
            _ = try await upload(name:"library-v1.json",id:files["library-v1.json"],data:JSONEncoder().encode(snapshot),mime:"application/json")
            lastSaved=Date();UserDefaults.standard.set(lastSaved,forKey:"google.lastSaved")
            status="Копия сохранена: \(snapshot.books.count) книг, закладки, прогресс и настройки."
        } catch {status="Не удалось сохранить копию: \(error.localizedDescription)"}
    }
    func restore() async {
        guard !busy,connected,let library,let cloud else{return}
        busy=true;status="Ищем резервную копию…"
        let stage=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer {busy=false;try? FileManager.default.removeItem(at:stage)}
        do {
            let files=try await list()
            guard let manifest=files["library-v1.json"] else {throw DriveBackupError.message("Резервная копия не найдена. Сначала сохраните её на другом устройстве.")}
            let bytes=try await get(manifest,limit:5_000_000)
            let snapshot=try JSONDecoder().decode(CloudLibrarySnapshot.self,from:bytes)
            guard snapshot.schema == 1,snapshot.books.count<=10_000 else {throw CloudSyncError.invalidSnapshot}
            try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
            var staged:[String:URL]=[:]
            for (index,book) in snapshot.books.enumerated() {
                try Task.checkCancellation()
                if let local=library.books.first(where:{$0.id == book.id}),FileManager.default.fileExists(atPath:library.fileURL(for:local).path) {continue}
                status="Восстанавливаем книги: \(index+1) из \(snapshot.books.count)…"
                guard let id=files["book_\(book.id.uuidString).epub"] else {throw CloudSyncError.unavailableData}
                let data=try await get(id,limit:50*1024*1024)
                guard data.starts(with:[0x50,0x4B]) else {throw CloudSyncError.badBook}
                let file=stage.appendingPathComponent(book.id.uuidString+".epub")
                try data.write(to:file);try await BookFormatConverter.validateContainer(file)
                staged[book.id.uuidString]=file
            }
            try library.mergeFromCloud(snapshot.books,tombstones:snapshot.deletions,staged:staged)
            cloud.restoreSettings(snapshot.settings,changedAt:snapshot.settingsChangedAt)
            status="Копия восстановлена. Книги доступны в библиотеке."
        } catch {status="Не удалось восстановить копию: \(error.localizedDescription)"}
    }
    func deleteBackup() async {
        guard !busy,connected else{return}
        busy=true;defer{busy=false}
        do {
            for id in try await list().values {
                _ = try await request("https://www.googleapis.com/drive/v3/files/\(id)",method:"DELETE")
            }
            lastSaved=nil;UserDefaults.standard.removeObject(forKey:"google.lastSaved")
            status="Резервная копия удалена из Google Drive. Книги на устройстве сохранены."
        } catch {status="Не удалось удалить копию: \(error.localizedDescription)"}
    }
    private func list() async throws -> [String:String] {
        var result:[String:String]=[:];var page:String?
        repeat {
            var url=URLComponents(string:"https://www.googleapis.com/drive/v3/files")!
            url.queryItems=[.init(name:"spaces",value:"appDataFolder"),.init(name:"q",value:"trashed = false"),.init(name:"fields",value:"nextPageToken,files(id,name)"),.init(name:"pageSize",value:"1000")]
            if let page {url.queryItems?.append(.init(name:"pageToken",value:page))}
            let data=try await request(url.url!.absoluteString)
            let json=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            for file in json?["files"] as? [[String:String]] ?? [] {
                if let name=file["name"],let id=file["id"],name == "library-v1.json" || name.hasPrefix("book_") {result[name]=id}
            }
            page=json?["nextPageToken"] as? String
            guard result.count<=10_001 else {throw CloudSyncError.invalidSnapshot}
        } while page != nil
        return result
    }
    private func upload(name:String,id:String?,data:Data,mime:String) async throws -> String {
        let boundary="darkreader-"+UUID().uuidString
        var meta:[String:Any]=["name":name]
        if id == nil {meta["parents"]=["appDataFolder"]}
        var body=Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject:meta))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(mime)\r\n\r\n".utf8));body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let path=id.map {"/"+$0} ?? ""
        let response=try await request("https://www.googleapis.com/upload/drive/v3/files\(path)?uploadType=multipart&fields=id",method:id == nil ? "POST":"PATCH",body:body,contentType:"multipart/related; boundary=\(boundary)")
        guard let json=try JSONSerialization.jsonObject(with:response) as? [String:String],let newID=json["id"] else {throw CloudSyncError.invalidSnapshot}
        return newID
    }
    private func get(_ id:String,limit:Int) async throws -> Data {
        var request=URLRequest(url:URL(string:"https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!)
        request.setValue("Bearer \(try await token())",forHTTPHeaderField:"Authorization")
        let (url,response)=try await URLSession.shared.download(for:request)
        defer{try? FileManager.default.removeItem(at:url)}
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {throw DriveBackupError.message("Google Drive не отдал файл. Проверьте доступ и повторите попытку.")}
        let size=(try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size<=limit else {throw CloudSyncError.invalidSnapshot}
        return try Data(contentsOf:url)
    }
    private func token() async throws -> String {
        guard let user=GIDSignIn.sharedInstance.currentUser else {throw DriveBackupError.message("Войдите в Google повторно.")}
        let refreshed=try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
    private func request(_ url:String,method:String="GET",body:Data?=nil,contentType:String?=nil) async throws -> Data {
        var r=URLRequest(url:URL(string:url)!);r.httpMethod=method;r.httpBody=body;r.timeoutInterval=120
        r.setValue("Bearer \(try await token())",forHTTPHeaderField:"Authorization")
        if let contentType {r.setValue(contentType,forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await URLSession.shared.data(for:r)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
            let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            let detail=(json?["error"] as? [String:Any])?["message"] as? String
            throw DriveBackupError.message(detail ?? "Google Drive недоступен. Проверьте интернет и разрешение приложения.")
        }
        return data
    }
    private func presenter()->UIViewController? {
        let scenes=UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.filter {$0.activationState == .foregroundActive}
        var controller=scenes.flatMap(\.windows).first(where:{$0.isKeyWindow})?.rootViewController
        while let presented=controller?.presentedViewController {controller=presented}
        return controller
    }
}
private enum DriveBackupError:LocalizedError {
    case message(String)
    var errorDescription:String? {if case .message(let text)=self {return text};return nil}
}
