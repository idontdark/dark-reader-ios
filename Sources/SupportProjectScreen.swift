import SwiftUI
import UIKit

private enum CryptoWallet {
    static let ton = "UQCLaPSDXwk1Glt8R4hO1NWOxYfYWOve1c-tPd7zbbdbV9Wc"
    static let sol = "E9tnTc9f3xvfEgAuLkjkpmeXd4YJuunR19Ng4SMakRf2"
    static let evm = "0xE5F398f0E6C56BdA8b6Ee12f747F8Bbc5ce01e6c"
    static let btc = "bc1ps9fqremq6k7x9xk6dk3n3zdkl4zmpcej0gydxyce786843ge6a2s7qavdh"
    static let bch = "qr0jzwn7srluxpv9rj08ech27zkd6qx3fuaxwsa39v"
    static let ltc = "ltc1pst8faedkyszepqps9htfpazw9jntfs2a7qdee8zzxuzduurx9rls5qwnth"
    static let trx = "TUWBzRchtMNgGoSQPHMKo3JPCJb6oHuJr8"
}

private enum USDTNetwork: String, CaseIterable, Identifiable {
    case erc20, trc20, bep20, ton, sol
    var id: String { rawValue }
    var label: String {
        switch self {
        case .erc20: "ERC20 · Ethereum"
        case .trc20: "TRC20 · Tron"
        case .bep20: "BEP20 · BNB Chain"
        case .ton: "TON · The Open Network"
        case .sol: "SOL · Solana"
        }
    }
    var address: String {
        switch self {
        case .erc20, .bep20: CryptoWallet.evm
        case .trc20: CryptoWallet.trx
        case .ton: CryptoWallet.ton
        case .sol: CryptoWallet.sol
        }
    }
}

private struct CryptoCurrency: Identifiable {
    let name: String
    let network: String
    let code: String
    let address: String
    var id: String { code }
    static let all: [CryptoCurrency] = [
        .init(name: "TON", network: "The Open Network", code: "TON", address: CryptoWallet.ton),
        .init(name: "SOL", network: "Solana", code: "SOL", address: CryptoWallet.sol),
        .init(name: "ETH", network: "Ethereum", code: "ETH", address: CryptoWallet.evm),
        .init(name: "BTC", network: "Bitcoin", code: "BTC", address: CryptoWallet.btc),
        .init(name: "BCH", network: "Bitcoin Cash", code: "BCH", address: CryptoWallet.bch),
        .init(name: "LTC", network: "Litecoin", code: "LTC", address: CryptoWallet.ltc),
        .init(name: "TRX", network: "Tron", code: "TRX", address: CryptoWallet.trx),
        .init(name: "BNB", network: "BNB Smart Chain", code: "BNB", address: CryptoWallet.evm)
    ]
}

/// Native vector currency marks rendered sharp at any device resolution.
/// These symbols are purpose-drawn rather than system SF Symbols.
struct CryptoMark: View {
    let code: String
    var body: some View {
        ZStack {
            Circle().fill(background)
            symbol
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
        }
        .frame(width: 41, height: 41)
        .accessibilityHidden(true)
    }

    private var background: Color {
        switch code {
        case "USDT": Color(red: 0.11, green: 0.65, blue: 0.50)
        case "TON": Color(red: 0.02, green: 0.61, blue: 0.94)
        case "SOL": Color(red: 0.08, green: 0.11, blue: 0.18)
        case "ETH": Color(red: 0.37, green: 0.48, blue: 0.79)
        case "BTC": Color(red: 0.94, green: 0.60, blue: 0.13)
        case "BCH": Color(red: 0.21, green: 0.70, blue: 0.32)
        case "LTC": Color(red: 0.46, green: 0.51, blue: 0.60)
        case "TRX": Color(red: 0.92, green: 0.15, blue: 0.18)
        default: Color(red: 0.94, green: 0.70, blue: 0.12)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch code {
        case "USDT":
            Text("₮").font(.system(size: 28, weight: .bold))
        case "TON":
            Path { p in
                p.move(to: CGPoint(x: 2, y: 4))
                p.addLine(to: CGPoint(x: 23, y: 4))
                p.addLine(to: CGPoint(x: 12.5, y: 23))
                p.closeSubpath()
                p.move(to: CGPoint(x: 12.5, y: 23))
                p.addLine(to: CGPoint(x: 12.5, y: 8))
                p.move(to: CGPoint(x: 2, y: 4))
                p.addLine(to: CGPoint(x: 12.5, y: 8))
                p.addLine(to: CGPoint(x: 23, y: 4))
            }.stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        case "SOL":
            SolanaMark().fill(
                LinearGradient(colors: [.mint, .purple], startPoint: .leading, endPoint: .trailing)
            )
        case "ETH":
            EthereumMark().fill(.white)
        case "TRX":
            TronMark().stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        case "BNB":
            BNBMark().fill(.white)
        case "BCH", "BTC":
            Text("₿").font(.system(size: 28, weight: .bold))
        case "LTC":
            Text("Ł").font(.system(size: 28, weight: .bold))
        default:
            Text("◆")
        }
    }
}

private struct SolanaMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let y = CGFloat(i) * 8 + 3
            let shift: CGFloat = i == 1 ? 4 : 0
            p.move(to: CGPoint(x: shift, y: y))
            p.addLine(to: CGPoint(x: 21 + shift - 4, y: y))
            p.addLine(to: CGPoint(x: 25 - shift, y: y + 5))
            p.addLine(to: CGPoint(x: 4 - shift + 4, y: y + 5))
            p.closeSubpath()
        }
        return p
    }
}

private struct EthereumMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 12.5, y: 0))
        p.addLine(to: CGPoint(x: 1, y: 14))
        p.addLine(to: CGPoint(x: 12.5, y: 18))
        p.addLine(to: CGPoint(x: 24, y: 14))
        p.closeSubpath()
        p.move(to: CGPoint(x: 1, y: 16))
        p.addLine(to: CGPoint(x: 12.5, y: 25))
        p.addLine(to: CGPoint(x: 24, y: 16))
        p.addLine(to: CGPoint(x: 12.5, y: 20))
        p.closeSubpath()
        return p
    }
}

private struct TronMark: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 3))
            p.addLine(to: CGPoint(x: 24, y: 7))
            p.addLine(to: CGPoint(x: 12, y: 24))
            p.closeSubpath()
            p.move(to: CGPoint(x: 1, y: 3))
            p.addLine(to: CGPoint(x: 9, y: 10))
            p.addLine(to: CGPoint(x: 24, y: 7))
            p.move(to: CGPoint(x: 9, y: 10))
            p.addLine(to: CGPoint(x: 12, y: 24))
        }
    }
}

private struct BNBMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func diamond(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
            p.move(to: CGPoint(x: x, y: y - size))
            p.addLine(to: CGPoint(x: x + size, y: y))
            p.addLine(to: CGPoint(x: x, y: y + size))
            p.addLine(to: CGPoint(x: x - size, y: y))
            p.closeSubpath()
        }
        diamond(12.5, 3.5, 3.5)
        diamond(4, 12, 3.5)
        diamond(21, 12, 3.5)
        diamond(12.5, 20.5, 3.5)
        diamond(12.5, 12, 5)
        return p
    }
}

private struct WalletRow: View {
    let name: String
    let code: String
    let address: String
    let copy: () -> Void

    var body: some View {
        Button(action: copy) {
            VStack(spacing: 11) {
                HStack(spacing: 12) {
                    CryptoMark(code: code)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                Text(address)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Скопировать адрес \(name)")
    }
}

struct SupportProjectScreen: View {
    @State private var network: USDTNetwork = .erc20
    @State private var copied: String?
    @State private var revision = 0
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Поддержать проект")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Dark Reader бесплатный. Если приложение полезно, вы можете поддержать его развитие.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "USDT")
                    ReaderCard {
                        HStack {
                            CryptoMark(code: "USDT")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tether USDT").font(.headline)
                                Text("Выберите сеть перевода")
                                    .font(.caption).foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .padding(.bottom, 14)
                        Picker("Сеть", selection: $network) {
                            ForEach(USDTNetwork.allCases) { item in
                                Text(item.rawValue.uppercased()).tag(item)
                            }
                        }
                        .tint(Color(hex: accentHex))
                        .padding(.bottom, 8)
                        ReaderDivider()
                        WalletRow(name: "USDT", code: "USDT",
                                  address: network.address) {
                            copyAddress(network.address, label: "USDT")
                        }
                    }
                    Label("Проверьте сеть перед отправкой. Перевод USDT через другую сеть может привести к потере средств.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.horizontal, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Другие криптовалюты")
                    ReaderCard {
                        ForEach(CryptoCurrency.all) { currency in
                            WalletRow(name: currency.name, code: currency.code, address: currency.address) {
                                copyAddress(currency.address, label: currency.name)
                            }
                            if currency.code != CryptoCurrency.all.last?.code {
                                ReaderDivider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .navigationTitle("Поддержать проект")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let copied {
                Label("Адрес \(copied) скопирован", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(ReaderStyle.raised, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
    }

    private func copyAddress(_ address: String, label: String) {
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        revision += 1
        let current = revision
        withAnimation(.easeInOut(duration: 0.15)) { copied = label }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard current == revision else { return }
            withAnimation(.easeInOut(duration: 0.15)) { copied = nil }
        }
    }
}
