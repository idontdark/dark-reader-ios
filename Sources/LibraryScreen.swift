import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject private var books: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var selected: LocalBook?
    @State private var query = ""
    @State private var filter = 0
    @State private var showSearch = false
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @AppStorage("hintLibraryShown") private var hintLibraryShown = false
    @AppStorage("onboardingSchemaVersion") private var onboardingVersion = 0
    @State private var showLibraryTip = false

    private var sortedBooks: [LocalBook] {
        let all = books.books.sorted { $0.addedAt > $1.addedAt }
        return all.filter { book in
            let matches = query.isEmpty
                || book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
            let category = filter == 0 || (filter == 1 && book.locatorJSON != nil)
                || (filter == 2 && book.isFavorite == true)
            return matches && category
        }
    }

    private var currentBook: LocalBook? {
        books.books
            .filter { $0.locatorJSON != nil }
            .max { $0.changeDate < $1.changeDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    ReaderHeader(title: "Моя библиотека", trailingIcon: "plus") {
                        navigation.tab = .add
                    }

                    if let currentBook {
                        featuredBook(currentBook)
                    } else if books.books.isEmpty {
                        welcomeCard
                    }

                    if !ReaderPreferences.array(authorsJSON).isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                SectionLabel(text: "Любимые авторы")
                                Spacer()
                                NavigationLink {
                                    FavoriteAuthorsScreen()
                                } label: {
                                    Text("Изменить")
                                        .font(.subheadline)
                                        .foregroundStyle(Color(hex: accentHex))
                                }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(ReaderPreferences.array(authorsJSON), id: \.self) { author in
                                        Button {
                                            navigation.authorToSearch = author
                                            navigation.tab = .catalog
                                        } label: {
                                            Label(author, systemImage: "person.crop.circle")
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 13)
                                                .padding(.vertical, 10)
                                                .background(ReaderStyle.surface, in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel(text: "Мои книги")
                            Spacer()
                            Button { withAnimation { showSearch.toggle() } } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        if showSearch {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(ReaderStyle.secondary)
                                TextField("Название или автор", text: $query)
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(12)
                            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Picker("Фильтр книг", selection: $filter) {
                            Text("Все").tag(0)
                            Text("Читаю").tag(1)
                            Text("Избранное").tag(2)
                        }
                        .pickerStyle(.segmented)

                        if sortedBooks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: books.books.isEmpty ? "books.vertical" : "text.magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(Color(hex: accentHex))
                                Text(books.books.isEmpty ? "Здесь будут ваши книги" : "Книг не найдено")
                                    .font(.headline)
                                Text(books.books.isEmpty
                                     ? "Добавьте EPUB из «Файлов» или найдите книгу в каталоге."
                                     : "Попробуйте изменить фильтр или строку поиска.")
                                    .font(.subheadline)
                                    .foregroundStyle(ReaderStyle.secondary)
                                    .multilineTextAlignment(.center)
                                if books.books.isEmpty {
                                    PurpleAction(title: "Добавить книгу", icon: "plus") {
                                        navigation.tab = .add
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity)
                            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 17))
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedBooks) { book in
                                    HStack(spacing: 12) {
                                        Button { selected = book } label: {
                                            HStack(spacing: 13) {
                                                BookArtwork(title: book.title, author: book.author,
                                                            coverURL: book.coverURL, width: 64, height: 91)
                                                VStack(alignment: .leading, spacing: 7) {
                                                    Text(book.title)
                                                        .foregroundStyle(.white)
                                                        .font(.system(.subheadline, weight: .semibold))
                                                        .lineLimit(2)
                                                    Text(book.author)
                                                        .font(.footnote)
                                                        .foregroundStyle(ReaderStyle.secondary)
                                                        .lineLimit(1)
                                                    if book.locatorJSON != nil {
                                                        progressLine(for: book)
                                                    }
                                                }
                                                Spacer(minLength: 2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        Menu {
                                            Button("Читать", systemImage: "book") { selected = book }
                                            Button(book.isFavorite == true ? "Убрать из избранного" : "В избранное",
                                                   systemImage: "heart") {
                                                books.toggleFavorite(book)
                                            }
                                            Button("Удалить книгу", systemImage: "trash", role: .destructive) {
                                                books.delete(book)
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .frame(width: 32, height: 44)
                                                .foregroundStyle(ReaderStyle.secondary)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    if book.id != sortedBooks.last?.id { ReaderDivider() }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { offerLibraryHint() }
            .onChange(of: onboardingVersion) { _, _ in offerLibraryHint() }
            .alert("Ваша библиотека", isPresented: $showLibraryTip) {
                Button("Понятно") { hintLibraryShown = true }
            } message: {
                Text("Здесь хранятся ваши книги. Чтобы добавить новую, нажмите +.")
            }
            .sheet(item: $selected) { book in
                ReaderScreen(bookID: book.id)
            }
        }
    }

    private func offerLibraryHint() {
        guard onboardingVersion >= 2, !hintLibraryShown else { return }
        hintLibraryShown = true
        showLibraryTip = true
    }

    private var welcomeCard: some View {
        ReaderCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30))
                    .frame(width: 60, height: 70)
                    .foregroundStyle(Color(hex: accentHex))
                    .background(Color(hex: accentHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Время читать")
                        .font(.headline)
                    Text("Ваша библиотека пока пуста. Начните с поиска книги или импорта EPUB.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }
            }
        }
    }

    private func featuredBook(_ book: LocalBook) -> some View {
        ReaderCard {
            HStack(alignment: .top, spacing: 15) {
                BookArtwork(title: book.title, author: book.author,
                            coverURL: book.coverURL, width: 100, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    Text("ЧИТАЮ СЕЙЧАС")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color(hex: accentHex))
                    Text(book.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(.white)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    progressLine(for: book)
                    Button {
                        selected = book
                    } label: {
                        Label("Продолжить", systemImage: "book.open")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color(hex: accentHex), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }

    private func progressLine(for book: LocalBook) -> some View {
        let percent = BookProgress.fraction(book.locatorJSON)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.11))
                    Capsule().fill(Color(hex: accentHex)).frame(width: proxy.size.width * percent)
                }
            }
            .frame(height: 4)
            Text("\(Int(percent * 100))% прочитано")
                .font(.caption2)
                .foregroundStyle(ReaderStyle.secondary)
        }
    }
}

enum BookProgress {
    static func fraction(_ locator: String?) -> Double {
        guard let locator, let data = locator.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locations = object["locations"] as? [String: Any] else { return 0 }
        let value = locations["totalProgression"] as? Double ?? locations["progression"] as? Double ?? 0
        return max(0, min(1, value))
    }
}
