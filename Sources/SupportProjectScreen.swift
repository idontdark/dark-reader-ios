import SwiftUI
import UIKit

// Wallet addresses are provided by the developer. Keep these complete strings
// unchanged: the visible text can truncate, but the pasteboard must not.
private enum SupportAddresses {
    static let ton = "UQCLaPSDXwk1Glt8R4hO1NWOxYfYWOve1c-tPd7zbbdbV9Wc"
    static let sol = "E9tnTc9f3xvfEgAuLkjkpmeXd4YJuunR19Ng4SMakRf2"
    static let evm = "0xE5F398f0E6C56BdA8b6Ee12f747F8Bbc5ce01e6c"
    static let btc = "bc1ps9fqremq6k7x9xk6dk3n3zdkl4zmpcej0gydxyce786843ge6a2s7qavdh"
    static let bch = "qr0jzwn7srluxpv9rj08ech27zkd6qx3fuaxwsa39v"
    static let ltc = "ltc1pst8faedkyszepqps9htfpazw9jntfs2a7qdee8zzxuzduurx9rls5qwnth"
    static let tron = "TUWBzRchtMNgGoSQPHMKo3JPCJb6oHuJr8"
}

private enum USDTNetwork: String, CaseIterable, Identifiable {
    case erc20, trc20, bep20, ton, sol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .erc20: "ERC20 · Ethereum"
        case .trc20: "TRC20 · Tron"
        case .bep20: "BEP20 · BNB Smart Chain"
        case .ton: "TON · The Open Network"
        case .sol: "SOL · Solana"
        }
    }

    var name: String {
        switch self {
        case .erc20: "USDT ERC20"
        case .trc20: "USDT TRC20"
        case .bep20: "USDT BEP20"
        case .ton: "USDT TON"
        case .sol: "USDT SOL"
        }
    }

    var address: String {
        switch self {
        case .erc20, .bep20: SupportAddresses.evm
        case .trc20: SupportAddresses.tron
        case .ton: SupportAddresses.ton
        case .sol: SupportAddresses.sol
        }
    }
}

private struct SupportCurrency: Identifiable {
    let id: String
    let subtitle: String
    let symbol: String
    let color: Color
    let address: String

    static let all: [SupportCurrency] = [
        .init(id: "TON", subtitle: "The Open Network", symbol: "◇", color: .cyan, address: SupportAddresses.ton),
        .init(id: "SOL", subtitle: "Solana", symbol: "◎", color: .mint, address: SupportAddresses.sol),
        .init(id: "ETH", subtitle: "Ethereum", symbol: "Ξ", color: .indigo, address: SupportAddresses.evm),
        .init(id: "BTC", subtitle: "Bitcoin", symbol: "₿", color: .orange, address: SupportAddresses.btc),
        .init(id: "BCH", subtitle: "Bitcoin Cash", symbol: "₿", color: .green, address: SupportAddresses.bch),
        .init(id: "LTC", subtitle: "Litecoin", symbol: "Ł", color: .gray, address: SupportAddresses.ltc),
        .init(id: "TRX", subtitle: "Tron", symbol: "T", color: .red, address: SupportAddresses.tron),
        .init(id: "BNB", subtitle: "BNB Smart Chain", symbol: "◆", color: .yellow, address: SupportAddresses.evm)
    ]
}

/// A native, compact button. The address is truncated visually only.
private struct WalletCopyRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let address: String
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 12) {
                Text(symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Скопировать адрес \(title), сеть \(subtitle)")
        .accessibilityHint("Полный адрес будет скопирован в буфер обмена")
    }
}

struct SupportProjectScreen: View {
    @State private var selectedNetwork: USDTNetwork = .erc20
    @State private var copiedLabel: String?
    @State private var copyRevision = 0

    var body: some View {
        Form {
            Section {
                Text("Спасибо, что помогаете развивать Dark Reader. Выберите валюту и коснитесь адреса, чтобы скопировать его полностью.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Сеть USDT", selection: $selectedNetwork) {
                    ForEach(USDTNetwork.allCases) { network in
                        Text(network.title).tag(network)
                    }
                }
                .pickerStyle(.navigationLink)

                WalletCopyRow(
                    title: selectedNetwork.name,
                    subtitle: selectedNetwork.title,
                    symbol: "₮",
                    tint: .green,
                    address: selectedNetwork.address
                ) {
                    copyAddress(selectedNetwork.address, label: selectedNetwork.name)
                }
            } header: {
                Text("USDT")
            } footer: {
                Text("Убедитесь, что сеть отправления совпадает с выбранной: ERC20 — Ethereum, TRC20 — Tron, BEP20 — BNB Smart Chain, TON — TON, SOL — Solana. Перевод через другую сеть может привести к потере средств.")
            }

            Section("Другие криптовалюты") {
                ForEach(SupportCurrency.all) { currency in
                    WalletCopyRow(
                        title: currency.id,
                        subtitle: currency.subtitle,
                        symbol: currency.symbol,
                        tint: currency.color,
                        address: currency.address
                    ) {
                        copyAddress(currency.address, label: currency.id)
                    }
                }
            }
        }
        .navigationTitle("Поддержать проект")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let copiedLabel {
                Label("Адрес \(copiedLabel) скопирован", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 5, y: 2)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func copyAddress(_ address: String, label: String) {
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copyRevision += 1
        let currentRevision = copyRevision
        withAnimation(.easeInOut(duration: 0.2)) { copiedLabel = label }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard currentRevision == copyRevision else { return }
            withAnimation(.easeInOut(duration: 0.2)) { copiedLabel = nil }
        }
    }
}
