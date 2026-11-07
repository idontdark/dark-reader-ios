import SwiftUI

/// Preferences remain editable after onboarding.
struct InterestsScreen: View {
    @AppStorage("wantsBooks") private var books = true
    @AppStorage("wantsAudiobooks") private var audiobooks = false
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionLabel(text: "Что вам интересно")
                ReaderCard {
                    Toggle("Читать книги", isOn: Binding(get: { books }, set: { value in
                        if !value && !audiobooks { return }
                        books = value
                    }))
                    .padding(.vertical, 13)
                    ReaderDivider()
                    Toggle("Слушать аудиокниги", isOn: Binding(get: { audiobooks }, set: { value in
                        if !value && !books { return }
                        audiobooks = value
                    }))
                    .padding(.vertical, 13)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Ваши интересы")
                    ReaderCard {
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
                Text("Переключаться между чтением и прослушиванием можно в любой момент.")
                    .font(.footnote)
                    .foregroundStyle(ReaderStyle.secondary)
            }.padding(20)
        }
        .readerCanvas()
        .navigationTitle("Интересы")
        .navigationBarTitleDisplayMode(.inline)
    }
}
