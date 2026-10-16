import Foundation

/// 真源：`MoreExtraActions.farmWuLinChiYao` — totalinfo 剩 0 次再 use。
enum WuLinChiYaoActions {
    static let fid = "wulin_chiyao"
    private static let gapNs: UInt64 = 80_000_000

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        func on(_ key: String) -> Bool { t.getBool(fid, key) }

        let (_, info) = await LedouCGI.getPhonePk(
            cmd: "totalinfo", extra: ["type": "1"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)

        if on("cb_not_0"),
           info.contains("最近参赛成绩：冠军") || info.contains("总冠军")
        {
            let tip = "冠军后不执行监听"
            onLog(tip)
            t.setEnabled(fid, false)
            return tip
        }

        onLog("武林吃药开始")
        if buffZero(info, "大力丸") {
            if on("cb_dlw_z") { await useItem("3020", "大力丸(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_dlw") { await useItem("3016", "大力丸", cookie: cookie, onLog: onLog) }
        }
        if buffZero(info, "迅捷珠") {
            if on("cb_xjz_z") { await useItem("3021", "迅捷珠(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_xjz") { await useItem("3017", "迅捷珠", cookie: cookie, onLog: onLog) }
        }
        if buffZero(info, "风之息") {
            if on("cb_fzx_z") { await useItem("3022", "风之息(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_fzx") { await useItem("3018", "风之息", cookie: cookie, onLog: onLog) }
        }
        if buffZero(info, "活血散"), on("cb_hxs") {
            await useItem("3004", "活血散", cookie: cookie, onLog: onLog)
        }
        if buffZero(info, "土豪金"), on("cb_thj") {
            await useItem("3382", "土豪金", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "减伤药水"), on("cb_jsys") {
            await useItem("3399", "减伤药水", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "金疮药"), on("cb_jcy") {
            await useItem("3006", "金疮药", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "大金疮药"), on("cb_djcy") {
            await useItem("3398", "大金疮药", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "宝石金戒"), on("cb_bsjj") {
            await useItem("3411", "宝石金戒", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "翡翠银戒"), on("cb_fcyj") {
            await useItem("3412", "翡翠银戒", cookie: cookie, onLog: onLog)
        }
        if buffMissing(info, "永恒紫钻"), on("cb_yhzz") {
            await useItem("3410", "永恒紫钻", cookie: cookie, onLog: onLog)
        }

        if on("cb_da_tie") {
            let (_, st) = await LedouCGI.getPetPk(
                cmd: "blacksmith", extra: ["op": "5"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let desc = field(st, "buff_time_desc")
            if desc == "未激活" || st.contains("未激活") {
                let (_, set) = await LedouCGI.getPetPk(
                    cmd: "blacksmith",
                    extra: ["op": "3", "type_id": "3", "first_pay_steel": "1"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("百炼钢：\(CombatLog.fromBody(set).ifBlankMe("设置"))")
                let (_, hit) = await LedouCGI.getPetPk(
                    cmd: "blacksmith",
                    extra: ["op": "4", "type_id": "3", "times": "1"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("打铁：\(CombatLog.fromBody(hit).ifBlankMe("已请求"))")
            } else {
                onLog("打铁：\(desc.isEmpty ? CombatLog.fromBody(st).ifBlankMe("已激活或无需") : desc)")
            }
        }

        let tip = "武林吃药结束"
        onLog(tip)
        return tip
    }

    private static func useItem(
        _ id: String,
        _ label: String,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async {
        let uin = LoginURLs.extractQq(cookie) ?? ""
        if uin.isEmpty {
            onLog("\(label)：未识别 selfuin")
            return
        }
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "use", extra: ["selfuin": uin, "id": id], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        onLog("\(label)：\(CombatLog.fromBody(r).ifBlankMe("已请求\(id)"))")
    }

    private static func buffZero(_ html: String, _ name: String) -> Bool {
        let line = html.split(whereSeparator: { $0 == "\n" || $0 == "<" })
            .map(String.init)
            .first(where: { $0.contains(name) })
            ?? (html.contains(name) ? html : nil)
        guard let line else { return false }
        return line.contains("剩0次") || line.contains("剩 0 次")
    }

    private static func buffMissing(_ html: String, _ name: String) -> Bool {
        !html.contains(name)
    }

    private static func field(_ body: String, _ key: String) -> String {
        let re = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]*)\""
        )
        let ns = body as NSString
        if let m = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return ""
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
