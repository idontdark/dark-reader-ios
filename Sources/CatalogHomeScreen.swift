import SwiftUI

struct CatalogPromoCarousel:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let audio:Bool
    let onSearch:()->Void
    let onLibrary:()->Void
    let onImport:()->Void
    @State private var index=0
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        VStack(spacing:7) {
            TabView(selection:$index) {
                promo(title:audio ? "Аудиокниги":"Электронные книги",
                      subtitle:audio ? "Слушайте любимые\nкниги в любое время":"Любимые истории —\nвсегда под рукой",action:onSearch).tag(0)
                promo(title:audio ? "Слушайте офлайн":"Читайте офлайн",
                      subtitle:"Ваша библиотека\nбез лишних отвлечений",action:onLibrary).tag(1)
                promo(title:"Свои книги",
                      subtitle:audio ? "Добавьте аудиокнигу\nиз приложения «Файлы»":"EPUB, FB2 и MOBI\nв вашей библиотеке",action:onImport).tag(2)
            }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:142)
            HStack(spacing:4) {
                ForEach(0..<3,id:\.self) {i in Circle().fill(index == i ? Color(hex:accentHex):Color.white.opacity(0.20)).frame(width:4,height:4)}
            }
        }.padding(.top,1)
    }
    private func promo(title:String,subtitle:String,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:7) {
                    Text(verbatim:L10n.render(title,language:localizationLanguage)).font(.system(size:20,weight:.bold)).tracking(-0.3)
                    Text(verbatim:L10n.render(subtitle,language:localizationLanguage)).font(.system(size:12)).lineSpacing(2).foregroundStyle(.white.opacity(0.8))
                }.padding(.leading,17).frame(maxWidth:.infinity,alignment:.leading)
                if audio {Image("HeroHeadphones").resizable().scaledToFit().frame(width:144,height:139).offset(x:5,y:9)}
                else {BrandBook(width:130).padding(.trailing,8)}
            }.foregroundStyle(.white).frame(maxWidth:.infinity).frame(height:142)
                .background {
                    ZStack(alignment:.bottom) {
                        LinearGradient(colors:[Color(hex:"#3B1556"),Color(hex:"#261039"),Color(hex:"#110A1C")],
                                       startPoint:.topLeading,endPoint:.bottomTrailing)
                        FooterWaves().frame(height:54).opacity(0.8)
                    }
                }.clipShape(RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(hex:"#81509E").opacity(0.42),lineWidth:0.8))
        }.buttonStyle(.plain)
    }
}

struct UnifiedSearchScreen:View {
    @EnvironmentObject private var navigation:ReaderNavigation
    var body:some View {
        VStack(spacing:12) {
            ReaderHeader(title:"Поиск",trailingIcon:nil,trailingAction:nil).padding(.horizontal,ReaderMetrics.screenInset)
            ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$navigation.searchScope)
                .padding(.horizontal,ReaderMetrics.screenInset)
            if navigation.searchScope == "books" {CatalogScreen(showsHeader:false)}
            else {AudioCatalogScreen(showsHeader:false)}
        }.readerCanvas()
    }
}
