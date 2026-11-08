import SwiftUI
import Foundation

enum OPDSCatalogKind:String,Codable {case books,audio}

struct NamedOPDSCatalog: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var url: String
    var searchParameter: String
    var kind:OPDSCatalogKind? = nil
    var isAudio:Bool {kind == .audio}

    init(id: UUID = UUID(), name: String, url: String, searchParameter: String = "searchTerm",kind:OPDSCatalogKind = .books) {
        self.id = id
        self.name = name
        self.url = url
        self.searchParameter = searchParameter
        self.kind=kind
    }
}

enum OPDSSources {
    static func decode(_ raw: String) -> [NamedOPDSCatalog] {
        guard let data = raw.data(using: .utf8),
              let sources = try? JSONDecoder().decode([NamedOPDSCatalog].self, from: data) else { return [] }
        return sources
    }

    static func encode(_ sources: [NamedOPDSCatalog]) -> String {
        guard let data = try? JSONEncoder().encode(sources),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    static func isValid(_ source: NamedOPDSCatalog) -> Bool {
        guard let url = URLComponents(string: source.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, !source.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return source.searchParameter.count < 60
    }
}

struct CustomOPDSCatalogsScreen: View {
    @AppStorage("savedOPDSCatalogs") private var raw = "[]"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var name = ""
    @State private var address = ""
    @State private var parameter = "searchTerm"
    @State private var editingID: UUID?
    @State private var error: String?
    @State private var kind="books"

    private var saved: [NamedOPDSCatalog] { OPDSSources.decode(raw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("OPDS-каталоги")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Добавьте название и ссылку HTTP или HTTPS. Можно подключить несколько каталогов.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                if !saved.isEmpty {
                    SectionLabel(text: "Мои каталоги")
                    ReaderCard {
                        ForEach(saved) { source in
                            HStack(spacing: 11) {
                                Image(systemName: source.isAudio ? "headphones":"books.vertical")
                                    .foregroundStyle(Color(hex: accentHex))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(source.isAudio ? "Аудиокниги":"Книги").font(.caption).foregroundStyle(ReaderStyle.secondary)
                                    Text(source.url)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                                Spacer()
                                Button {
                                    editingID = source.id
                                    name = source.name
                                    address = source.url
                                    parameter = source.searchParameter
                                    kind=source.isAudio ? "audio":"books"
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                Button(role: .destructive) {
                                    raw = OPDSSources.encode(saved.filter { $0.id != source.id })
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                            .padding(.vertical, 12)
                            if saved.last?.id != source.id { ReaderDivider() }
                        }
                    }
                }
                SectionLabel(text: editingID == nil ? "Новый каталог" : "Изменить каталог")
                ReaderCard {
                    Text("Тип каталога").font(.system(size:13,weight:.semibold)).padding(.bottom,10)
                    ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$kind)
                    ReaderDivider().padding(.top,12)
                    TextField("Название", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(.vertical, 13)
                    ReaderDivider()
                    TextField("https://example.org/opds", text: $address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .padding(.vertical, 13)
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                PurpleAction(title: editingID == nil ? "Добавить каталог" : "Сохранить изменения",
                             icon: "checkmark") {
                    save()
                }
                if editingID != nil {
                    Button("Отменить редактирование") {
                        clear()
                    }
                    .font(.subheadline)
                }
                Text("Если книги не находятся, проверьте адрес OPDS-каталога.")
                    .font(.footnote)
                    .foregroundStyle(ReaderStyle.secondary)
            }
            .padding(20)
        }
        .readerCanvas()
        .navigationTitle("OPDS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let item = NamedOPDSCatalog(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: address.trimmingCharacters(in: .whitespacesAndNewlines),
            searchParameter: parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "searchTerm" : parameter.trimmingCharacters(in: .whitespacesAndNewlines),
            kind:kind == "audio" ? .audio:.books
        )
        guard OPDSSources.isValid(item) else {
            error = "Укажите название и ссылку HTTP или HTTPS на каталог."
            return
        }
        var list = saved
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
        raw = OPDSSources.encode(list)
        clear()
    }

    private func clear() {
        editingID = nil
        name = ""
        address = ""
        parameter = "searchTerm"
        kind="books"
        error = nil
    }
}
