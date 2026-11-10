import Foundation
import NaturalLanguage
import CoreFoundation

struct Entry: Hashable {
    let code: String
    let word: String
}

enum Flypy {
    private static let initials = ["zh": "v", "ch": "i", "sh": "u"]
    private static let finals = [
        "iu":"q", "ei":"w", "uan":"r", "ue":"t", "ve":"t", "un":"y",
        "uo":"o", "ie":"p", "ong":"s", "iong":"s", "ai":"d", "en":"f",
        "eng":"g", "ang":"h", "an":"j", "ing":"k", "uai":"k", "iang":"l",
        "uang":"l", "ou":"z", "ia":"x", "ua":"x", "ao":"c", "ui":"v",
        "in":"b", "iao":"n", "ian":"m"
    ]

    static func normalize(_ syllable: String) -> String {
        // Remove tones while preserving the diaeresis in lü/nü.
        let toneMarks: Set<Unicode.Scalar> = ["\u{0304}", "\u{0301}", "\u{030c}", "\u{0300}"]
        return String(syllable.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !toneMarks.contains($0) })
            .precomposedStringWithCanonicalMapping.replacingOccurrences(of: "ü", with: "v")
    }

    static func encode(_ syllable: String) -> String? {
        let plain = normalize(syllable)
        guard let first = plain.first, plain.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return nil }
        if "aoe".contains(first) {
            if plain.count == 1 { return plain + plain }
            if plain.count == 2 { return plain }
            return finals[plain].map { String(first) + $0 }
        }
        let pair = String(plain.prefix(2))
        let initial = initials[pair] ?? String(first)
        let final = String(plain.dropFirst(initials[pair] == nil ? 1 : 2))
        if final.count == 1, "aeiouv".contains(final) { return initial + final }
        return finals[final].map { initial + $0 }
    }

    // CF returns word-level readings without syllable separators. Align those readings
    // with the characters using the pronunciation list shipped with Squirrel.
    private static let readings: [Character: [String]] = {
        let path = "/Library/Input Methods/Squirrel.app/Contents/SharedSupport/luna_pinyin.dict.yaml"
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [Character: [String]] = [:]
        for line in source.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 2, fields[0].count == 1, let ch = fields[0].first else { continue }
            result[ch, default: []].append(String(fields[1]))
        }
        return result
    }()

    private static func split(_ roman: Substring, characters: Substring) -> [String]? {
        guard let ch = characters.first else { return roman.isEmpty ? [] : nil }
        for reading in readings[ch] ?? [] where roman.hasPrefix(reading) {
            if let tail = split(roman.dropFirst(reading.count), characters: characters.dropFirst()) {
                return [reading] + tail
            }
        }
        return nil
    }

    static func code(for word: String) -> String? {
        let source = word as NSString
        let tokenizer = CFStringTokenizerCreate(nil, word as CFString, CFRangeMake(0, source.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "zh_CN") as CFLocale)!
        var syllables: [String] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = source.substring(with: NSRange(location: range.location, length: range.length))
            if let roman = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer,
                    kCFStringTokenizerAttributeLatinTranscription) as? String,
               let aligned = split(normalize(roman).filter { $0.isLetter }[...], characters: token[...]) {
                syllables += aligned
            } else if let roman = token.applyingTransform(.mandarinToLatin, reverse: false) {
                syllables += roman.split(whereSeparator: { $0.isWhitespace || $0 == "'" }).map(String.init)
            }
        }
        let codes = syllables.compactMap(encode)
        guard codes.count == word.count else { return nil }
        return codes.joined()
    }
}

final class WordIndex {
    private let tokens = NLTokenizer(unit: .word)
    private let runs = try! NSRegularExpression(
        pattern: #"\p{Han}+|[A-Za-z][A-Za-z0-9_]*(?:[\p{Pd}.][A-Za-z0-9_]+)*"#
    )
    private let codeCache = NSCache<NSString, NSString>()

    init() {
        tokens.setLanguage(.simplifiedChinese)
        codeCache.countLimit = 6000
    }

    func entries(lines: [String]) -> [Entry] {
        var seen = Set<Entry>()
        var ordered: [Entry] = []
        func add(_ code: String, _ word: String) {
            let entry = Entry(code: code, word: word)
            if seen.insert(entry).inserted { ordered.append(entry) }
        }
        var mixedPhrases: [Entry] = []
        var phrases: [Entry] = []
        func englishCode(_ word: String) -> String {
            word.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.lowercased()
        }
        func chineseCode(_ word: String) -> String? {
            let key = word as NSString
            if let cached = codeCache.object(forKey: key) { return cached as String }
            guard let code = Flypy.code(for: word) else { return nil }
            codeCache.setObject(code as NSString, forKey: key)
            return code
        }
        func addChinese(_ word: String) {
            if (2...12).contains(word.count), let code = chineseCode(word) { add(code, word) }
        }
        for line in lines {
            let ns = line as NSString
            var recent: [(range: NSRange, code: String, isHan: Bool)] = []
            func appendToken(_ range: NSRange, code: String, isHan: Bool) {
                if let previous = recent.last {
                    let end = NSMaxRange(previous.range)
                    let gap = ns.substring(with: NSRange(location: end, length: range.location - end))
                    let joins = gap.unicodeScalars.allSatisfy {
                        $0.properties.generalCategory == .spaceSeparator ||
                        $0.properties.generalCategory == .dashPunctuation || $0 == "_"
                    }
                    if !joins { recent.removeAll() }
                }
                if recent.count == 6 { recent.removeFirst() }
                recent.append((range, code, isHan))
                var key = "", hasHan = false, hasLatin = false
                for start in recent.indices.reversed() {
                    let token = recent[start]
                    key = token.code + key
                    hasHan = hasHan || token.isHan
                    hasLatin = hasLatin || !token.isHan
                    let span = NSUnionRange(token.range, range)
                    guard span.length <= 64 else { break }
                    let count = recent.count - start
                    guard count >= 2, hasHan || count <= 4 else { continue }
                    let word = ns.substring(with: span)
                    guard word.utf8.count <= 128 else { continue }
                    var lookup = key
                    if !hasLatin {
                        // Join separate Han runs across spaces only. Recompute the
                        // reading as one phrase (e.g. 重 庆) without changing its text.
                        let compact = word.filter { !$0.isWhitespace }
                        guard compact.count < word.count, compact.count <= 12,
                              compact.unicodeScalars.allSatisfy({ !CharacterSet.punctuationCharacters.contains($0) }),
                              let code = chineseCode(compact) else { continue }
                        lookup = code
                    }
                    let entry = Entry(code: lookup, word: word)
                    if seen.insert(entry).inserted {
                        if hasHan && hasLatin { mixedPhrases.append(entry) } else { phrases.append(entry) }
                    }
                }
            }
            for match in runs.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range
                let run = ns.substring(with: range)
                if run.utf8.first.map({ $0 < 128 }) == true {
                    let code = englishCode(run)
                    if (2...64).contains(run.utf8.count), code.count >= 2 { add(code, run) }
                    for component in run.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        where component.count >= 2 && component.count <= 64 && component.count < run.count {
                        add(component.lowercased(), String(component))
                    }
                    appendToken(range, code: code, isHan: false)
                    continue
                }
                tokens.string = run
                let parts = tokens.tokens(for: run.startIndex..<run.endIndex)
                // Keep individual words and short adjacent phrases on the same OCR line.
                for i in parts.indices {
                    let word = String(run[parts[i]])
                    if word.count <= 12, let code = chineseCode(word) {
                        if word.count >= 2 { add(code, word) }
                        let local = NSRange(parts[i], in: run)
                        appendToken(NSRange(location: range.location + local.location, length: local.length),
                                    code: code, isHan: true)
                    } else {
                        recent.removeAll()
                    }
                    for end in (i + 1)..<min(i + 3, parts.count) {
                        let phrase = String(run[parts[i].lowerBound..<parts[end].upperBound])
                        if phrase.count <= 8 { addChinese(phrase) }
                    }
                }
            }
        }
        return Array((ordered + mixedPhrases + phrases).prefix(2000))
    }
}
