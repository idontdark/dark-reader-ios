import SwiftUI

/// One-time, skippable setup. Changing preferences later never replays this flow.
struct OnboardingFlow: View {
    let finish: () -> Void

    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("catalogProvider") private var catalogProvider = "flibusta"
    @AppStorage("wantsBooks") private var wantsBooks = true
    @AppStorage("wantsAudiobooks") private var wantsAudio = false
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    @State private var step = 0
    @State private var authorQuery = ""
    @FocusState private var authorFocused: Bool

    private var english: Bool { language == "en" }
    private var genres: [String] { ReaderPreferences.array(genresJSON) }
    private var authors: [String] { ReaderPreferences.array(authorsJSON) }

    var body: some View {
        ZStack {
            ReaderStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        introduction
                        switch step {
                        case 0: languageChoices
                        case 1: contentChoices
                        case 2: genreChoices
                        case 3: authorChoices
                        default: completion
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                footer
            }
            .padding(.horizontal, 22)
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: language))
    }

    private var header: some View {
        VStack(spacing: 22) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color(hex: accentHex))
                Text("Dark Reader")
                    .font(.headline)
                Spacer()
                if step < 4 {
                    Button(english ? "Skip" : "Пропустить") {
                        authorFocused = false
                        withAnimation(.easeInOut(duration: 0.18)) { step += 1 }
                    }
                    .font(.subheadline)
                    .foregroundStyle(ReaderStyle.secondary)
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(index <= step ? Color(hex: accentHex) : ReaderStyle.raised)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }
            HStack {
                Text(english ? "STEP \(step + 1) OF 5" : "ШАГ \(step + 1) ИЗ 5")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(ReaderStyle.secondary)
                Spacer()
            }
        }
        .padding(.top, 20)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ReaderStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch step {
        case 0: english ? "Choose your language" : "Выберите язык"
        case 1: english ? "What do you enjoy?" : "Что вам нравится?"
        case 2: english ? "Favorite genres" : "Любимые жанры"
        case 3: english ? "Favorite authors" : "Любимые авторы"
        default: english ? "You're all set" : "Всё готово"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: english ? "You can change it later in Settings." : "Язык можно изменить в настройках."
        case 1: english ? "Choose one or both options." : "Можно выбрать оба варианта."
        case 2: english ? "Pick the genres you enjoy. This step is optional." : "Отметьте интересные жанры. Это необязательно."
        case 3: english ? "Save your authors to find their books faster." : "Сохраняйте авторов, чтобы быстро находить их книги."
        default: english ? "All set. Find a book or an audiobook." :
            "Всё готово. Выберите книгу или аудиозапись."
        }
    }

    private var languageChoices: some View {
        VStack(spacing: 11) {
            languageRow("ru", "🇷🇺", "Русский")
            languageRow("en", "🇬🇧", "English")
        }
    }

    private func languageRow(_ key: String, _ emoji: String, _ name: String) -> some View {
        Button {
            language = key
            // Automatically suggest English or Russian for public-domain catalogs,
            // while keeping catalog language separately adjustable in Settings.
            if catalogProvider == "flibusta" || catalogProvider == "gutendex" {
                catalogProvider = key == "en" ? "gutendex" : "flibusta"
            }
        } label: {
            HStack(spacing: 14) {
                Text(emoji).font(.title)
                Text(name).font(.headline).foregroundStyle(.white)
                Spacer()
                Image(systemName: language == key ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(language == key ? Color(hex: accentHex) : ReaderStyle.secondary)
                    .font(.title3)
            }
            .padding(17)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(
                language == key ? Color(hex: accentHex) : ReaderStyle.line,
                lineWidth: language == key ? 1.6 : 1))
        }
        .buttonStyle(.plain)
    }

    private var contentChoices: some View {
        VStack(spacing: 12) {
            choiceRow(icon: "book.closed", title: english ? "Read books" : "Читать книги",
                      caption: english ? "Your EPUB library and offline reading" : "EPUB и офлайн-чтение",
                      selected: wantsBooks) {
                if wantsBooks && !wantsAudio { return }
                wantsBooks.toggle()
            }
            choiceRow(icon: "headphones", title: english ? "Listen to audiobooks" : "Слушать аудиокниги",
                      caption: english ? "Find and listen to free audiobooks" :
                            "Каталог, главы и офлайн-прослушивание",
                      selected: wantsAudio) {
                if wantsAudio && !wantsBooks { return }
                wantsAudio.toggle()
            }
        }
    }

    private func choiceRow(icon: String, title: String, caption: String,
                           selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: accentHex))
                    .frame(width: 42, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(caption).font(.caption).foregroundStyle(ReaderStyle.secondary)
                }
                Spacer(minLength: 2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color(hex: accentHex) : ReaderStyle.secondary)
            }
            .padding(14)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(
                selected ? Color(hex: accentHex).opacity(0.7) : ReaderStyle.line))
        }
        .buttonStyle(.plain)
    }

    private var genreChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(ReaderPreferences.genres, id: \.id) { item in
                let picked = genres.contains(item.id)
                Button {
                    var current = genres
                    if picked { current.removeAll { $0 == item.id } }
                    else { current.append(item.id) }
                    genresJSON = ReaderPreferences.encode(current)
                } label: {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Image(systemName: item.icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: accentHex))
                            Spacer()
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked ? Color(hex: accentHex) : ReaderStyle.secondary)
                        }
                        Text(ReaderPreferences.genreName(item.id, language: language))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(15)
                    .frame(height: 105)
                    .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                        picked ? Color(hex: accentHex) : ReaderStyle.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var authorChoices: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ReaderStyle.secondary)
                TextField(english ? "Add an author" : "Добавить автора", text: $authorQuery)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($authorFocused)
                    .onSubmit(addCustom)
                Button { addCustom() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: accentHex))
                }
                .disabled(authorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 14))

            let sample = language == "en" ? ReaderPreferences.suggestedAuthorsEN :
                ReaderPreferences.suggestedAuthorsRU
            ForEach(sample, id: \.self) { author in
                let picked = authors.contains(author)
                Button {
                    var list = authors
                    if picked { list.removeAll { $0 == author } }
                    else { list.append(author) }
                    authorsJSON = ReaderPreferences.encode(list)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color(hex: accentHex))
                            .font(.title2)
                        Text(author)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(Color(hex: accentHex))
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
                    .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addCustom() {
        let value = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return }
        if !authors.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
            authorsJSON = ReaderPreferences.encode(authors + [value])
        }
        authorQuery = ""
        authorFocused = false
    }

    private var completion: some View {
        VStack(spacing: 22) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 65, weight: .ultraLight))
                .foregroundStyle(Color(hex: accentHex))
                .padding(35)
                .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 23))
            VStack(spacing: 12) {
                Label(english ? "Reading without the internet" : "Читайте без интернета",
                      systemImage: "checkmark.circle.fill")
                Label(english ? "Your own library" : "Ваша библиотека",
                      systemImage: "checkmark.circle.fill")
                Label(english ? "Save favorite authors" : "Любимые авторы всегда под рукой",
                      systemImage: "checkmark.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(ReaderStyle.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(19)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 15))
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                if step > 0 {
                    Button {
                        authorFocused = false
                        withAnimation(.easeInOut(duration: 0.18)) { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 47, height: 48)
                            .foregroundStyle(.white)
                            .background(ReaderStyle.raised, in: RoundedRectangle(cornerRadius: 13))
                    }
                }
                PurpleAction(
                    title: step == 4
                        ? (english ? "Start reading" : "Начать чтение")
                        : (english ? "Continue" : "Продолжить"),
                    icon: step == 4 ? "book" : "arrow.right"
                ) {
                    authorFocused = false
                    if step == 4 {
                        finish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { step += 1 }
                    }
                }
            }
            if step == 0 {
                Text(english ? "Language can be changed in Settings." : "Язык можно изменить в настройках.")
                    .font(.caption)
                    .foregroundStyle(ReaderStyle.secondary)
            }
        }
        .padding(.vertical, 15)
    }
}
