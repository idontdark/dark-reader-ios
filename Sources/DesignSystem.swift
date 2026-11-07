import SwiftUI
import UIKit

enum ReaderStyle {
    static let background = Color(hex: "#0D0A14")
    static let surface = Color(hex: "#201929")
    static let raised = Color(hex: "#2A2235")
    static let line = Color(hex: "#65516F").opacity(0.38)
    static let secondary = Color(hex: "#ACA2B6")
    static let defaultAccent = "#9937EF"
    static let cardGradient = LinearGradient(colors: [Color(hex:"#251D31"), Color(hex:"#17131F")],
                                             startPoint:.topLeading,endPoint:.bottomTrailing)
    static func actionGradient(_ hex: String) -> LinearGradient {
        LinearGradient(stops:[.init(color:Color(hex:hex).shade(0.30),location:0),
                              .init(color:Color(hex:hex),location:0.38),
                              .init(color:Color(hex:hex).shade(-0.28),location:1)],
                       startPoint:.top,endPoint:.bottom)
    }
}
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"#",with:"")
        let value = UInt64(cleaned,radix:16) ?? 0x9937EF
        if cleaned.count == 8 {
            self.init(.sRGB,red:Double((value >> 24)&255)/255,green:Double((value >> 16)&255)/255,
                      blue:Double((value >> 8)&255)/255,opacity:Double(value&255)/255)
        } else {
            self.init(.sRGB,red:Double((value >> 16)&255)/255,green:Double((value >> 8)&255)/255,blue:Double(value&255)/255,opacity:1)
        }
    }
    var hexRGB: String {
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        guard UIColor(self).getRed(&r,green:&g,blue:&b,alpha:&a) else { return ReaderStyle.defaultAccent }
        return String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255))
    }
    func shade(_ amount: Double) -> Color {
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        UIColor(self).getRed(&r,green:&g,blue:&b,alpha:&a)
        func adjust(_ v:CGFloat)->Double { amount >= 0 ? Double(v)+(1-Double(v))*amount : Double(v)*(1+amount) }
        return Color(.sRGB,red:adjust(r),green:adjust(g),blue:adjust(b),opacity:Double(a))
    }
}
struct ReaderCanvas: ViewModifier {
    func body(content:Content)->some View {
        content.background {
            ZStack {
                ReaderStyle.background
                LinearGradient(colors:[Color(hex:"#281436").opacity(0.16),.clear],
                               startPoint:.topLeading,endPoint:.center)
            }.ignoresSafeArea()
        }.scrollContentBackground(.hidden)
    }
}
extension View { func readerCanvas()->some View { modifier(ReaderCanvas()) } }

struct BrandBook: View {
    var width:CGFloat=24
    var body:some View { Image("BrandBook").resizable().scaledToFit().frame(width:width,height:width*0.76).accessibilityHidden(true) }
}
struct ReaderCard<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:0) { content }
            .padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:13,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(ReaderStyle.line,lineWidth:0.8))
    }
}
struct ReaderInsetGroup<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {
        VStack(spacing:0) { content }.padding(.horizontal,12)
            .background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(ReaderStyle.line,lineWidth:0.8))
    }
}
struct ReaderHeader:View {
    let title:String
    let trailingIcon:String?
    let trailingAction:(()->Void)?
    var secondaryIcon:String?=nil
    var secondaryAction:(()->Void)?=nil
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    init(title:String,trailingIcon:String?,trailingAction:(()->Void)?) {
        self.title=title;self.trailingIcon=trailingIcon;self.trailingAction=trailingAction
    }
    init(title:String,trailingIcon:String?,trailingAction:(()->Void)?,secondaryIcon:String?,secondaryAction:(()->Void)?) {
        self.title=title;self.trailingIcon=trailingIcon;self.trailingAction=trailingAction
        self.secondaryIcon=secondaryIcon;self.secondaryAction=secondaryAction
    }
    private var library:Bool { title == "Моя библиотека" || title == "Библиотека" }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if library {
                HStack(spacing:7) {
                    BrandBook(width:23)
                    Text("Dark Reader").font(.system(size:14,weight:.semibold))
                    Spacer()
                    if let secondaryIcon,let secondaryAction { headerButton(secondaryIcon,secondaryAction) }
                    if let trailingIcon,let trailingAction { headerButton(trailingIcon,trailingAction) }
                }.frame(height:28)
                Text(LocalizedStringKey(title)).font(.system(size:25,weight:.bold)).tracking(-0.6)
            } else {
                HStack {
                    Text(LocalizedStringKey(title)).font(.system(size:26,weight:.bold)).tracking(-0.5)
                    Spacer()
                    if let trailingIcon,let trailingAction { headerButton(trailingIcon,trailingAction) }
                }.frame(minHeight:38)
            }
        }.foregroundStyle(.white).padding(.top,7)
    }
    private func headerButton(_ name:String,_ action:@escaping()->Void)->some View {
        Button(action:action) {
            Image(systemName:name).font(.system(size:15,weight:.medium))
                .foregroundStyle(Color.white.opacity(0.84)).frame(width:29,height:29)
                .background(Color.white.opacity(0.045),in:Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.06),lineWidth:0.6))
        }.accessibilityLabel(name == "plus" ? "Добавить книгу" : "Поиск")
    }
}

struct ReaderSegmentedControl:View {
    let items:[(id:String,title:String)]
    @Binding var selection:String
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        HStack(spacing:2) {
            ForEach(items,id:\.id) { item in
                Button { withAnimation(.easeInOut(duration:0.16)) { selection=item.id } } label: {
                    Text(LocalizedStringKey(item.title)).font(.system(size:12,weight:selection == item.id ? .semibold:.medium))
                        .foregroundStyle(.white.opacity(selection == item.id ? 1:0.73))
                        .frame(maxWidth:.infinity).frame(height:27)
                        .background {
                            if selection == item.id {
                                Capsule().fill(ReaderStyle.actionGradient(accentHex))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16),lineWidth:0.6))
                                    .shadow(color:Color(hex:accentHex).opacity(0.25),radius:5,y:1)
                            }
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == item.id ? [.isSelected] : [])
                    .accessibilityIdentifier("scope-"+item.id)
            }
        }.padding(3)
            .background(Color(hex:"#24202C"),in:Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.055),lineWidth:0.6))
    }
}
struct PurpleAction:View {
    let title:String
    var icon:String="arrow.right"
    var height:CGFloat=44
    let action:()->Void
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        Button(action:action) {
            HStack(spacing:7) {
                if !icon.isEmpty { Image(systemName:icon).font(.system(size:15,weight:.medium)) }
                Text(LocalizedStringKey(title)).font(.system(size:14,weight:.semibold))
            }.foregroundStyle(.white).frame(maxWidth:.infinity).frame(height:height)
                .background(ReaderStyle.actionGradient(accentHex),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.white.opacity(0.18),lineWidth:0.7))
                .shadow(color:Color(hex:accentHex).opacity(0.16),radius:9,y:3)
        }.buttonStyle(.plain)
    }
}
struct BookArtwork:View {
    let title:String
    let author:String
    var coverURL:URL?=nil
    var width:CGFloat=68
    var height:CGFloat=96
    var body:some View {
        Group {
            if let coverURL {
                CachedCover(url:CoverSize.url(coverURL,detailed:width>115)) { $0.resizable().scaledToFill() }
                    placeholder: { fallback }
            } else { fallback }
        }.frame(width:width,height:height)
            .clipShape(RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(Color.white.opacity(0.19),lineWidth:0.6))
            .shadow(color:.black.opacity(0.3),radius:5,y:3)
            .accessibilityHidden(true)
    }
    private var fallback:some View {
        ZStack {
            LinearGradient(colors:[Color(hex:"#705B6B"),Color(hex:"#29212F")],startPoint:.topLeading,endPoint:.bottomTrailing)
            VStack(spacing:8) {
                Text(title).font(.system(size:max(9,width*0.14),weight:.semibold,design:.serif))
                    .multilineTextAlignment(.center).lineLimit(4)
                Spacer(minLength:0)
                Text(author).font(.system(size:max(7,width*0.09))).lineLimit(2).multilineTextAlignment(.center)
            }.foregroundStyle(Color(hex:"#F1E4C5")).padding(max(7,width*0.08))
        }
    }
}
struct SectionLabel:View {
    let text:String
    var body:some View { Text(LocalizedStringKey(text)).font(.system(size:13,weight:.semibold)).foregroundStyle(ReaderStyle.secondary) }
}
struct ReaderRow<Content:View>:View {
    let icon:String
    let title:String
    let subtitle:String?
    @ViewBuilder var trailing:Content
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        HStack(spacing:11) {
            Image(systemName:icon).font(.system(size:17)).foregroundStyle(Color(hex:accentHex).shade(0.18)).frame(width:24)
            VStack(alignment:.leading,spacing:3) {
                Text(LocalizedStringKey(title)).font(.system(size:14,weight:.medium)).foregroundStyle(.white)
                if let subtitle { Text(LocalizedStringKey(subtitle)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            trailing
        }.padding(.vertical,12).contentShape(Rectangle())
    }
}
struct ReaderDivider:View { var body:some View { Rectangle().fill(Color.white.opacity(0.065)).frame(height:0.6) } }
struct LibraryMenuRow:View {
    let icon:String
    let title:String
    let count:Int
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:icon).font(.system(size:17,weight:.regular)).frame(width:23)
            Text(LocalizedStringKey(title)).font(.system(size:14,weight:.medium))
            Spacer()
            Text("\(count)").font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
            Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(ReaderStyle.secondary.opacity(0.8))
        }.foregroundStyle(Color.white.opacity(0.9)).frame(minHeight:44).contentShape(Rectangle())
    }
}
struct FooterWaves:View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        ZStack {
            RadialGradient(colors:[Color(hex:accentHex).opacity(0.30),.clear],center:.bottom,startRadius:5,endRadius:210)
            Canvas { context,size in
                for index in 0..<6 {
                    let i=CGFloat(index)
                    var path=Path()
                    path.move(to:CGPoint(x:-20,y:size.height*(0.48+i*0.045)))
                    path.addCurve(to:CGPoint(x:size.width+20,y:size.height*(0.61+i*0.025)),
                                  control1:CGPoint(x:size.width*0.36,y:size.height*(0.18+i*0.13)),
                                  control2:CGPoint(x:size.width*0.53,y:size.height*(1.22-i*0.12)))
                    context.stroke(path,with:.color(Color(hex:accentHex).opacity(index == 2 ? 0.65:0.18)),lineWidth:index == 2 ? 1.1:0.6)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct AudioWaveBackdrop:View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        HStack(spacing:4) {
            ForEach(0..<49) { index in
                let x=Double(index)
                let amplitude=18+abs(sin(x*1.13))*47+abs(cos(x*0.41))*28
                Capsule().fill(LinearGradient(colors:[Color(hex:accentHex).opacity(0.1),Color(hex:accentHex),Color(hex:accentHex).opacity(0.1)],
                                               startPoint:.top,endPoint:.bottom))
                    .frame(width:3,height:amplitude)
                    .shadow(color:Color(hex:accentHex).opacity(0.8),radius:5)
            }
        }.frame(maxWidth:.infinity).accessibilityHidden(true)
    }
}
