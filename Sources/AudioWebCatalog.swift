import SwiftUI
import SafariServices
import UIKit

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
