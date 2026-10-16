import Foundation

/// 真源：`ViewFightHtmlSplicer.kt` — phonepk `cmd=viewfight` 多页 HTML 拼成一页。
/// 对齐笔记/大乐斗 Android：正文拼回合，页脚从末页原样子串截取。
enum ViewFightHtmlSplicer {
    struct Result {
        let html: String
        let pages: Int
        let chars: Int
    }

    static func splice(
        pageUrl: String,
        cookie: String,
        knightSummaryHtml: String = "",
        firstPageBody: String? = nil
    ) async -> Result {
        let base = normalizeUrl(pageUrl)
        let first: String
        if let b = firstPageBody, !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            first = b
        } else if let url = URL(string: base) {
            first = await LedouCGI.get(url: url, cookie: cookie).1
        } else {
            first = ""
        }

        var rawPages: [String] = []
        var blocks: [String] = []

        if !first.isEmpty {
            rawPages.append(first)
            let total: Int = {
                guard let m = first.range(of: #"(\d+)\s*/\s*(\d+)\s*页"#, options: .regularExpression) else {
                    return 1
                }
                let s = String(first[m])
                let parts = s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                guard parts.count >= 2, let t = Int(parts[1]) else { return 1 }
                return min(max(t, 1), 20)
            }()

            if total > 1 {
                await withTaskGroup(of: (Int, String).self) { group in
                    for p in 2...total {
                        let u = pageUrlWithIndex(base, page: p)
                        group.addTask {
                            guard let url = URL(string: u) else { return (p, "") }
                            let body = await LedouCGI.get(url: url, cookie: cookie).1
                            return (p, body)
                        }
                    }
                    var map: [Int: String] = [:]
                    for await (p, body) in group { map[p] = body }
                    for p in 2...total {
                        if let body = map[p], !body.isEmpty { rawPages.append(body) }
                    }
                }
            } else {
                var url = nextPageUrl(first, current: base)
                var guardN = 0
                while let u = url, guardN < 19 {
                    guardN += 1
                    guard let abs = URL(string: u) else { break }
                    let body = await LedouCGI.get(url: abs, cookie: cookie).1
                    if body.isEmpty { break }
                    rawPages.append(body)
                    url = nextPageUrl(body, current: u)
                }
            }
            for body in rawPages {
                blocks.append(extractFightBlock(body))
            }
        }

        let knightHtml = knightSummaryHtml
        if blocks.isEmpty {
            let emptyBody = knightHtml.isEmpty
                ? "无战斗过程"
                : knightHtml.trimmingCharacters(in: .whitespacesAndNewlines) + "<br />无战斗过程"
            return Result(
                html: wrapInFirstPageShell(rawPages.first ?? "", emptyBody),
                pages: 0,
                chars: 0
            )
        }

        var nativeFooter = extractNativeFooterRaw(rawPages.last ?? "")
        if nativeFooter.isEmpty {
            nativeFooter = extractNativeFooterRaw(blocks.last ?? "")
        }

        let header = extractHeader(blocks[0])
        var rounds: [String] = []
        var ending = ""
        for (idx, block) in blocks.enumerated() {
            rounds.append(contentsOf: extractRounds(block))
            if idx == blocks.count - 1 {
                ending = extractEnding(block)
            }
        }

        var parts: [String] = []
        if !header.isEmpty { parts.append(header) }
        var seen = Set<String>()
        for r in rounds where seen.insert(r).inserted { parts.append(r) }
        if !ending.isEmpty { parts.append(ending) }

        var merged = parts.joined(separator: "<br />")
        merged = stripFooterAnchorsFromBody(merged)
        merged = stripPagingOnly(merged)
        merged = colorHp(merged)
        merged = collapseBr(merged).trimmingCharacters(in: .whitespacesAndNewlines)

        if !knightHtml.isEmpty {
            merged = stripThinKnightChrome(merged)
            if knightHtml.contains("战斗过程：") || knightHtml.contains("战斗过程:") {
                merged = stripDuplicatePhoneProcess(merged)
            }
            merged = prependKnightSummary(knightHtml, merged)
        } else {
            merged = ensureKnightDetailLink(merged, firstPageHtml: rawPages.first ?? "")
        }

        let html = wrapInFirstPageShell(rawPages.first ?? "", merged, nativeFooter)
        return Result(html: html, pages: blocks.count, chars: merged.count)
    }

    /// 多页拼接用的 phonepk 首页：去掉 page / hide_knight=1。
    static func multipageBase(_ url: String) -> String {
        guard let comps = URLComponents(string: url),
              let id = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty
        else { return url }
        let type = comps.queryItems?.first(where: { $0.name == "type" })?.value
        var c = URLComponents(string: "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk")!
        var items = [
            URLQueryItem(name: "cmd", value: "viewfight"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "hide_knight", value: "0"),
        ]
        if let type, !type.isEmpty {
            items.append(URLQueryItem(name: "type", value: type))
        }
        c.queryItems = items
        return c.url?.absoluteString ?? url
    }

    static func fightId(from url: String) -> String? {
        URLComponents(string: url)?.queryItems?.first(where: { $0.name == "id" })?.value
    }

    static func hideKnightDetail(_ url: String) -> Bool {
        URLComponents(string: url)?.queryItems?.first(where: { $0.name == "hide_knight" })?.value == "1"
    }

    // MARK: - extract / transform

    private static func normalizeUrl(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        if u.hasPrefix("//") { u = "https:" + u }
        return u
    }

    private static func pageUrlWithIndex(_ base: String, page: Int) -> String {
        if base.range(of: #"[?&]page=\d+"#, options: .regularExpression) != nil {
            return base.replacingOccurrences(
                of: #"([?&]page=)\d+"#,
                with: "$1\(page)",
                options: .regularExpression
            )
        }
        return base + (base.contains("?") ? "&" : "?") + "page=\(page)"
    }

    private static func extractFightBlock(_ html: String) -> String {
        if let m = firstGroup(#"<div\s+id=["']id["'][^>]*>([\s\S]*?)</div>"#, in: html, options: .caseInsensitive),
           !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return m.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let body = firstGroup(#"<body[^>]*>([\s\S]*?)</body>"#, in: html, options: .caseInsensitive) {
            let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? html : t
        }
        return html
    }

    private static func extractHeader(_ block: String) -> String {
        let plain = normalizeBreaks(block)
        guard let r = plain.range(of: #"回合\s*\d+\s*[：:]"#, options: .regularExpression) else {
            return stripPagingOnly(stripFooterAnchorsFromBody(plain))
        }
        var h = String(plain[..<r.lowerBound])
        h = stripPagingOnly(stripFooterAnchorsFromBody(h))
        h = h.replacingOccurrences(of: #"(<br\s*/?>\s*)+$"#, with: "", options: .regularExpression)
        return h.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractRounds(_ block: String) -> [String] {
        let text = normalizeBreaks(block)
        let re = try? NSRegularExpression(
            pattern: #"回合\s*\d+\s*[：:][\s\S]*?(?=(?:回合\s*\d+\s*[：:])|(?:战斗结束)|$)"#
        )
        let ns = text as NSString
        let matches = re?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        return matches.compactMap { m -> String? in
            let s = cutAtFooter(ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines))
            return (s.contains("回合") && !s.isEmpty) ? s : nil
        }
    }

    private static func cutAtFooter(_ roundHtml: String) -> String {
        var s = roundHtml
        var cut = s.count
        for k in ["继续乐斗", "返回大乐斗", "下一页", "上一页", "强化", "镶嵌", "经脉", "佣兵"] {
            if let r = s.range(of: k) {
                let i = s.distance(from: s.startIndex, to: r.lowerBound)
                if i > 0, i < cut { cut = i }
            }
        }
        if let aIdx = regexFirstIndex(
            #"<a\s+[^>]*>\s*(?:继续乐斗|返回大乐斗|强化|镶嵌|经脉|佣兵|下一页|上一页)"#,
            in: s
        ) ?? regexFirstIndex(
            #"<a\s+[^>]*href=["'][^"']*cmd=(?:viewupdate|inlaypearl|intfmerid|newmercenary|index)[^"']*["']"#,
            in: s
        ) {
            if aIdx >= 0, aIdx < cut { cut = aIdx }
        }
        cut = rewindPastOpenAnchor(s, cut)
        let end = s.index(s.startIndex, offsetBy: min(cut, s.count))
        s = String(s[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"<a\s+[^>]*>\s*$"#, with: "", options: .regularExpression)
        return s.replacingOccurrences(of: #"(<br\s*/?>\s*)+$"#, with: "", options: .regularExpression)
    }

    private static func rewindPastOpenAnchor(_ html: String, _ cut: Int) -> Int {
        guard cut > 0, cut <= html.count else { return cut }
        let before = String(html.prefix(cut))
        guard let lastOpen = before.range(of: #"<a\s"#, options: [.regularExpression, .backwards]) else {
            return cut
        }
        let segment = String(before[lastOpen.lowerBound...])
        if segment.range(of: #"</a\s*>"#, options: .regularExpression) != nil {
            return cut
        }
        return before.distance(from: before.startIndex, to: lastOpen.lowerBound)
    }

    private static func extractEnding(_ block: String) -> String {
        let text = normalizeBreaks(block)
        guard let m = text.range(of: #"战斗结束[\s\S]*"#, options: .regularExpression) else { return "" }
        var end = String(text[m])
        var cutPos = end.count
        for k in ["继续乐斗", "返回大乐斗", "强化", "下一页", "上一页"] {
            if let r = end.range(of: k) {
                let i = end.distance(from: end.startIndex, to: r.lowerBound)
                if i > 0, i < cutPos { cutPos = i }
            }
        }
        if let pr = end.range(of: #"第\s*\d+\s*/\s*\d+\s*页"#, options: .regularExpression) {
            let i = end.distance(from: end.startIndex, to: pr.lowerBound)
            if i > 0, i < cutPos { cutPos = i }
        }
        if let aIdx = regexFirstIndex(
            #"<a\s+[^>]*href=["'][^"']*cmd=(?:viewupdate|inlaypearl|intfmerid|newmercenary|index|viewfight)[^"']*["']"#,
            in: end
        ) ?? regexFirstIndex(
            #"<a\s+[^>]*>\s*(?:继续乐斗|返回大乐斗|强化|镶嵌|经脉|佣兵|下一页|上一页)"#,
            in: end
        ) {
            if aIdx >= 0, aIdx < cutPos { cutPos = aIdx }
        }
        cutPos = rewindPastOpenAnchor(end, cutPos)
        let idx = end.index(end.startIndex, offsetBy: min(cutPos, end.count))
        end = String(end[..<idx])
            .replacingOccurrences(of: #"<a\s+[^>]*>\s*$"#, with: "", options: .regularExpression)
        return end.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractNativeFooterRaw(_ html: String) -> String {
        let text = html
        let start = regexFirstIndex(
            #"<a\s+[^>]*href=["'][^"']*cmd=viewupdate[^"']*["'][^>]*>"#,
            in: text
        ) ?? regexFirstIndex(
            #"<a\s+[^>]*>\s*强化\s*</a>"#,
            in: text
        ) ?? regexFirstIndex(
            #"<a\s+[^>]*href=["'][^"']*cmd=index[^"']*["'][^>]*>"#,
            in: text
        )
        guard let start else { return "" }
        var footer = String(text[text.index(text.startIndex, offsetBy: start)...])
        let endDiv = regexFirstIndex(#"</div\s*>"#, in: footer)
        let endBody = regexFirstIndex(#"</body\s*>"#, in: footer)
        let endAt = [endDiv, endBody].compactMap { $0 }.min()
        if let endAt, endAt > 0 {
            footer = String(footer.prefix(endAt))
        }
        footer = stripPagingOnly(footer)
        return footer
            .replacingOccurrences(of: #"(<br\s*/?>\s*)+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripPagingOnly(_ html: String) -> String {
        var s = html
        for t in ["上一页", "下一页", "下页"] {
            s = s.replacingOccurrences(
                of: #"<a\s+[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: t) + #"\s*</a>"#,
                with: "",
                options: .regularExpression
            )
        }
        s = s.replacingOccurrences(
            of: #"<a\s+[^>]*href=["'][^"']*cmd=viewfight[^"']*page=\d+[^"']*["'][^>]*>[\s\S]*?</a>"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: #"第?\s*\d+\s*/\s*\d+\s*页"#, with: "", options: .regularExpression)
        return s
    }

    private static func stripFooterAnchorsFromBody(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(
            of: #"<a\s+[^>]*>\s*(?:强化|镶嵌|经脉|佣兵|继续乐斗|返回大乐斗首页|返回大乐斗)\s*</a>"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"<a\s+[^>]*href=["'][^"']*cmd=(?:viewupdate|inlaypearl|intfmerid|newmercenary|index)[^"']*["'][^>]*>[\s\S]*?</a>"#,
            with: "",
            options: .regularExpression
        )
        return s
    }

    private static func normalizeBreaks(_ html: String) -> String {
        html.replacingOccurrences(of: #"<br\s*/?>"#, with: "<br />", options: .regularExpression)
    }

    private static func nextPageUrl(_ html: String, current: String) -> String? {
        if let next = firstGroup(
            #"href=["']([^"']*cmd=viewfight[^"']*page=\d+[^"']*)["'][^>]*>\s*下一页"#,
            in: html,
            options: .caseInsensitive
        ), !next.isEmpty {
            return absolutize(next)
        }
        guard let m = html.range(of: #"(\d+)\s*/\s*(\d+)\s*页"#, options: .regularExpression) else {
            return nil
        }
        let s = String(html[m])
        let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard nums.count >= 2, let cur = Int(nums[0]), let total = Int(nums[1]), cur < total else {
            return nil
        }
        let nextN = cur + 1
        if current.range(of: #"[?&]page=\d+"#, options: .regularExpression) != nil {
            return current.replacingOccurrences(
                of: #"([?&]page=)\d+"#,
                with: "$1\(nextN)",
                options: .regularExpression
            )
        }
        return current + (current.contains("?") ? "&" : "?") + "page=\(nextN)"
    }

    private static func absolutize(_ href: String) -> String {
        var h = href.replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if h.isEmpty { return "" }
        if h.hasPrefix("//") { return "https:" + h }
        if h.hasPrefix("http") { return h }
        if h.hasPrefix("/") { return "https://dld.qzapp.z.qq.com" + h }
        if h.hasPrefix("phonepk") { return "https://dld.qzapp.z.qq.com/qpet/cgi-bin/" + h }
        return h
    }

    private static func colorHp(_ html: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"HP[+\-]?[^<）]*）"#) else { return html }
        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var out = html
        for m in matches.reversed() {
            let whole = ns.substring(with: m.range)
            let colored = whole.contains("+")
                ? "<b><font color='green'>\(whole)</font></b>"
                : "<b><font color='red'>\(whole)</font></b>"
            if let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: colored)
            }
        }
        return out
    }

    private static func collapseBr(_ html: String) -> String {
        html.replacingOccurrences(
            of: #"(?:<br\s*/?>\s*){3,}"#,
            with: "<br /><br />",
            options: .regularExpression
        )
    }

    private static func ensureKnightDetailLink(_ merged: String, firstPageHtml: String) -> String {
        if merged.contains("hide_knight=1"), merged.contains("查看详情") { return merged }
        let link = firstGroup(
            #"(<a\s+[^>]*href=["'][^"']*hide_knight=1[^"']*["'][^>]*>\s*查看详情\s*</a>)"#,
            in: firstPageHtml,
            options: .caseInsensitive
        ) ?? firstGroup(
            #"(<a\s+[^>]*href=["'][^"']*hide_knight=1[^"']*["'][^>]*>[\s\S]*?</a>)"#,
            in: firstPageHtml,
            options: .caseInsensitive
        )
        guard let link else { return merged }
        let win = firstGroup(#"(侠士战[^<]{0,48}获胜[：:]?)"#, in: firstPageHtml) ?? ""
        var insert = ""
        if !win.isEmpty, !merged.contains(win) { insert += win }
        insert += link + "<br />"
        if let r = merged.range(of: #"回合\s*\d+\s*[：:]"#, options: .regularExpression),
           r.lowerBound > merged.startIndex
        {
            return String(merged[..<r.lowerBound]) + insert + String(merged[r.lowerBound...])
        }
        return insert + merged
    }

    private static let knightMarkStart = "<!--dld-knight-summary-->"
    private static let knightMarkEnd = "<!--/dld-knight-summary-->"

    private static func prependKnightSummary(_ summary: String, _ body: String) -> String {
        let filtered = body
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .filter { !$0.contains("参战角色：") }
            .joined(separator: "<br />")
        let clean = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(<br\s*/?>\s*)+$"#, with: "", options: .regularExpression)
        return knightMarkStart
            + #"<div style="font-size:14px;line-height:1.35;">\#(clean)</div>"#
            + knightMarkEnd
            + "<br /><br />"
            + filtered
    }

    /// 后台技能名解析完成后，只替换侠士摘要块，避免重拉多页。
    static func replaceKnightSummary(in html: String, with summary: String) -> String? {
        guard let s = html.range(of: knightMarkStart),
              let e = html.range(of: knightMarkEnd)
        else { return nil }
        let clean = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(<br\s*/?>\s*)+$"#, with: "", options: .regularExpression)
        let block = knightMarkStart
            + #"<div style="font-size:14px;line-height:1.35;">\#(clean)</div>"#
            + knightMarkEnd
        return html.replacingCharacters(in: s.lowerBound..<e.upperBound, with: block)
    }

    private static func stripThinKnightChrome(_ html: String) -> String {
        var s = html
        for pat in [
            #"<a\s+[^>]*>\s*查看详情\s*</a>"#,
            #"<a\s+[^>]*>\s*查看侠士战斗记录\s*</a>"#,
            #"<a\s+[^>]*>\s*去查看完整的侠士战斗过程\s*</a>"#,
        ] {
            s = s.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"侠士战[^<]{0,40}获胜"#, with: "", options: .regularExpression)
        return collapseBr(s)
    }

    private static func stripDuplicatePhoneProcess(_ html: String) -> String {
        var s = html.replacingOccurrences(
            of: #"侠士战斗过程如下\s*[：:][\s\S]*?(?=(?:【乐斗过程】)|(?:战斗结束)|$)"#,
            with: "",
            options: .regularExpression
        )
        let hasBenti = s.range(
            of: #"你(?:使用了|使出|身形|双指|凝神|触发|挥|持|吃了一招|被击中|中招)"#,
            options: .regularExpression
        ) != nil
        if !hasBenti {
            let footerAt = regexFirstIndex(
                #"<a\s+[^>]*(?:cmd=viewupdate|继续乐斗|返回大乐斗|强化)"#,
                in: s
            )
            let ending = firstGroup(#"(战斗结束[\s\S]*)"#, in: s) ?? ""
            if let footerAt, footerAt > 0 {
                let foot = String(s[s.index(s.startIndex, offsetBy: footerAt)...])
                if !ending.isEmpty, !foot.contains("战斗结束") {
                    return collapseBr(ending + "<br />" + foot)
                }
                return collapseBr(foot)
            }
            if !ending.isEmpty { return collapseBr(ending) }
            return ""
        }
        if let ledou = s.range(of: "【乐斗过程】"), ledou.lowerBound > s.startIndex {
            let before = String(s[..<ledou.lowerBound])
                .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
                .components(separatedBy: "\n")
                .filter {
                    !$0.contains("回合") && !$0.contains("侠士战斗过程") && !$0.contains("去查看完整")
                }
                .joined(separator: "<br />")
            s = before + String(s[ledou.lowerBound...])
        }
        return collapseBr(s)
    }

    private static func wrapInFirstPageShell(
        _ firstPageHtml: String,
        _ inner: String,
        _ footerNative: String = ""
    ) -> String {
        let foot = footerNative.isEmpty ? "" : "<br />\(footerNative)"
        let sizedInner = #"<div style="font-size:14px;line-height:1.35;">\#(inner)</div>\#(foot)"#
        if firstPageHtml.isEmpty {
            return wrapSingleDocument(inner, footerNative)
        }
        if let re = try? NSRegularExpression(
            pattern: #"(<div\s+id=["']id["'][^>]*>)([\s\S]*?)(</div>)"#,
            options: .caseInsensitive
        ) {
            let ns = firstPageHtml as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = re.firstMatch(in: firstPageHtml, range: range), m.numberOfRanges >= 4 {
                let open = ns.substring(with: m.range(at: 1))
                let close = ns.substring(with: m.range(at: 3))
                let replaced = ns.replacingCharacters(in: m.range, with: open + sizedInner + close)
                return replaced
            }
        }
        if let re = try? NSRegularExpression(
            pattern: #"(<body[^>]*>)([\s\S]*?)(</body>)"#,
            options: .caseInsensitive
        ) {
            let ns = firstPageHtml as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = re.firstMatch(in: firstPageHtml, range: range), m.numberOfRanges >= 4 {
                let open = ns.substring(with: m.range(at: 1))
                let close = ns.substring(with: m.range(at: 3))
                return ns.replacingCharacters(in: m.range, with: open + sizedInner + close)
            }
        }
        return wrapSingleDocument(inner, footerNative)
    }

    private static func wrapSingleDocument(_ inner: String, _ footerNative: String) -> String {
        let foot = footerNative.isEmpty ? "" : "<br />\(footerNative)"
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>乐斗过程</title>
        <style>body{font-size:14px;line-height:1.35;}</style>
        </head><body><div style="font-size:14px;line-height:1.35;">\(inner)</div>\(foot)</body></html>
        """
    }

    // MARK: - regex helpers

    private static func firstGroup(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func regexFirstIndex(_ pattern: String, in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return m.range.location
    }
}
