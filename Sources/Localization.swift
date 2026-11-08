import Foundation
import SwiftUI
import UIKit

enum L10n {
    static var language:String {UserDefaults.standard.string(forKey:"appLanguage") == "en" ? "en":"ru"}
    private static let bundles:[String:Bundle] = Dictionary(uniqueKeysWithValues:["ru","en"].compactMap {code in
        Bundle.main.path(forResource:code,ofType:"lproj").flatMap(Bundle.init(path:)).map {(code,$0)}
    })
    static func text(_ key:String,language:String?=nil)->String {
        bundles[language ?? self.language]?.localizedString(forKey:key,value:key,table:"Localizable") ?? key
    }
    private struct Template {
        let regex:NSRegularExpression
        let key:String
    }
    private static let templates:[Template] = {
        guard let file=bundles["en"]?.path(forResource:"Localizable",ofType:"strings"),
              let values=NSDictionary(contentsOfFile:file) as? [String:String] else{return []}
        return values.keys.filter {$0.contains("%@") && $0.range(of:"[А-Яа-яЁё]",options:.regularExpression) != nil}
            .sorted {$0.replacingOccurrences(of:"%@",with:"").count > $1.replacingOccurrences(of:"%@",with:"").count}
            .compactMap {key in
                let parts=key.components(separatedBy:"%@")
                guard parts.joined().count>3,
                      let regex=try? NSRegularExpression(pattern:"^"+parts.map {NSRegularExpression.escapedPattern(for:$0)}.joined(separator:"(.*?)")+"$",options:.dotMatchesLineSeparators) else{return nil}
                return Template(regex:regex,key:key)
            }
    }()
    /// Only used for application UI. Catalog titles/authors stay verbatim.
    static func render(_ source:String,language:String?=nil)->String {
        let language=language ?? self.language
        let exact=text(source,language:language)
        if language != "en" || exact != source {return exact}
        let range=NSRange(source.startIndex..<source.endIndex,in:source)
        for template in templates {
            guard let match=template.regex.firstMatch(in:source,range:range) else{continue}
            let parts=text(template.key,language:language).components(separatedBy:"%@")
            guard parts.count == match.numberOfRanges else{continue}
            var output=parts[0]
            for index in 1..<parts.count {
                guard let capture=Range(match.range(at:index),in:source) else{continue}
                let value=String(source[capture])
                let nestedUI=index == 1 && (template.key.hasPrefix("Не удалось") || template.key.hasPrefix("Вход не завершён") || template.key.hasPrefix("%@ Повтор подключения"))
                output+=(nestedUI ? render(value,language:language):value)+parts[index]
            }
            return output
        }
        return source
    }
    static func errorDescription(_ error:Error)->String {
        let ns=error as NSError
        let message=error.localizedDescription
        if language == "en",message.range(of:"[А-Яа-яЁё]",options:.regularExpression) != nil {
            let translated=render(message)
            if translated != message {return translated}
            return text("Не удалось выполнить действие. Повторите попытку.")+" (\(ns.domain): \(ns.code))"
        }
        return message
    }
    static func date(_ date:Date)->String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:language)
        formatter.dateStyle = .medium;formatter.timeStyle = .short
        return formatter.string(from:date)
    }
}

extension View {
    func readerNavigationTitle(_ title:String,localized:Bool=true)->some View {
        modifier(ReaderNavigationTitle(title:title,localized:localized))
    }
}
private struct ReaderNavigationTitle:ViewModifier {
    let title:String
    let localized:Bool
    @AppStorage("appLanguage") private var language="ru"
    func body(content:Content)->some View {
        content.navigationTitle(Text(verbatim:localized ? L10n.render(title,language:language):title))
            .background(LocalizedNavigationBridge(language:language).frame(width:0,height:0).allowsHitTesting(false))
    }
}
private struct LocalizedNavigationBridge:UIViewControllerRepresentable {
    let language:String
    func makeUIViewController(context:Context)->Controller {Controller(language:language)}
    func updateUIViewController(_ controller:Controller,context:Context) {
        controller.language=language;controller.updateBackTitle()
    }
    final class Controller:UIViewController {
        var language:String
        init(language:String) {self.language=language;super.init(nibName:nil,bundle:nil)}
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        override func viewDidAppear(_ animated:Bool) {super.viewDidAppear(animated);updateBackTitle()}
        override func didMove(toParent parent:UIViewController?) {super.didMove(toParent:parent);updateBackTitle()}
        func updateBackTitle() {
            guard let navigationController,navigationController.viewControllers.count>1 else{return}
            let previous=navigationController.viewControllers[navigationController.viewControllers.count-2]
            let title=L10n.text("Назад",language:language)
            previous.navigationItem.backButtonDisplayMode = .default
            previous.navigationItem.backButtonTitle=title
            previous.navigationItem.backBarButtonItem=UIBarButtonItem(title:title,style:.plain,target:nil,action:nil)
        }
    }
}
