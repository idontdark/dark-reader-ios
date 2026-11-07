import SwiftUI
import UIKit

enum ReaderStyle {
    static let background = Color(red: 11/255, green: 10/255, blue: 19/255)
    static let surface = Color(red: 28/255, green: 26/255, blue: 42/255)
    static let raised = Color(red: 37/255, green: 33/255, blue: 53/255)
    static let line = Color.white.opacity(0.095)
    static let secondary = Color(red: 170/255, green: 166/255, blue: 187/255)
    static let defaultAccent = "#8755E8"
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        let value = UInt64(cleaned, radix: 16) ?? 0x8755E8
        if cleaned.count == 8 {
            self.init(.sRGB,
                      red: Double((value >> 24) & 255) / 255,
                      green: Double((value >> 16) & 255) / 255,
                      blue: Double((value >> 8) & 255) / 255,
                      opacity: Double(value & 255) / 255)
        } else {
            self.init(.sRGB,
                      red: Double((value >> 16) & 255) / 255,
                      green: Double((value >> 8) & 255) / 255,
                      blue: Double(value & 255) / 255,
                      opacity: 1)
        }
    }

    var hexRGB: String {
        let color = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return ReaderStyle.defaultAccent
        }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

struct ReaderCanvas: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ReaderStyle.background.ignoresSafeArea()
            }
            .scrollContentBackground(.hidden)
    }
}

extension View {
    func readerCanvas() -> some View { modifier(ReaderCanvas()) }
}

struct ReaderCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(ReaderStyle.line))
    }
}

struct ReaderHeader: View {
    let title: String
    let trailingIcon: String?
    let trailingAction: (() -> Void)?
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "book.closed.fill")
                    .font(.body)
                    .foregroundStyle(Color(hex: accentHex))
                Text("Dark Reader")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if let trailingIcon, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 39, height: 39)
                            .background(ReaderStyle.raised, in: Circle())
                    }
                    .accessibilityLabel(title == "Библиотека" ? "Добавить книгу" : "Дополнительно")
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 10)
            Text(LocalizedStringKey(title))
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }
}

struct BookArtwork: View {
    let title: String
    let author: String
    var coverURL: URL? = nil
    var width: CGFloat = 68
    var height: CGFloat = 96

    var body: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.18)))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.33, green: 0.26, blue: 0.39),
                         Color(red: 0.12, green: 0.16, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 9) {
                Image(systemName: "book.closed")
                    .font(.system(size: width * 0.32, weight: .ultraLight))
                Text(title)
                    .font(.system(size: max(8, width * 0.145), weight: .medium, design: .serif))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Text(author.components(separatedBy: " ").first ?? "")
                    .font(.system(size: max(7, width * 0.11)))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(7)
        }
    }
}

struct PurpleAction: View {
    let title: String
    var icon: String = "arrow.right"
    let action: () -> Void
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .foregroundStyle(.white)
                .background(Color(hex: accentHex), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(LocalizedStringKey(text.uppercased()))
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(ReaderStyle.secondary)
    }
}

struct ReaderRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Content
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color(hex: accentHex))
                .frame(width: 29)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).foregroundStyle(.white)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.footnote).foregroundStyle(ReaderStyle.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct ReaderDivider: View {
    var body: some View {
        Rectangle().fill(ReaderStyle.line).frame(height: 0.5)
    }
}
