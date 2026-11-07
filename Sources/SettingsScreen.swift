import SwiftUI

struct SettingsScreen: View {
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("appLanguage") private var language = "ru"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ReaderHeader(title: "Настройки", trailingIcon: nil, trailingAction: nil)

                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(text: "Оформление")
                        ReaderCard {
                            NavigationLink {
                                AppearanceScreen()
                            } label: {
                                ReaderRow(icon: "paintpalette", title: "Тема и цвета",
                                          subtitle: "Стиль ipa_dark, HEX и фон") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            ReaderDivider()
                            NavigationLink {
                                TypographyScreen()
                            } label: {
                                ReaderRow(icon: "textformat.size", title: "Настройки чтения",
                                          subtitle: "Шрифт, размер и прокрутка") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(text: "Предпочтения")
                        ReaderCard {
                            NavigationLink { LanguageSettingsScreen() } label: {
                                ReaderRow(icon: "globe", title: "Язык приложения",
                                          subtitle: language == "en" ? "English" : "Русский") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }.buttonStyle(.plain)
                            ReaderDivider()
                            NavigationLink { InterestsScreen() } label: {
                                ReaderRow(icon: "slider.horizontal.3", title: "Мои интересы",
                                          subtitle: "Жанры, книги и аудиокниги") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }.buttonStyle(.plain)
                            ReaderDivider()
                            NavigationLink { FavoriteAuthorsScreen() } label: {
                                ReaderRow(icon: "person.2", title: "Любимые авторы",
                                          subtitle: nil) {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(text: "Библиотека")
                        ReaderCard {
                            NavigationLink {
                                CloudSyncScreen()
                            } label: {
                                ReaderRow(icon: "icloud", title: "Синхронизация iCloud",
                                          subtitle: "Книги, закладки и прогресс") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            ReaderDivider()
                            NavigationLink {
                                CustomOPDSCatalogsScreen()
                            } label: {
                                ReaderRow(icon: "network", title: "Каталоги",
                                          subtitle: "Ваши OPDS-библиотеки") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            ReaderDivider()
                            NavigationLink {
                                ImportTutorialScreen()
                            } label: {
                                ReaderRow(icon: "questionmark.circle", title: "Как добавить книгу",
                                          subtitle: "Импорт через Файлы и Safari") {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(text: "О приложении")
                        ReaderCard {
                            NavigationLink {
                                SupportProjectScreen()
                            } label: {
                                ReaderRow(icon: "heart", title: "Поддержать проект",
                                          subtitle: nil) {
                                    Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            ReaderDivider()
                            Link(destination: URL(string: "https://t.me/ipa_dark")!) {
                                ReaderRow(icon: "paperplane", title: "Разработчик",
                                          subtitle: "t.me/ipa_dark") {
                                    Image(systemName: "arrow.up.right").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Dark Reader · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0")")
                        .font(.caption)
                        .foregroundStyle(ReaderStyle.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct AppearanceScreen: View {
    @EnvironmentObject private var sync: CloudSyncManager
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("appAppearance") private var appearance = "dark"
    @AppStorage("readerBackgroundHex") private var readerBackgroundHex = "#101018"
    @State private var customColor = Color(hex: ReaderStyle.defaultAccent)
    @State private var hexText = ReaderStyle.defaultAccent
    @FocusState private var editingHex: Bool

    private let swatches = ["#8755E8", "#4178E8", "#2AAF91", "#E65A73", "#EAA344", "#B2B2B9"]
    private var chosenAccent: Color { Color(hex: accentHex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                SectionLabel(text: "Приложение")
                ReaderCard {
                    HStack {
                        Text("Тема приложения")
                        Spacer()
                        Picker("Тема", selection: $appearance) {
                            Text("Тёмная").tag("dark")
                            Text("Светлая").tag("light")
                            Text("Системная").tag("system")
                        }
                        .tint(chosenAccent)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Цвет интерфейса")
                    ReaderCard {
                        Text("Фирменный фиолетовый выбран по умолчанию.")
                            .font(.footnote)
                            .foregroundStyle(ReaderStyle.secondary)
                        HStack(spacing: 12) {
                            ForEach(swatches, id: \.self) { hex in
                                Button {
                                    accentHex = hex
                                    customColor = Color(hex: hex)
                                    hexText = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if accentHex == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Выбрать цвет \(hex)")
                            }
                        }
                        .padding(.vertical, 15)

                        ReaderDivider()

                        ColorPicker("Палитра цветов", selection: $customColor, supportsOpacity: false)
                            .padding(.vertical, 13)
                            .onChange(of: customColor) { _, value in
                                let hex = value.hexRGB
                                accentHex = hex
                                hexText = hex
                            }
                        ReaderDivider()

                        HStack(spacing: 10) {
                            Text("HEX").font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                            TextField("#8755E8", text: $hexText)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($editingHex)
                                .onSubmit { applyHEX() }
                                .foregroundStyle(.white)
                            Button("Применить") { applyHEX() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(chosenAccent)
                                .disabled(!isValidHex)
                        }
                        .padding(.vertical, 13)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Предпросмотр")
                    ReaderCard {
                        Text("Моя библиотека")
                            .font(.headline)
                        HStack {
                            Image(systemName: "book.closed")
                                .foregroundStyle(chosenAccent)
                            Text("Книга для чтения")
                                .font(.subheadline)
                            Spacer()
                            Text("68%").foregroundStyle(ReaderStyle.secondary)
                        }
                        .padding(.vertical, 10)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule().fill(chosenAccent).frame(width: g.size.width * 0.68)
                            }
                        }
                        .frame(height: 5)
                    }
                }

                ReaderCard {
                    HStack {
                        Text("Вернуть цвет ipa_dark")
                        Spacer()
                        Button("Сбросить") {
                            accentHex = ReaderStyle.defaultAccent
                            customColor = Color(hex: accentHex)
                            hexText = accentHex
                        }
                        .font(.subheadline)
                        .foregroundStyle(chosenAccent)
                    }
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customColor = Color(hex: accentHex)
            hexText = accentHex
        }
        .onChange(of: accentHex) { _, value in
            sync.settingsChanged(key: "accentHex", value: value)
        }
        .onChange(of: appearance) { _, value in
            sync.settingsChanged(key: "appAppearance", value: value)
        }
    }

    private var isValidHex: Bool {
        let trimmed = hexText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        return trimmed.count == 6 && UInt32(trimmed, radix: 16) != nil
    }

    private func applyHEX() {
        guard isValidHex else { return }
        let hex = "#" + hexText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "").uppercased()
        accentHex = hex
        customColor = Color(hex: hex)
        hexText = hex
        editingHex = false
    }
}

struct TypographyScreen: View {
    @EnvironmentObject private var sync: CloudSyncManager
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerScroll") private var scroll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                SectionLabel(text: "Читалка")
                ReaderCard {
                    HStack {
                        Text("Тема страницы")
                        Spacer()
                        Picker("Тема страницы", selection: $theme) {
                            Text("Системная").tag("system")
                            Text("Светлая").tag("light")
                            Text("Тёмная").tag("dark")
                            Text("Сепия").tag("sepia")
                            Text("OLED").tag("oled")
                        }.tint(.white)
                    }
                    ReaderDivider()
                    HStack {
                        Text("Шрифт")
                        Spacer()
                        Picker("Шрифт", selection: $font) {
                            Text("С засечками").tag("serif")
                            Text("Без засечек").tag("sans")
                        }.tint(.white)
                    }
                    ReaderDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Размер текста")
                            Spacer()
                            Text("\(Int(fontSize * 100))%").foregroundStyle(ReaderStyle.secondary)
                        }
                        Slider(value: $fontSize, in: 0.7...3.0, step: 0.1)
                    }.padding(.vertical, 11)
                    ReaderDivider()
                    Toggle("Вертикальная прокрутка", isOn: $scroll)
                        .padding(.vertical, 12)
                }
                Text("Настройки применяются при чтении. Скачанные книги остаются в том формате, в котором были добавлены.")
                    .font(.footnote).foregroundStyle(ReaderStyle.secondary)
            }.padding(20)
        }
        .readerCanvas()
        .navigationTitle("Чтение")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: theme) { _, value in sync.settingsChanged(key: "readerTheme", value: value) }
        .onChange(of: font) { _, value in sync.settingsChanged(key: "readerFont", value: value) }
        .onChange(of: fontSize) { _, value in sync.settingsChanged(key: "readerFontSize", value: String(value)) }
        .onChange(of: scroll) { _, value in sync.settingsChanged(key: "readerScroll", value: String(value)) }
    }
}

