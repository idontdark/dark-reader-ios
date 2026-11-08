import SwiftUI

extension View {
    func readerHint(isPresented: Binding<Bool>, title: String, message: String, icon: String) -> some View {
        modifier(ReaderHint(presented: isPresented, title: title, message: message, icon: icon))
    }
    func readerError(_ message: Binding<String?>, title: String) -> some View {
        readerHint(isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
                   title: title, message: L10n.render(message.wrappedValue ?? ""), icon: "exclamationmark.circle")
    }
}

private struct ReaderHint: ViewModifier {
    @Binding var presented: Bool
    let title: String
    let message: String
    let icon: String
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if presented {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon).font(.title3).foregroundStyle(Color(hex: accentHex)).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: L10n.text(title, language: language)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text(verbatim: L10n.text(message, language: language)).font(.footnote).foregroundStyle(ReaderStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                    Button { presented = false } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(ReaderStyle.secondary).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: L10n.text("Закрыть подсказку", language: language)))
                }.padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 14)
                    .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ReaderStyle.line, lineWidth: 0.8))
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: presented)
    }
}
