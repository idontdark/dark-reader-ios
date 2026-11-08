import Foundation
import UIKit
import UniformTypeIdentifiers
import Combine

enum CloudConnectionDiagnostics {
    private static let lock=NSLock()
    static func record(_ event:String,error:Error?=nil) {
        lock.lock();defer {lock.unlock()}
        let detail=error.map {" \(($0 as NSError).domain):\(($0 as NSError).code)"} ?? ""
        let line="\(ISO8601DateFormatter().string(from:Date())) \(event)\(detail)"
        var events=UserDefaults.standard.stringArray(forKey:"cloudSync.connectionEvents") ?? []
        events.append(line)
        UserDefaults.standard.set(Array(events.suffix(30)),forKey:"cloudSync.connectionEvents")
    }
}

/// Uses the URL granted by Files; no private iCloud paths or local substitute.
enum CloudFolderConnection {
    static func prepare(_ selected:URL) throws -> Data {
        CloudConnectionDiagnostics.record("folder.verify.begin")
        let scoped=selected.startAccessingSecurityScopedResource()
        defer {if scoped {selected.stopAccessingSecurityScopedResource()}}
        var coordinationError:NSError?
        var operationError:Error?
        NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:selected,options:.forMerging,error:&coordinationError) {accessible in
            do {
                let root=accessible.lastPathComponent == "Dark Reader" ? accessible:accessible.appendingPathComponent("Dark Reader",isDirectory:true)
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                let probe=root.appendingPathComponent(".darkreader-access-"+UUID().uuidString)
                defer {try? FileManager.default.removeItem(at:probe)}
                let expected=Data(UUID().uuidString.utf8)
                try expected.write(to:probe,options:.atomic)
                guard try Data(contentsOf:probe) == expected else {throw CloudSyncError.accessDenied}
            } catch {operationError=error}
        }
        if let coordinationError {throw coordinationError}
        if let operationError {throw operationError}
        CloudConnectionDiagnostics.record("folder.verify.success")
        let bookmark=try selected.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)
        CloudConnectionDiagnostics.record("bookmark.created")
        return bookmark
    }
}

/// Retained independently of SwiftUI sheet updates. UIKit owns dismissal.
@MainActor
final class CloudFolderPickerPresenter:NSObject,ObservableObject,UIDocumentPickerDelegate,UIAdaptivePresentationControllerDelegate {
    @Published private(set) var presented=false
    private var picker:UIDocumentPickerViewController?
    private var completion:((URL?)->Void)?
    private var finishing=false

    func present(completion:@escaping(URL?)->Void) {
        guard !presented else{return}
        let scenes=UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.filter {$0.activationState == .foregroundActive}
        guard var host=scenes.flatMap(\.windows).first(where:{$0.isKeyWindow})?.rootViewController else {
            CloudConnectionDiagnostics.record("picker.no-presenter");completion(nil);return
        }
        while let top=host.presentedViewController {host=top}
        host.view.endEditing(true)
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
        picker.delegate=self
        picker.allowsMultipleSelection=false
        picker.modalPresentationStyle = .formSheet
        self.picker=picker;self.completion=completion;finishing=false;presented=true
        CloudConnectionDiagnostics.record("picker.present.begin")
        host.present(picker,animated:true) {
            picker.presentationController?.delegate=self
            CloudConnectionDiagnostics.record("picker.presented")
        }
    }
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
        CloudConnectionDiagnostics.record("picker.selected")
        finish(urls.first)
    }
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {
        CloudConnectionDiagnostics.record("picker.cancelled");finish(nil)
    }
    func presentationControllerDidDismiss(_ presentationController:UIPresentationController) {
        if !finishing {CloudConnectionDiagnostics.record("picker.swipe-dismissed");finish(nil)}
    }
    private func finish(_ url:URL?) {
        guard !finishing else{return}
        finishing=true
        let scoped=url?.startAccessingSecurityScopedResource() ?? false
        var didDeliver=false
        let delivered:()->Void = { [self] in
            guard !didDeliver else{return};didDeliver=true
            let callback=completion
            completion=nil;picker=nil;presented=false
            CloudConnectionDiagnostics.record("picker.completed")
            callback?(url)
            if scoped,let url {url.stopAccessingSecurityScopedResource()}
        }
        guard let picker, picker.presentingViewController != nil else {delivered();return}
        if picker.isBeingDismissed,let transition=picker.transitionCoordinator {
            if !transition.animate(alongsideTransition:nil,completion:{_ in delivered()}) {delivered()}
        } else {picker.dismiss(animated:true,completion:delivered)}
    }
}
