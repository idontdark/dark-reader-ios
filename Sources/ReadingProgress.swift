import Foundation

enum ReadingProgressDisplay:String,CaseIterable {
    case percent,pages
    static func stored(_ raw:String?)->Self { raw.flatMap(Self.init(rawValue:)) ?? .percent }
    func text(fraction:Double?,position:Int?,total:Int?,language:String="ru")->String {
        switch self {
        case .percent:
            guard let fraction,fraction.isFinite else{return "—"}
            return "\(Int((max(0,min(1,fraction))*100).rounded()))%"
        case .pages:
            guard let position,position>0 else{return "—"}
            let page=total.flatMap {$0>0 ? min(position,$0):nil} ?? position
            if let total,total>0 {return language == "en" ? "Page \(page) of \(total)":"Стр. \(page) из \(total)"}
            return language == "en" ? "Page \(page)":"Стр. \(page)"
        }
    }
}
