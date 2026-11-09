import SwiftUI

enum ReaderMetrics {
    static let screenInset:CGFloat=20
    static let formSpacing:CGFloat=12
    static let sectionSpacing:CGFloat=24
}
struct ReaderSearchSourceLabel:View {
    let title:String
    let icon:String
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:icon).foregroundStyle(Color(hex:accentHex)).frame(width:22)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength:8)
            Image(systemName:"chevron.up.chevron.down").font(.caption).foregroundStyle(ReaderStyle.secondary)
        }.foregroundStyle(.white).padding(.horizontal,14).frame(minHeight:48)
            .background(ReaderStyle.surface,in:RoundedRectangle(cornerRadius:12))
    }
}
struct ReaderQueryField:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @Binding var query:String
    var focus: FocusState<Bool>.Binding
    let search:()->Void
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(ReaderStyle.secondary)
            TextField("Название или автор",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused(focus).submitLabel(.search).onSubmit { focus.wrappedValue=false; search() }.foregroundStyle(.white)
            if !query.isEmpty {
                Button {query=""} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(ReaderStyle.secondary)}
                    .frame(minWidth:44,minHeight:44).accessibilityLabel(Text(verbatim:L10n.render("Очистить поиск",language:localizationLanguage)))
            }
        }.padding(.leading,14).padding(.trailing,query.isEmpty ? 14:2).frame(minHeight:48)
            .background(ReaderStyle.surface,in:RoundedRectangle(cornerRadius:12))
    }
}
struct ReaderSearchLanguage:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @Binding var selection:String
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    private var title:String {selection == "all" ? "Все":selection == "en" || (selection == "auto" && language == "en") ? "English":"Русский"}
    var body:some View {
        Menu {
            Button("Русский") {selection="ru"}
            Button("English") {selection="en"}
            Button("Все") {selection="all"}
        } label:{
            HStack(spacing:8) {
                Image(systemName:"globe")
                Text(verbatim:L10n.render("Язык книг",language:localizationLanguage))
                Spacer()
                Text(verbatim:L10n.render(title,language:language)).foregroundStyle(Color(hex:accentHex))
            }.font(.footnote).foregroundStyle(ReaderStyle.secondary).frame(minHeight:44).contentShape(Rectangle())
        }
    }
}
struct LibraryActions:View {
    let audio:Bool
    let search:()->Void
    let importFiles:()->Void
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        VStack(spacing:10) {
            PurpleAction(title:audio ? "Найти аудиокнигу":"Найти книгу",icon:"magnifyingglass",action:search)
            Button(action:importFiles) {
                Label("Импортировать в библиотеку",systemImage:"square.and.arrow.down")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color(hex:accentHex))
                    .frame(maxWidth:.infinity,minHeight:44)
                    .background(ReaderStyle.surface,in:RoundedRectangle(cornerRadius:10))
                    .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(ReaderStyle.line,lineWidth:0.8))
            }.buttonStyle(.plain)
        }
    }
}
struct CatalogResultRow:View {
    let title:String
    let author:String
    let coverURL:URL?
    var reason: String? = nil
    var body:some View {
        ReaderCard(inset:12) {
            HStack(spacing:12) {
                BookArtwork(title:title,author:author,coverURL:coverURL,width:56,height:80)
                VStack(alignment:.leading,spacing:6) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    Text(verbatim:L10n.authorName(author)).font(.caption).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                    if let reason { Text(verbatim: L10n.render(reason)).font(.caption2).foregroundStyle(ReaderStyle.secondary).lineLimit(2) }
                }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(ReaderStyle.secondary)
            }.frame(minHeight:80)
        }
    }
}
struct CatalogSkeletons:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse=false
    var body:some View {
        VStack(spacing:12) {
            ForEach(0..<6) {_ in
                ReaderCard(inset:12) {
                    HStack(spacing:12) {
                        RoundedRectangle(cornerRadius:5).frame(width:56,height:80)
                        VStack(alignment:.leading,spacing:10) {
                            Capsule().frame(maxWidth:190).frame(height:12)
                            Capsule().frame(maxWidth:140).frame(height:12)
                            Capsule().frame(maxWidth:110).frame(height:9).padding(.top,2)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.foregroundStyle(Color.white.opacity(0.10))
                }
            }
        }.opacity(reduceMotion ? 0.8:pulse ? 1:0.55)
            .animation(reduceMotion ? nil:.easeInOut(duration:1.1).repeatForever(autoreverses:true),value:pulse)
            .onAppear {pulse=true}.onDisappear {pulse=false}
            .accessibilityElement(children:.ignore).accessibilityLabel(Text(verbatim:L10n.render("Загрузка каталога",language:localizationLanguage)))
    }
}
