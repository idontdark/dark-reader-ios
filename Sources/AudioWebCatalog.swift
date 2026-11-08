import SwiftUI
import SafariServices
import UIKit

struct AudioWebCatalog: Identifiable {
    let id = UUID()
    let url: URL
    static func search(host: String, query: String) -> AudioWebCatalog? {
        let path = host == "akniga.org" ? "/search/books/" : "/search/"
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = host
        parts.path = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : path
        if parts.path != "/" { parts.queryItems = [URLQueryItem(name: "q", value: query)] }
        return parts.url.map { AudioWebCatalog(url: $0) }
    }
}

struct AudioWebCatalogScreen: UIViewControllerRepresentable {
    let url: URL
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color(hex: accentHex))
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        controller.preferredControlTintColor = UIColor(Color(hex: accentHex))
    }
}
