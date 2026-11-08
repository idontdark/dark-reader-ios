import SwiftUI

/// One-time, skippable setup. Changing preferences later never replays this flow.
struct OnboardingFlow: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let finish: () -> Void

    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("catalogProvider") private var catalogProvider = "flibusta"
    @AppStorage("wantsBooks") private var wantsBooks = true
    @AppStorage("wantsAudiobooks") private var wantsAudio = false
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("favoriteBooksJSON") private var favoriteBooksJSON = "[]"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    @State private var step = 0
    @State private var bookSuggestions: [DiscoveryBook] = []
    @State private var loadingSuggestions = false
    @State private var suggestionError: String?

    private var english: Bool { language == "en" }
    private var genres: [String] { ReaderPreferences.array(genresJSON) }
    private var favoriteBooks: [DiscoveryBook] { DiscoveryService.saved(favoriteBooksJSON) }

    var body: some View {
        ZStack {
            ReaderStyle.background.ignoresSafeArea()
            if step == 0 { languageLanding }
            else { VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        introduction
                        switch step {
                        case 0: languageChoices
                        case 1: contentChoices
                        case 2: genreChoices
                        case 3: bookChoices
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
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: language))
        .task(id: "\(step)-\(genresJSON)-\(language)") {
            if step == 3 { await loadBookSuggestions() }
        }
    }

    private var languageLanding: some View {
        ZStack(alignment:.bottom) {
            RadialGradient(colors:[Color(hex:accentHex).opacity(0.13),.clear],center:UnitPoint(x:0.5,y:0.24),
                           startRadius:12,endRadius:240).ignoresSafeArea()
            FooterWaves().frame(height:118).ignoresSafeArea(edges:.bottom)
            VStack(spacing:0) {
                Spacer(minLength:22).frame(maxHeight:55)
                BrandBook(width:150).shadow(color:Color(hex:accentHex).opacity(0.32),radius:18)
                Text("Dark Reader").font(.system(size:30,weight:.bold)).tracking(-0.8).padding(.top,10)
                Text(verbatim:L10n.render(english ? "Books and Audiobooks" : "Книги и Аудиокниги",language:localizationLanguage))
                    .font(.system(size:14,weight:.medium)).foregroundStyle(Color.white.opacity(0.87)).padding(.top,5)
                VStack(alignment:.leading,spacing:0) {
                    HStack(spacing:10) {
                        Image(systemName:"globe").font(.system(size:21,weight:.light)).foregroundStyle(Color(hex:"#C4B2D6"))
                        Text(verbatim:L10n.render(english ? "Choose your language" : "Выберите язык",language:localizationLanguage)).font(.system(size:15,weight:.semibold))
                    }.padding(.bottom,17)
                    landingLanguage("ru","🇷🇺","Русский")
                    landingLanguage("en","🇬🇧","English").padding(.top,8)
                    Text(verbatim:L10n.render(english ? "You can change it later in Settings." : "Язык можно изменить в настройках.",language:localizationLanguage))
                        .font(.system(size:10)).foregroundStyle(ReaderStyle.secondary.opacity(0.7)).padding(.top,12)
                }.padding(15).background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:14))
                    .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color(hex:"#756085").opacity(0.35),lineWidth:0.8))
                    .padding(.top,34)
                Spacer(minLength:30)
                PurpleAction(title:english ? "Continue" : "Продолжить",icon:"",height:47) {
                    withAnimation(.easeInOut(duration:0.2)) { step=1 }
                }.padding(.bottom,19)
            }.padding(.horizontal,25)
        }.foregroundStyle(.white)
    }
    private func landingLanguage(_ code:String,_ flag:String,_ name:String)->some View {
        Button {
            language=code
            bookLanguage=code
            catalogProvider=code == "en" ? "gutendex":"flibusta"
            UserDefaults.standard.set(code == "ru" ? AudioSource.archive.rawValue:AudioSource.librivox.rawValue,forKey:"preferredAudioSource")
        } label: {
            HStack(spacing:12) {
                Text(flag).font(.system(size:26))
                Text(name).font(.system(size:16,weight:.medium))
                Spacer()
                if language == code { Image(systemName:"checkmark").font(.system(size:18,weight:.semibold)) }
            }.foregroundStyle(.white).padding(.horizontal,12).frame(height:53)
                .background(Color.white.opacity(language == code ? 0.06:0.025),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(
                    language == code ? Color(hex:"#C574FF"):Color.white.opacity(0.045),lineWidth:language == code ? 1.5:0.8))
        }.buttonStyle(.plain)
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
                Text(verbatim:L10n.render(english ? "STEP \(step + 1) OF 5" : "ШАГ \(step + 1) ИЗ 5",language:localizationLanguage))
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
                .font(.system(size: 27, weight: .bold))
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
        case 3: english ? "Choose books" : "Выберите книги"
        default: english ? "You're all set" : "Всё готово"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: english ? "You can change it later in Settings." : "Язык можно изменить в настройках."
        case 1: english ? "Choose one or both options." : "Можно выбрать оба варианта."
        case 2: english ? "Pick the genres you enjoy. This step is optional." : "Отметьте интересные жанры. Это необязательно."
        case 3: english ? "Pick stories you like. We will use your choices for recommendations." : "Отметьте интересные книги. Мы учтём ваш выбор в рекомендациях."
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
            bookLanguage = key
            UserDefaults.standard.set(key == "ru" ? AudioSource.archive.rawValue : AudioSource.librivox.rawValue, forKey: "preferredAudioSource")
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

    private var bookChoices: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loadingSuggestions && bookSuggestions.isEmpty {
                HStack(spacing: 11) {
                    ProgressView().tint(Color(hex: accentHex))
                    Text(verbatim:L10n.render(english ? "Finding books with covers…" : "Подбираем книги с обложками…",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                .padding(.vertical, 18)
            } else if bookSuggestions.isEmpty {
                ReaderCard {
                    Text(verbatim:L10n.render(suggestionError ?? (english ? "No books available yet." : "Подборка пока недоступна."),language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                    Button(english ? "Try again" : "Повторить") {
                        Task { await loadBookSuggestions() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hex: accentHex))
                    .padding(.top, 10)
                }
            } else {
                Text(verbatim:L10n.render(english ? "Real titles and covers from Open Library" :
                    "Реальные книги и обложки из Open Library",language:localizationLanguage))
                    .font(.caption)
                    .foregroundStyle(ReaderStyle.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)], spacing: 17) {
                    ForEach(bookSuggestions) { book in
                        let picked = favoriteBooks.contains(where: { $0.id == book.id })
                        Button { toggleBook(book) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    DiscoveryArtwork(book: book, width: 133, height: 175)
                                        .frame(maxWidth: .infinity)
                                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(picked ? Color(hex: accentHex) : .white)
                                        .padding(9)
                                }
                                Text(book.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text(book.author)
                                    .font(.caption2)
                                    .foregroundStyle(ReaderStyle.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(book.title)
                    }
                }
            }
        }
    }

    private func toggleBook(_ book: DiscoveryBook) {
        var selected = favoriteBooks
        if selected.contains(where: { $0.id == book.id }) {
            selected.removeAll { $0.id == book.id }
        } else {
            selected.append(book)
        }
        favoriteBooksJSON = DiscoveryService.encode(selected)
    }

    private func loadBookSuggestions() async {
        loadingSuggestions = true
        suggestionError = nil
        defer { loadingSuggestions = false }
        do {
            bookSuggestions = try await DiscoveryService.books(
                genres: genres, language: language, limit: 12
            )
            if bookSuggestions.isEmpty {
                suggestionError = english ? "No books found. You can skip this step." :
                    "Книги не найдены. Этот шаг можно пропустить."
            }
        } catch is CancellationError {
            return
        } catch {
            suggestionError = english ? "Can't load books. Check your connection or try a VPN." :
                "Не удалось загрузить книги. Проверьте интернет или включите VPN."
        }
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
                Label(english ? "Recommendations for your interests" : "Подборки по вашим интересам",
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
                    
                    if step == 4 {
                        finish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { step += 1 }
                    }
                }
            }
        }
        .padding(.vertical, 15)
    }
}
