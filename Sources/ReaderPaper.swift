import SwiftUI

@MainActor final class ReaderChrome: ObservableObject {
    @Published var visible=false
}

struct ReaderPaper {
    let theme:String
    var dark:Bool {theme == "dark" || theme == "oled"}
    var backgroundHex:String {
        switch theme {
        case "sepia":"#F5EAD1"
        case "dark":"#1C1C1E"
        case "oled":"#000000"
        default:"#FAFAF7"
        }
    }
    var textHex:String {dark ? "#F2F2F2":"#1C1C1E"}
    var background:SwiftUI.Color {SwiftUI.Color(hex:backgroundHex)}
    var text:SwiftUI.Color {SwiftUI.Color(hex:textHex)}
}
