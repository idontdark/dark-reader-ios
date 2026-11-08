import SwiftUI

/// Preferences remain editable after onboarding.
struct InterestsScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @AppStorage("wantsBooks") private var books = true
    @AppStorage("wantsAudiobooks") private var audiobooks = false
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment:.leading,spacing:8) {
                SectionLabel(text: "Что вам интересно")
                ReaderInsetGroup {
                    Toggle("Читать книги", isOn: Binding(get: { books }, set: { value in
                        if !value && !audiobooks { return }
                        books = value
                    }))
                    .frame(minHeight:48).padding(.horizontal,4)
                    ReaderDivider()
                    Toggle("Слушать аудиокниги", isOn: Binding(get: { audiobooks }, set: { value in
                        if !value && !books { return }
                        audiobooks = value
                    }))
                    .frame(minHeight:48).padding(.horizontal,4)
                }.padding(.vertical,4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Ваши интересы")
                    ReaderInsetGroup {
                        NavigationLink {
                            GenreSettingsScreen()
                        } label: {
                            ReaderRow(icon: "sparkles", title: "Любимые жанры",
                                      subtitle: "\(ReaderPreferences.array(genresJSON).count)") {
                                Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                            }
                        }.buttonStyle(.plain)
                        ReaderDivider()
                        NavigationLink {
                            FavoriteAuthorsScreen()
                        } label: {
                            ReaderRow(icon: "person.2", title: "Любимые авторы",
                                      subtitle: "\(ReaderPreferences.array(authorsJSON).count)") {
                                Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Text(verbatim:L10n.render("Переключаться между чтением и прослушиванием можно в любой момент.",language:localizationLanguage))
                    .font(.footnote)
                    .foregroundStyle(ReaderStyle.secondary)
            }.padding(20)
        }
        .readerCanvas()
        .readerNavigationTitle("Интересы")
        .navigationBarTitleDisplayMode(.inline)
    }
}
