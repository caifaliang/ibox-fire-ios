import Foundation

/// 对齐参考 XinXiActivity.R1 / WuQiActivity 查询链路（仅腾讯域）。
enum QueryRepository {

    // MARK: - Public API

    static func query(uin: String, selfUin: String?, cookie: String) async -> QueryProfile {
        async let visitR = LedouCGI.getPetPk(cmd: "visit", extra: ["puin": uin, "kind": "1"], cookie: cookie)
        async let attrR = LedouCGI.getPetPk(cmd: "viewattr", extra: ["puin": uin, "kind": "1"], cookie: cookie)
        async let rankR = LedouCGI.getPetPk(cmd: "rank", extra: ["kind": "5", "other": uin], cookie: cookie)
        async let mercR = LedouCGI.getPetPk(cmd: "newmercenary", extra: ["sub": "1", "uin": uin], cookie: cookie)
        async let formR = LedouCGI.getPetPk(cmd: "formation", extra: ["type": "4", "uin": uin], cookie: cookie)
        async let meridR = LedouCGI.getPetPk(cmd: "intfmerid", extra: ["uin": uin], cookie: cookie)
        async let outfitR = LedouCGI.getPetPk(cmd: "outfit", extra: ["op": "0", "target_uin": uin], cookie: cookie)
        async let zjR = LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "10", "op_uin": uin], cookie: cookie)
        async let achR = LedouCGI.getPetPk(cmd: "achievement", extra: ["kind": "1", "uin": uin], cookie: cookie)
        async let skillR = LedouCGI.getPhonePk(
            cmd: "view",
            extra: ["B_UID": uin, "type": "0"],
            cookie: cookie
        )
        async let weaponR = LedouCGI.getPhonePk(
            cmd: "view",
            extra: ["B_UID": uin, "type": "2"],
            cookie: cookie
        )

        let visitBody = (await visitR).1.replacingOccurrences(of: "\\速度高于对手时", with: "速度高于对手时")
        let attrBody = (await attrR).1
        let rankBody = (await rankR).1
        let mercBody = (await mercR).1
        let formBody = (await formR).1
        let meridBody = (await meridR).1
        let outfitBody = (await outfitR).1
        let zjBody = (await zjR).1
        let achBody = (await achR).1
        let skillHtml = (await skillR).1
        let weaponHtml = (await weaponR).1

        if visitBody.contains("登陆校验失败") || attrBody.contains("登陆校验失败") {
            return QueryProfile(
                uin: uin,
                cookieOk: false,
                rawError: "Cookie 无效或已过期（登陆校验失败）",
                header: HeaderInfo(avatarUrl: qqAvatar(uin))
            )
        }

        let visit = parseObj(visitBody)
        let attr = parseObj(attrBody)
        let rank = parseObj(rankBody)
        let merc = parseObj(mercBody)
        let form = parseObj(formBody)
        let merid = parseObj(meridBody)
        let outfit = parseObj(outfitBody)
        let zj = parseObj(zjBody)
        let ach = parseObj(achBody)

        let header = parseHeader(uin: uin, visit: visit, attr: attr)
        let xinxiBase = parseXinXiBase(visit: visit)
        let baseAttrBlock = parseBaseAttrBlock(attr: attr)
        let badges = parseBadges(visit: visit, ach: ach)
        var weapons = parseWeaponsFromVisit(visit: visit)
        if weapons.isEmpty { weapons = parseWeaponsFromHtml(html: weaponHtml) }

        if let selfUin, !selfUin.isEmpty, selfUin == uin {
            weapons = attachFushi(weapons: weapons, fushiList: await fetchFushiBodies(cookie: cookie))
        }

        let weaponSummary = buildWeaponSummary(weapons: weapons)
        let skills = parseSkillsFromVisit(visit: visit)
        let mercBlock = parseMerc(merc: merc)
        let mercFormation = parseFormation(form: form)
        let jingMai = parseJingMai(merid: merid)
        let zhuanJing = parseZhuanJing(zj: zj)
        let shenZhuang = parseShenZhuang(outfit: outfit)
        let skillPage = await parseSkillHtml(html: skillHtml, uin: uin, cookie: cookie)
        let attrsText = parseAttrs(attr: attr)
        let power = parsePower(rank: rank)

        return QueryProfile(
            uin: uin,
            cookieOk: true,
            header: header,
            xinxiBase: xinxiBase,
            baseAttrBlock: baseAttrBlock,
            badges: badges,
            weapons: weapons,
            weaponSummary: weaponSummary,
            skillsHtmlLines: skills,
            mercOnField: mercBlock.on,
            mercAll: mercBlock.all,
            mercTalent: mercBlock.talent,
            mercTough: mercBlock.tough,
            mercFormation: mercFormation,
            jingMai: jingMai,
            zhuanJing: zhuanJing,
            shenZhuang: shenZhuang,
            shenJiang: skillPage.shenJiang,
            aoYi: skillPage.aoYi,
            luanDou: skillPage.luanDou,
            shenMo: skillPage.shenMo,
            shenMoDing: skillPage.shenMoDing,
            attrsText: attrsText,
            powerRank: power.rank,
            powerLeft: power.left,
            powerRight: power.right
        )
    }

    static func addFriend(uin: String, cookie: String) async -> String {
        guard let url = URL(string: "\(LedouCGI.petpkBase)?cmd=friend_change&op=addfriend&oppuin=\(uin)") else {
            return "URL 无效"
        }
        let (_, body) = await LedouCGI.get(url: url, cookie: cookie, referer: LedouCGI.petpkBase)
        let msg = parseObj(body)?.str("msg").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !msg.isEmpty { return msg }
        let short = String(body.prefix(80))
        return short.isEmpty ? "无返回" : short
    }

    static func formatCombat(_ v: Double) -> String {
        combatFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    static func qqAvatar(_ uin: String) -> String {
        "https://q.qlogo.cn/g?b=qq&nk=\(uin)&s=100"
    }

    // MARK: - Private types

    private struct MercBlock {
        var on: String = ""
        var all: String = ""
        var talent: String = ""
        var tough: String = ""
    }

    private struct SkillPage {
        var shenJiang: String = ""
        var aoYi: String = ""
        var luanDou: String = ""
        var shenMo: String = ""
        var shenMoDing: String = ""
    }

    private struct PowerBlock {
        var rank: String = ""
        var left: [(String, String)] = []
        var right: [(String, String)] = []
    }

    private struct Acc {
        var v: Double = 0
        var from: [String] = []
    }

    // MARK: - Constants

    private static let shenJiangSkill = [
        "以武止戈", "侠之大者", "燕人之怒", "它如流星", "冬至天节", "无厘头", "九霄风雷", "南帝朱雀",
        "新年快乐", "墨守成规", "灵魂献祭", "言灵", "积炎切割", "神威雷切", "蓄意灭杀", "游龙圣体",
        "冠军威压", "极致抢断", "时之守护", "最终火药", "生杀制裁", "笔落惊鸿", "西楚龙魂", "天命之子",
        "三昧真火", "狂风绝息", "地狱之裔", "利刃纵贯", "盘古之怒", "重装战士", "至高生命", "奥丁之子",
        "海王", "功夫熊猫", "号令天下", "精武英雄", "秀色可餐", "剑气凛然", "温候变身", "武圣变身",
    ]
    private static let shenJiangName = [
        "爆风9C", "郭靖", "燕人张飞", "奥丁", "虚日鼠", "周", "天蓬", "雀星宿", "新春游侠", "可乐游侠",
        "猎魔人", "圣骑士", "红莲", "鹅卡西", "帝辛", "蠃政", "冠军炫炫", "天才樱木", "诗仙李白", "小丑",
        "武则天", "杨玉环", "项羽", "刘邦", "哪吒", "姜子牙", "死神", "死亡骑士", "盘古", "机甲战士",
        "灭世", "雷神托尔", "海王波塞冬", "熊猫潘达", "金毛狮王", "帅帅大侠", "菜菜大侠", "剑君大侠",
        "温候吕布", "武圣关羽",
    ]
    private static let aoYi = [
        "影刃乱舞", "神之泪影", "蟠龙翻江", "龙魂风暴", "恐惧洪流", "弹指神通", "瞬杀冲锋", "狮吼功",
        "移形换影", "杨柳甘露", "吉人天相", "三花聚顶", "青龙守护", "玄武守护", "白虎守护", "朱雀守护",
    ]
    private static let siLingRatio = [
        "减免比例为20%", "减免比例为21%", "减免比例为22%", "减免比例为23%", "减免比例为24%",
        "减免比例为25%", "减免比例为26%", "减免比例为27%", "减免比例为28%", "减免比例为29%",
        "减免比例为30%", "减免比例为32%", "减免比例为34%", "减免比例为36%", "减免比例为38%",
        "减免比例为40%", "减免比例为42%", "减免比例为44%", "减免比例为46%", "减免比例为49%",
        "减免比例为52%", "减免比例为55%", "减免比例为58%", "减免比例为61%", "减免比例为64%",
        "减免比例为67%", "减免比例为70%", "减免比例为73%", "减免比例为76%", "减免比例为80%",
    ]
    private static let siLingGrade = [
        "1-0", "1-1", "1-2", "1-3", "1-4", "1-5",
        "2-0", "2-1", "2-2", "2-3", "2-4", "2-5",
        "3-0", "3-1", "3-2", "3-3", "3-4", "3-5",
        "4-0", "4-1", "4-2", "4-3", "4-4", "4-5",
        "5-0", "5-1", "5-2", "5-3", "5-4", "5-5",
    ]
    private static let aoYiDmgA = [
        "造成50", "造成56", "造成64", "造成73", "造成84", "造成97",
        "造成113", "造成131", "造成150", "造成171", "造成200",
    ]
    private static let aoYiDmgB = [
        "造成150", "造成162", "造成174", "造成192", "造成216", "造成246",
        "造成276", "造成312", "造成348", "造成390", "造成450",
    ]
    private static let aoYiDmgC = [
        "造成50点伤害，额外增加自身速度", "造成56点伤害，额外增加自身速度", "造成64点伤害，额外增加自身速度",
        "造成73点伤害，额外增加自身速度", "造成84点伤害，额外增加自身速度", "造成97点伤害，额外增加自身速度",
        "造成113点伤害，额外增加自身速度", "造成131点伤害，额外增加自身速度", "造成150点伤害，额外增加自身速度",
        "造成171点伤害，额外增加自身速度", "造成200点伤害，额外增加自身速度",
    ]
    private static let aoYiDmgD = [
        "造成150点伤害，并且降低对手韧性31%持续2回合", "造成162点伤害，并且降低对手韧性32%持续2回合",
        "造成174点伤害，并且降低对手韧性34%持续2回合", "造成192点伤害，并且降低对手韧性37%持续2回合",
        "造成216点伤害，并且降低对手韧性41%持续2回合", "造成246点伤害，并且降低对手韧性46%持续2回合",
        "造成276点伤害，并且降低对手韧性51%持续3回合", "造成312点伤害，并且降低对手韧性57%持续3回合",
        "造成348点伤害，并且降低对手韧性63%持续3回合", "造成390点伤害，并且降低对手韧性70%持续3回合",
        "造成450点伤害，并且降低对手韧性80%持续3回合",
    ]
    private static let aoYiDmgE = [
        "造成100+", "造成112+", "造成124+", "造成142+", "造成166+", "造成196+",
        "造成226+", "造成262+", "造成298+", "造成340+", "造成400+",
    ]
    private static let aoYiDmgF = [
        "造成150点伤害，自身速度提升15%持续2回合", "造成162点伤害，自身速度提升16%持续2回合",
        "造成174点伤害，自身速度提升18%持续2回合", "造成192点伤害，自身速度提升20%持续2回合",
        "造成216点伤害，自身速度提升22%持续2回合", "造成246点伤害，自身速度提升25%持续3回合",
        "造成276点伤害，自身速度提升27%持续3回合", "造成312点伤害，自身速度提升30%持续3回合",
        "造成348点伤害，自身速度提升33%持续3回合", "造成390点伤害，自身速度提升36%持续3回合",
        "造成450点伤害，自身速度提升40%持续3回合",
    ]
    private static let aoYiHealA = [
        "恢复150点生命，自身减伤和速度+30%持续2回合，下次被攻击时增加50%闪避率。",
        "恢复156点生命，自身减伤和速度+30%持续2回合，下次被攻击时增加52%闪避率。",
        "恢复164点生命，自身减伤和速度+30%持续2回合，下次被攻击时增加54%闪避率。",
        "恢复173点生命，自身减伤和速度+30%持续2回合，下次被攻击时增加57%闪避率。",
        "恢复184点生命，自身减伤和速度+40%持续2回合，下次被攻击时增加61%闪避率。",
        "恢复197点生命，自身减伤和速度+40%持续3回合，下次被攻击时增加66%闪避率。",
        "恢复213点生命，自身减伤和速度+40%持续3回合，下次被攻击时增加71%闪避率。",
        "恢复231点生命，自身减伤和速度+50%持续3回合，下次被攻击时增加77%闪避率。",
        "恢复250点生命，自身减伤和速度+50%持续3回合，下次被攻击时增加83%闪避率。",
        "恢复271点生命，自身减伤和速度+50%持续3回合，下次被攻击时增加90%闪避率。",
        "恢复300点生命，自身减伤和速度+50%持续3回合，下次被攻击时增加100%闪避率。",
    ]
    private static let aoYiHealB = [
        "恢复200点+3%的生命", "恢复212点+3%的生命", "恢复224点+3%的生命", "恢复242点+3%的生命",
        "恢复266点+6%的生命", "恢复296点+6%的生命", "恢复326点+6%的生命", "恢复362点+9%的生命",
        "恢复398点+9%的生命", "恢复440点+9%的生命", "恢复500点+10%的生命",
    ]
    private static let aoYiHealC = [
        "恢复250点生命，被攻击时大幅降低暴击概率", "恢复256点生命，被攻击时大幅降低暴击概率",
        "恢复264点生命，被攻击时大幅降低暴击概率", "恢复273点生命，被攻击时大幅降低暴击概率",
        "恢复284点生命，被攻击时大幅降低暴击概率", "恢复297点生命，被攻击时大幅降低暴击概率",
        "恢复313点生命，被攻击时大幅降低暴击概率", "恢复331点生命，被攻击时大幅降低暴击概率",
        "恢复350点生命，被攻击时大幅降低暴击概率", "恢复371点生命，被攻击时大幅降低暴击概率",
        "恢复400点生命，被攻击时大幅降低暴击概率",
    ]
    private static let aoYiHealD = [
        "恢复250点生命+等级", "恢复262点生命+等级", "恢复274点生命+等级", "恢复292点生命+等级",
        "恢复316点生命+等级", "恢复346点生命+等级", "恢复376点生命+等级", "恢复412点生命+等级",
        "恢复448点生命+等级", "恢复490点生命+等级", "恢复550点生命+等级",
    ]
    private static let aoYiGuardA = [
        "51%", "52%", "54%", "57%", "61%", "66%", "71%", "77%", "83%", "90%", "100%",
    ]
    private static let aoYiGuardB = [
        "21%", "22%", "23%", "25%", "27%", "30%", "33%", "37%", "41%", "45%", "50%",
    ]
    private static let luanDou = ["空手反制", "武器感知", "技巧感知", "魔能亲和", "神兵共鸣", "灵光一现"]
    private static let shenMo = ["古阵之蕴", "神魔护盾", "八荒之境", "灵兽清啸", "上古神佑"]
    private static let shenMoDing = ["夔牛鼓", "饕餮鼎", "烛龙印", "黄鸟伞"]

    private static let cuiHuo: Set<String> = [
        "青龙偃月刀", "盘古开天斧", "雷神之锤", "死神之镰", "盘龙之戟", "蒸汽重锤", "海洋之心", "真·斗战神剑",
        "定海神针", "降妖宝杖", "加特林", "穿刺之枪", "龙武之魂", "龙脊", "老虎凳", "射雕神弓", "圣道之剑",
        "死亡之翼", "双持狂战斧", "生死簿", "钟馗道剑", "鸭爪叉", "蛟龙水枪", "万磁头盔", "黄金酒桶",
        "月光宝盒", "沙漠之鹰", "可乐终结者", "王牌飞行鼠", "老虎鸡", "螺旋手里剑", "暴雨梨花针",
        "奇妙种子", "玲珑宝塔", "扑克王", "缚龙仙绳", "核弹", "贯星长枪",
    ]
    private static let jingLiang: Set<String> = [
        "佛跳墙", "九齿钉耙", "传说之杖", "祥云火炬", "豪华午餐", "大夏龙雀", "光剑", "合金钻头",
        "我的篮球鞋", "砖家之怒",
    ]

    private static let formOrder = [
        "生命", "力量", "敏捷", "速度", "大型伤害", "大型减免", "抗大型穿透", "中型伤害", "中型减免",
        "抗中型穿透", "小型伤害", "小型减免", "抗小型穿透", "投掷伤害", "投掷减免", "抗投掷武器穿透",
        "技能伤害", "技能减免", "抗技能穿透", "空手伤害", "空手减免", "暴击", "减暴", "暴击伤害",
        "暴击减免", "命中", "闪避",
    ]
    private static let talentShort: [String: String] = [
        "增加人物被动属性全类型武器穿透": "武器穿透",
        "增加人物被动属性全类型武器抗穿透": "抗武器穿透",
        "增加人物被动属性生命值": "生命",
        "增加人物被动属性力量": "力量",
        "力量": "力量",
        "增加人物被动属性敏捷": "敏捷",
        "增加人物被动属性速度": "速度",
        "增加人物被动属性武器吸血比例": "吸血",
        "增加人物被动属性大型武器穿透": "大穿",
        "增加人物抗投掷武器韧性": "抗投韧",
        "增加人物被动属性大型武器伤害": "大伤",
        "增加人物被动属性小型武器减免": "小减",
        "增加人物被动属性投掷武器伤害": "投掷伤",
        "增加人物被动属性大型武器减免": "大减",
        "增加人物被动属性中型武器减免": "中减",
        "增加人物被动属性抗小型武器韧性": "抗小韧",
        "增加人物被动属性技能韧性": "技能韧",
        "增加人物被动属性抗中型武器韧性": "抗中韧",
        "增加人物被动属性中型武器伤害": "中伤",
        "增加人物被动属性投掷武器减免": "投掷减",
        "增加人物被动属性抗投掷武器韧性": "抗投韧",
        "增加人物被动属性抗大型武器韧性": "抗大韧",
        "增加所有伤害技能佣兵的技能减免固定值": "佣兵固减",
        "增加所有佣兵技能减免固定值": "佣兵固减",
        "增加所有佣兵技能韧性": "佣兵韧性",
        "增加所有佣兵技能抗韧性": "佣兵抗韧",
        "增加所有伤害技能佣兵技能暴击": "佣兵暴击",
        "增加所有伤害技能佣兵的技能暴击": "佣兵暴击",
        "增加所有伤害技能佣兵的技能减免百分比": "佣兵减%",
        "增加所有佣兵技能伤害百分比": "佣兵伤%",
        "增加佣兵技能伤害": "佣兵伤%",
        "增加所有伤害技能佣兵的技能伤害百分比": "佣兵伤%",
        "增加所有伤害技能佣兵的技能伤害固定值": "佣兵固伤",
        "增加所有佣兵技能伤害固定值": "佣兵固伤",
        "增加所有佣兵主动技能治疗效果": "佣兵治疗",
        "增加所有伤害技能佣兵的技能抗暴击": "佣兵抗暴",
    ]
    private static let formShort: [String: String] = [
        "生命": "生命", "力量": "力量", "敏捷": "敏捷", "速度": "速度",
        "大型伤害": "大型伤害", "大型减免": "大型减免", "抗大型穿透": "抗大型穿透",
        "中型伤害": "中型伤害", "中型减免": "中型减免", "抗中型穿透": "抗中型穿透",
        "小型伤害": "小型伤害", "小型减免": "小型减免", "抗小型穿透": "抗小型穿透",
        "投掷伤害": "投掷伤害", "投掷减免": "投掷减免", "抗投掷武器穿透": "抗投掷武器穿透",
        "技能伤害": "技能伤害", "技能减免": "技能减免", "抗技能穿透": "抗技能穿透",
        "空手伤害": "空手伤害", "空手减免": "空手减免",
        "暴击": "暴击", "减暴": "减暴", "暴击伤害": "暴击伤害", "暴击减免": "暴击减免",
        "命中": "命中", "闪避": "闪避",
    ]
    private static let meridAttr: [Int: String] = [
        1: "命中", 2: "闪避", 3: "暴击", 4: "暴击伤害", 5: "减暴", 6: "暴击减免",
        7: "技能伤害", 8: "技能减免", 9: "大型伤害", 10: "大型减免", 11: "中型伤害",
        12: "中型减免", 13: "投掷/小型伤害", 14: "投掷/小型减免", 15: "生命", 16: "力量",
        17: "速度", 18: "敏捷", 34: "技能穿透", 35: "大型穿透", 36: "中型穿透",
        37: "投掷/小型穿透", 38: "空手伤害", 39: "空手减免", 109: "大型韧性",
        110: "中型韧性", 113: "技能韧性", 114: "抗大型韧性", 115: "抗中型韧性",
        118: "抗技能韧性", 119: "小型和投掷韧性", 120: "抗小型和投掷韧性",
    ]
    private static let meridDiv10: Set<Int> = [1, 2, 3, 4, 5, 6, 34, 35, 36, 37, 109, 110, 113, 114, 115, 118, 119, 120]

    private static let combatFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.minimumIntegerDigits = 1
        f.decimalSeparator = "."
        return f
    }()

    private static let talentPat = try! NSRegularExpression(
        pattern: "(.+?)(\\d+(?:\\.\\d+)?)%?([\\u4e00-\\u9fa5]*)"
    )
    private static let formPat = try! NSRegularExpression(
        pattern: "^(.+?)([+-]?\\d+(?:\\.\\d+)?)(%?)$"
    )
    private static let weaponIdPat = try! NSRegularExpression(pattern: "[&?]id=(\\d+)")
    private static let aoYiLevelPat = try! NSRegularExpression(pattern: #"等级\s*[：:]?\s*(\d{1,2})"#)
    private static let skillHrefIdPat = try! NSRegularExpression(pattern: #"(?:[?&]id=)([^&"'<>\s]+)"#)

    // MARK: - Fetch helpers

    private static func fetchFushiBodies(cookie: String) async -> [[String: Any]] {
        let types = ["8", "2", "1", "16"]
        return await withTaskGroup(of: [String: Any]?.self) { group in
            for t in types {
                group.addTask {
                    let (_, body) = await LedouCGI.getPetPk(
                        cmd: "weapongod",
                        extra: ["weapon_type": t, "sub": "1"],
                        cookie: cookie
                    )
                    guard let obj = parseObj(body), obj.int("result") == 0 else { return nil }
                    return obj
                }
            }
            var out: [[String: Any]] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
    }

    private static func attachFushi(weapons: [WeaponItem], fushiList: [[String: Any]]) -> [WeaponItem] {
        if fushiList.isEmpty { return weapons }
        return weapons.map { w in
            if w.weaponId <= 0 { return w }
            let targetId = w.weaponId + 1000
            var text = ""
            for fs in fushiList {
                guard let arr = fs.arr("weapon_array") else { continue }
                for el in arr {
                    if el.int("id") != targetId { continue }
                    guard let holes = el.arr("hole_array") else { continue }
                    text = holes.map { ho in
                        let stone = ho.obj("stone_str")
                        let name = stone?.str("stone_name") ?? ""
                        let lv = ho.int("level")
                        return name.isEmpty ? "" : "[\(name)+\(lv)]"
                    }.joined()
                    break
                }
                if !text.isEmpty { break }
            }
            if text.isEmpty { return w }
            var copy = w
            copy.fushi = text
            return copy
        }
    }

    // MARK: - Parsers

    private static func parseHeader(uin: String, visit: [String: Any]?, attr: [String: Any]?) -> HeaderInfo {
        let base = visit?.obj("baseinfo")
        let nickname = firstNonBlank(attr?.str("nickname"), base?.str("name")) ?? "?"
        let level = attr?.int("level") ?? base?.int("lilian") ?? 0
        let combat = (attr?.double("combat") ?? base?.double("combat") ?? 0) / 10.0
        let menpai = attr?.arr("menpai")?
            .first(where: { $0.str("name") == "当前所属门派" })?
            .str("value") ?? ""
        let attrs = attr?.arr("baseattr")?.map { ($0.str("name"), $0.str("value")) } ?? []
        func av(_ n: String) -> String {
            attrs.first(where: { $0.0 == n })?.1.components(separatedBy: " +").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return HeaderInfo(
            nickname: nickname,
            level: level,
            combat: combat,
            menpai: menpai,
            arenaRank: attr?.str("arena_rank") ?? "",
            faction: base?.str("factionname") ?? "",
            strong: firstNonBlank(base?.str("strong"), av("力量")) ?? "",
            minjie: firstNonBlank(base?.str("minjie"), av("敏捷")) ?? "",
            speed: firstNonBlank(base?.str("speed"), av("速度")) ?? "",
            hp: firstNonBlank(base?.str("hp"), av("生命")) ?? "",
            avatarUrl: qqAvatar(uin)
        )
    }

    private static func parseXinXiBase(visit: [String: Any]?) -> String {
        guard let b = visit?.obj("baseinfo") else { return "" }
        let boss: String = {
            switch b.int("isboss") {
            case 0: return "帮众"
            case 1: return "帮主"
            case 2: return "副帮主"
            case 3: return "护法"
            case 4: return "长老"
            case 5: return "堂主"
            case 6: return "精英"
            default: return ""
            }
        }()
        var fac = b.str("factionname")
        var role = boss
        if fac.isEmpty {
            fac = "独步江湖中。。。"
            role = ""
        }
        var lines: [String] = []
        lines.append("达人：\(b.str("darenflag"))")
        lines.append("帮派：\(fac)(ID:\(b.str("factionid")))")
        lines.append("职位：\(role)")
        lines.append("升级经验：\(b.str("maxexp"))")
        lines.append("武林：\(b.str("joinground"))")
        let manorName = visit?.obj("manor")?.str("name") ?? ""
        if !manorName.isEmpty { lines.append("地盘：\(manorName)") }
        let title = b.str("attrtitle")
        let titleDesc = b.str("attrtitleDesc")
        if !title.isEmpty { lines.append("\(title)(\(titleDesc))") }
        visit?.arr("status")?.forEach { o in
            lines.append("\(o.str("name"))(\(o.str("times")))")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseBaseAttrBlock(attr: [String: Any]?) -> String {
        guard let attr, attr.int("result") == 0 else { return "" }
        var lifeCoef = ""
        var lines: [String] = []
        attr.arr("baseattr")?.forEach { o in
            var name = o.str("name")
            let value = o.str("value")
            let parts = value.components(separatedBy: " + ")
            switch name {
            case "生命":
                name = "血"
                if let base = Double(parts.first ?? ""), attr.int("level") > 1 {
                    lifeCoef = String(format: "生命系数：%.3f", (base - 65.0) / Double(attr.int("level") - 1))
                }
            case "力量": name = "力"
            case "敏捷": name = "敏"
            case "速度": name = "速"
            default: break
            }
            let sum: String = {
                guard parts.count > 1 else { return "" }
                let total = parts.reduce(0) { $0 + (Int($1) ?? 0) }
                return " = \(total)"
            }()
            lines.append("\(name)：\(value)\(sum)")
        }
        if !lifeCoef.isEmpty { lines.append(lifeCoef) }
        lines.append("【武器穿透/抗武器穿透】")
        if let s = pairWeaponStats(attr: attr, atkKey: "weapon_penetrate", dfsKey: "dec_weapon_penetrate") {
            lines.append(s.trimmingCharacters(in: .newlines))
        }
        lines.append("【武器抗韧性/武器韧性】")
        if let s = pairWeaponStats(attr: attr, atkKey: "dec_weapon_toughness", dfsKey: "weapon_toughness") {
            lines.append(s.trimmingCharacters(in: .newlines))
        }
        lines.append("【技能抗韧性/技能韧性】")
        if let s = pairSkillStats(attr: attr, atkKey: "dec_sutoughness", dfsKey: "sutoughness") {
            lines.append(s.trimmingCharacters(in: .newlines))
        }
        return lines.joined(separator: "\n")
    }

    private static func pairWeaponStats(attr: [String: Any], atkKey: String, dfsKey: String) -> String? {
        guard let atkArr = attr.arr("weaponatk"), let dfsArr = attr.arr("weapon_dfs") else { return nil }
        var lines: [String] = []
        for i in 0..<min(atkArr.count, dfsArr.count) {
            let atk = atkArr[i]
            let dfs = dfsArr[i]
            guard let aList = atk.arr(atkKey), let dList = dfs.arr(dfsKey) else { continue }
            for j in 0..<min(aList.count, dList.count) {
                let a = aList[j]
                let d = dList[j]
                lines.append("\(a.str("name")):\(a.str("value"))/\(d.str("value"))")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n") + "\n"
    }

    private static func pairSkillStats(attr: [String: Any], atkKey: String, dfsKey: String) -> String? {
        guard let atkArr = attr.arr("suatk"), let dfsArr = attr.arr("sudef") else { return nil }
        var lines: [String] = []
        for i in 0..<min(atkArr.count, dfsArr.count) {
            let atk = atkArr[i]
            let dfs = dfsArr[i]
            guard let aList = atk.arr(atkKey), let dList = dfs.arr(dfsKey) else { continue }
            for j in 0..<min(aList.count, dList.count) {
                let a = aList[j]
                let d = dList[j]
                lines.append("\(a.str("name")):\(a.str("value"))/\(d.str("value"))")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n") + "\n"
    }

    private static func parseBadges(visit: [String: Any]?, ach: [String: Any]?) -> [BadgeItem] {
        guard let src = ach?.arr("badges") ?? visit?.arr("badges") else { return [] }
        return src.compactMap { o in
            guard o.int("status") == 1 else { return nil }
            let name = o.str("name")
            let typeStr = o.str("type")
            let type = typeStr.isEmpty ? String(o.int("type")) : typeStr
            let aid = o.str("achievement_id")
            return BadgeItem(
                name: name.replacingOccurrences(of: "徽章", with: ""),
                level: o.str("level"),
                iconUrl: "https://fightimg.pet.qq.com/img/badges/icon/\(type)/\(aid).png",
                highlight: ["周年", "富豪", "魅力", "威望"].contains(where: { name.contains($0) })
            )
        }
    }

    private static func parseWeaponsFromVisit(visit: [String: Any]?) -> [WeaponItem] {
        guard let visit, visit.int("result") == 0 else { return [] }
        let goods = visit.str("goods")
        if goods.isEmpty { return [] }
        let insc = visit.arr("insc_info")
        var list: [WeaponItem] = []

        for item in goods.split(separator: ";") {
            let itemStr = String(item)
            if itemStr.isEmpty || itemStr == "----" { continue }
            let lines = itemStr.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if lines.isEmpty { continue }
                let head = lines[0].split(separator: ",").map(String.init)
                let tail = lines[lines.count - 1].split(separator: ",").map(String.init)
                if head.isEmpty || head[0].isEmpty { continue }

                let rawName = head[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let namePlain = "[\(rawName)]"
                let color = weaponColor(namePlain)
                let qh = Int(head.count > 2 ? head[2] : "") ?? 0
                var xian = tail.last ?? ""
                if xian == "-1" { xian = "0" }
                let xianInt = Int(xian) ?? 0
                let xianShow = xianInt == 5 ? "5★" : xian

                let weak = qh < 3
                    && !namePlain.contains("真·")
                    && !namePlain.contains("神·")
                    && color != 0xFF1565C0

                let inscId = head.count > 3 ? head[3] : ""
                let weaponId: Int = {
                    if weak {
                        return Int(inscId) ?? 0
                    }
                    if tail.count >= 2, let id = Int(tail[tail.count - 2]) { return id }
                    return Int(inscId) ?? 0
                }()

                let damageRaw = head.last?
                    .components(separatedBy: "伤害:")
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let dmgParts = damageRaw.split { $0 == "-" || $0 == "/" }.map(String.init)
                let threshold = (head.last ?? "").contains("投掷") ? 70 : 100
                let dmgHot: Bool = {
                    let a = Int(dmgParts.first ?? "") ?? 0
                    let b = Int(dmgParts.count > 1 ? dmgParts[1] : "") ?? 0
                    return a >= threshold || b >= threshold
                }()
                let damage = damageRaw.isEmpty ? "" : "[\(damageRaw)]"

                let hunzhuField = tail.count >= 3 ? tail[tail.count - 3] : ""
                let hunzhu = parseHunzhu(field: hunzhuField)
                let mingke = findMingke(insc: insc, weaponId: inscId)

                let iconId = weaponId < 1000 && weaponId > 0 ? weaponId + 1000 : weaponId
                list.append(WeaponItem(
                    namePlain: namePlain,
                    color: color,
                    iconUrl: "https://fightimg.pet.qq.com/img/phone/\(iconId).jpg",
                    weaponId: weaponId >= 1000 ? weaponId - 1000 : weaponId,
                    qhXh: "[强\(qh)仙\(xianShow)]",
                    damage: dmgHot ? "★\(damage)" : damage,
                    hunzhu: hunzhu,
                    mingke: mingke,
                    xianHua: xianInt
                ))
        }
        return sortWeapons(list)
    }

    private static func parseHunzhu(field: String) -> String {
        if field.isEmpty || !field.contains("|") { return "" }
        let map = ["1": "剑", "2": "菜", "3": "月", "4": "帅", "5": "血", "6": "影", "7": "教"]
        var out = ""
        for part in field.components(separatedBy: "||") {
            if part.isEmpty { continue }
            let kv = part.components(separatedBy: "|")
            if kv.count < 2 { continue }
            guard let name = map[kv[0]] else { continue }
            let lv = kv[1]
            out += name + (lv.contains("7") ? "7★" : lv)
        }
        return out
    }

    private static func findMingke(insc: [[String: Any]]?, weaponId: String) -> String {
        guard let insc, !weaponId.isEmpty else { return "" }
        for o in insc {
            if o.str("weapon_id") != weaponId { continue }
            guard let attrs = o.arr("attr_list") else { continue }
            for a in attrs {
                if a.str("name") != "该武器伤害" { continue }
                let lv = a.int("level")
                let v = a.str("value").isEmpty ? String(a.int("value")) : a.str("value")
                return lv > 10 ? "(Lv\(lv))+\(v)★" : "(Lv\(lv))+\(v)"
            }
        }
        return ""
    }

    private static func parseWeaponsFromHtml(html: String) -> [WeaponItem] {
        guard html.contains("升级即有机会获得新武器") else { return [] }
        let part = htmlLineAfter(html: html, marker: "升级即有机会获得新武器")
        var list: [WeaponItem] = []
        for chunk in part.components(separatedBy: "</a>") {
            guard chunk.contains("\">") else { continue }
            let name = chunk.components(separatedBy: "\">").last?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty || name.count > 40 { continue }
            guard let rawId = firstMatchInt(text: chunk, regex: weaponIdPat) else { continue }
            let namePlain = "[\(name)]"
            list.append(WeaponItem(
                namePlain: namePlain,
                color: weaponColor(namePlain),
                iconUrl: "https://fightimg.pet.qq.com/img/phone/\(rawId).jpg",
                weaponId: rawId >= 1000 ? rawId - 1000 : rawId
            ))
            if list.count >= 80 { break }
        }
        return sortWeapons(list)
    }

    private static func buildWeaponSummary(weapons: [WeaponItem]) -> String {
        let shen = weapons.filter { $0.color == 0xFFC62828 }.count
        let cui = weapons.filter { $0.color == 0xFF1565C0 }.count
        let xian = weapons.filter {
            $0.xianHua == 5 || $0.qhXh.contains("仙5") || $0.qhXh.contains("仙5★")
        }.count
        return "神器：\(shen)，淬火：\(cui)，仙化：\(xian)"
    }

    private static func parseSkillsFromVisit(visit: [String: Any]?) -> [SkillLine] {
        let skill = visit?.str("skill") ?? ""
        if skill.isEmpty { return [] }
        var lines: [SkillLine] = []
        var specialA = ""
        var specialB = ""
        for s in skill.split(separator: ";") {
            let sStr = String(s)
            if sStr.isEmpty { continue }
            let parts = sStr.split(separator: ",").map(String.init)
            let name = parts.first ?? ""
            if name.isEmpty { continue }
            var xh = parts.last ?? ""
            if xh == "-1" { xh = "0" }
            let qhIdx = max(1, parts.count - 3)
            let qh = parts.count > qhIdx ? parts[qhIdx] : ""
            let xhShow = xh == "5" ? "5★" : xh
            let text = "【\(name)】[强\(qh)仙\(xhShow)]"
            let mid = parts.count > 2 ? parts[2] : ""
            if mid.contains("乐斗达人尊贵特权，对目标造成") {
                if specialA.isEmpty { specialA = text }
            } else if mid.contains("乐斗达人尊贵特权，所经之处无人幸免") {
                if specialB.isEmpty { specialB = text }
            } else {
                lines.append(SkillLine(text: text, emphasize: xh == "5" || name.contains("神·")))
            }
        }
        if !specialA.isEmpty { lines.append(SkillLine(text: specialA, emphasize: true)) }
        if !specialB.isEmpty { lines.append(SkillLine(text: specialB, emphasize: true)) }
        return lines
    }

    private static func parseMerc(merc: [String: Any]?) -> MercBlock {
        guard let merc, let arr = merc.arr("array") else { return MercBlock() }
        var on = "上阵佣兵："
        var all = "全部佣兵："
        var person: [(String, Acc)] = []
        var mercPass: [(String, Acc)] = []
        func accIndex(_ map: inout [(String, Acc)], key: String) -> Int {
            if let i = map.firstIndex(where: { $0.0 == key }) { return i }
            map.append((key, Acc()))
            return map.count - 1
        }

        for o in arr {
            let name = o.str("name")
            let lvl = o.str("lvl")
            let status = o.str("status")
            var talentCount = 0
            o.arr("talent")?.forEach { t in
                if t.int("tlevel") > 0 { talentCount += 1 }
            }
            let talentTag = talentCount > 0 ? "+\(talentCount)" : ""
            if status == "1" { on += "\(name) | " }
            all += "\(name)(\(lvl)\(talentTag)) "

            o.arr("talent")?.forEach { t in
                let to = t
                let lv = to.int("tlevel")
                if lv <= 0 { return }
                let tid = to.str("tid")
                if tid != "1" && tid != "2" { return }
                let desc = to.str("desc")
                let chunks = name == "皇·御天战鹅" && tid == "2"
                    ? desc.components(separatedBy: "，")
                    : [desc]
                for chunk in chunks {
                    let range = NSRange(chunk.startIndex..., in: chunk)
                    guard let m = talentPat.firstMatch(in: chunk, range: range),
                          m.numberOfRanges >= 3,
                          let kR = Range(m.range(at: 1), in: chunk),
                          let vR = Range(m.range(at: 2), in: chunk) else { continue }
                    let rawKey = String(chunk[kR]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard var v = Double(chunk[vR]) else { continue }
                    if desc.contains("千分之") { v /= 1000.0 }
                    let key = talentShort[rawKey] ?? rawKey
                    if tid == "2" {
                        let i = accIndex(&person, key: key)
                        person[i].1.v += v
                        person[i].1.from.append("\(name)+\(lv)")
                    } else {
                        let i = accIndex(&mercPass, key: key)
                        mercPass[i].1.v += v
                        mercPass[i].1.from.append("\(name)+\(lv)")
                    }
                }
            }
        }

        func dump(_ map: [(String, Acc)]) -> String {
            map.map { k, acc in
                "\(k) +\(trimNum(acc.v))(\(acc.from.joined(separator: ",")))"
            }.joined(separator: "\n")
        }
        var talentSummary = "-----------佣兵天赋属性汇总-------------\n"
        talentSummary += "——人物被动属性——\n"
        talentSummary += person.isEmpty ? "无\n" : dump(person) + "\n"
        talentSummary += "——佣兵被动属性——\n"
        talentSummary += mercPass.isEmpty ? "无" : dump(mercPass).trimmingCharacters(in: .newlines)

        let combined = Dictionary(uniqueKeysWithValues: person + mercPass)
        let tough = combined
            .filter { $0.key.hasPrefix("佣兵韧") || $0.key.hasPrefix("佣兵抗韧") }
            .map { "\($0.key) +\(trimNum($0.value.v))" }
            .joined(separator: "\n")

        return MercBlock(
            on: on.trimmingCharacters(in: CharacterSet(charactersIn: " |")),
            all: all.trimmingCharacters(in: .whitespacesAndNewlines),
            talent: talentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            tough: tough
        )
    }

    private static func parseFormation(form: [String: Any]?) -> String {
        guard let form, let info = form.arr("info") else { return "" }
        var map: [(String, Double)] = []
        func idx(_ key: String) -> Int {
            if let i = map.firstIndex(where: { $0.0 == key }) { return i }
            map.append((key, 0))
            return map.count - 1
        }
        for el in info {
            let effect = el.str("attr_effect")
            let range = NSRange(effect.startIndex..., in: effect)
            guard let m = formPat.firstMatch(in: effect, range: range),
                  m.numberOfRanges >= 3,
                  let kR = Range(m.range(at: 1), in: effect),
                  let vR = Range(m.range(at: 2), in: effect) else { continue }
            let rawKey = String(effect[kR])
            let key = formShort[rawKey] ?? rawKey
            guard let v = Double(effect[vR]) else { continue }
            let i = idx(key)
            map[i].1 += v
        }
        if map.isEmpty { return "" }
        var dict = Dictionary(uniqueKeysWithValues: map)
        var lines = ["-----------佣兵助阵-------------"]
        for k in formOrder {
            guard let v = dict.removeValue(forKey: k) else { continue }
            lines.append("\(k)：\(trimNum(v))")
        }
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            lines.append("\(k)：\(trimNum(v))")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseJingMai(merid: [String: Any]?) -> String {
        guard let merid else { return "" }
        let combat = Int(merid.str("combat")) ?? merid.int("combat")
        guard let effects = merid.arr("intf_effect") else { return "" }
        var lines = [
            "-----------经脉汇总-------------",
            "总战力：\(Double(combat) / 10.0)",
            "—— 属性汇总 ——",
        ]
        for o in effects {
            let type = Int(o.str("attr_type")) ?? o.int("attr_type")
            let name = meridAttr[type] ?? "未知(\(type))"
            let raw = Double(o.str("attr_value")) ?? o.double("attr_value")
            let v = meridDiv10.contains(type) ? raw / 10.0 : raw
            lines.append("\(name)：+\(v)")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseZhuanJing(zj: [String: Any]?) -> String {
        guard let zj else { return "" }
        guard let src = zj.arr("dst_weapons0") ?? zj.arr("src_weapons0") else { return "" }
        var lines = ["-----------专精-------------"]
        for type in ["投", "小", "中", "大"] {
            for el in src {
                let o = el
                let typeName = o.str("type_name")
                if !typeName.contains(type) { continue }
                var line = "\(type)专(\(o.str("stage"))-\(o.str("level")))"
                o.arr("storages")?.forEach { s in
                    line += "(\(s.str("storage_level")) \(s.str("weapon_name")))"
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func parseShenZhuang(outfit: [String: Any]?) -> String {
        guard let outfit, outfit.int("result") == 0,
              let list = outfit.arr("magic_outfits") else { return "" }
        var lines = ["-----------神装-------------"]
        for name in ["神兵", "神铠", "神羽", "神兽", "神饰", "神履"] {
            guard let o = list.first(where: { $0.str("magic_outfit_name") == name }) else { continue }
            var line = "\(name)(\(o.str("level")))"
            o.arr("skills")?.forEach { s in
                let suit = s.int("suit_level")
                if suit >= 0 {
                    line += "(\(s.str("skill_name"))\(s.str("skill_level")) +\(suit))"
                } else {
                    line += "(\(s.str("skill_name"))\(s.str("skill_level")))"
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func parseSkillHtml(html: String, uin: String, cookie: String) async -> SkillPage {
        guard html.contains("升级即有机会获得新技能") else { return SkillPage() }
        let part = html.components(separatedBy: "升级即有机会获得新技能").dropFirst().joined(
            separator: "升级即有机会获得新技能"
        )
        let chunks = part.components(separatedBy: "</a>")
        var hits: [(String, String)] = []
        let upper = max(0, chunks.count - 1)
        for i in 0..<upper {
            let chunk = chunks[i]
            var name = chunk.components(separatedBy: "\">").last ?? ""
            name = name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            name = name.replacingOccurrences(of: "&nbsp;", with: "")
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let href = (chunk.components(separatedBy: "\">").first ?? chunk)
                .replacingOccurrences(of: "&amp;", with: "&")
            let id = firstMatchString(text: href, regex: skillHrefIdPat)?
                .filter(\.isNumber) ?? ""
            hits.append((id, name))
        }
        let names = hits.map(\.1)
        var shenJiang = "出战神将：未设置"
        for (i, key) in shenJiangSkill.enumerated() {
            if names.contains(where: { $0.contains(key) }) {
                shenJiang = "出战神将：\(shenJiangName[i])"
                break
            }
        }
        var siLingLabel = ""
        var aoYiBits: [String] = []
        for (id, name) in hits {
            if name.contains("四灵守护") {
                let detail = await fetchSkillDetail(uin: uin, id: id, cookie: cookie)
                siLingLabel = siLingGradeFromDetail(html: detail)
                continue
            }
            guard let slot = aoYi.firstIndex(where: { name.contains($0) }) else { continue }
            let detail = await fetchSkillDetail(uin: uin, id: id, cookie: cookie)
            let lv = aoYiLevelFromDetail(slot: slot, html: detail)
            let shown = name.replacingOccurrences(of: "等级", with: "")
            if let lv {
                aoYiBits.append("[\(shown)\(lv)]")
            } else {
                aoYiBits.append("[\(shown)]")
            }
        }
        var aoYiStr = ""
        if !siLingLabel.isEmpty {
            aoYiStr = "奥义：\(siLingLabel)"
            if !aoYiBits.isEmpty { aoYiStr += " " + aoYiBits.joined(separator: " ") }
        } else if !aoYiBits.isEmpty {
            aoYiStr = "奥义：" + aoYiBits.joined(separator: " ")
        }
        let ld = names
            .filter { n in luanDou.contains(where: { n.contains($0) }) }
            .map { $0.replacingOccurrences(of: "等级", with: "Lv") }
            .joined(separator: "|")
        let luanDouStr = ld.isEmpty ? "" : "------------特殊技能------------\n大乱斗：\(ld)"
        let sm = names.filter { n in shenMo.contains(where: { n.contains($0) }) }
        let shenMoStr = sm.isEmpty ? "" : "神魔阵法：" + sm.map { "[\($0)]" }.joined()
        let ding = shenMoDing.compactMap { d in
            names.first(where: { $0.contains(d) }).map { _ in "(\(d))" }
        }
        let shenMoDingStr = ding.isEmpty ? "" : "神魔鼎：" + ding.joined()
        return SkillPage(
            shenJiang: shenJiang,
            aoYi: aoYiStr,
            luanDou: luanDouStr,
            shenMo: shenMoStr,
            shenMoDing: shenMoDingStr
        )
    }

    private static func fetchSkillDetail(uin: String, id: String, cookie: String) async -> String {
        guard !id.isEmpty else { return "" }
        let (_, body) = await LedouCGI.getPhonePk(
            cmd: "view",
            extra: ["B_UID": uin, "type": "5", "id": id],
            cookie: cookie
        )
        return body
    }

    private static func siLingGradeFromDetail(html: String) -> String {
        var hay = compactHtml(htmlLineContaining(html: html, key: "减免比例为"))
        if hay.isEmpty { hay = compactHtml(html) }
        for i in siLingRatio.indices {
            if hay.contains(compactHtml(siLingRatio[i])) { return siLingGrade[i] }
        }
        return ""
    }

    private static func aoYiLevelFromDetail(slot: Int, html: String) -> Int? {
        let marker: String = {
            if slot <= 7 { return "造成" }
            if slot <= 11 { return "恢复" }
            return "所有奥义技能伤害"
        }()
        var hay = compactHtml(htmlLineContaining(html: html, key: marker))
        if hay.isEmpty { hay = compactHtml(html) }
        let tables: [(tag: String, rows: [String])] = {
            if slot <= 3 { return [("A", aoYiDmgA), ("B", aoYiDmgB)] }
            if slot <= 7 { return [("C", aoYiDmgC), ("D", aoYiDmgD), ("E", aoYiDmgE), ("F", aoYiDmgF)] }
            if slot <= 11 { return [("A", aoYiHealA), ("B", aoYiHealB), ("C", aoYiHealC), ("D", aoYiHealD)] }
            return [("A", aoYiGuardA), ("B", aoYiGuardB)]
        }()
        let width = tables.map(\.rows.count).max() ?? 0
        for i in 0..<width {
            for (tag, table) in tables {
                if i >= table.count { continue }
                let needle = compactHtml(table[i])
                if needle.isEmpty || !hay.contains(needle) { continue }
                if slot <= 3 && tag == "B" && hay.contains("自身命中率") { continue }
                return i
            }
        }
        let range = NSRange(html.startIndex..., in: html)
        if let m = aoYiLevelPat.firstMatch(in: html, range: range),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: html) {
            return Int(html[r])
        }
        return nil
    }

    private static func parseAttrs(attr: [String: Any]?) -> String {
        guard let attr, attr.int("result") == 0 else { return "" }
        var lines: [String] = ["-----------武器属性-------------"]
        if let atkArr = attr.arr("weaponatk"), let dfsArr = attr.arr("weapon_dfs") {
            for i in 0..<min(atkArr.count, dfsArr.count) {
                let atk = atkArr[i]
                let dfs = dfsArr[i]
                lines.append("\(atk.str("name"))/\(dfs.str("name"))")
                appendPairs(lines: &lines, a: atk.arr("weapon_hit"), b: dfs.arr("weapon_miss"))
                appendPairs(lines: &lines, a: atk.arr("weapon_crit"), b: dfs.arr("dec_weapon_crit"))
                appendPairs(lines: &lines, a: atk.arr("crit_damage"), b: dfs.arr("dec_crit_damage"))
                appendPairs(lines: &lines, a: atk.arr("weapon_damage"), b: dfs.arr("dec_weapon_damage"))
                appendPairs(lines: &lines, a: atk.arr("weapon_penetrate"), b: dfs.arr("dec_weapon_penetrate"))
                appendPairs(lines: &lines, a: atk.arr("dec_weapon_toughness"), b: dfs.arr("weapon_toughness"))
            }
        }
        lines.append("-----------技能空手属性-------------")
        if let suatk = attr.arr("suatk"), let sudef = attr.arr("sudef") {
            for i in 0..<min(suatk.count, sudef.count) {
                let a = suatk[i]
                let d = sudef[i]
                lines.append("\(a.str("name"))/\(d.str("name"))")
                appendPairs(lines: &lines, a: a.arr("suhit"), b: d.arr("sumiss"))
                appendPairs(lines: &lines, a: a.arr("sucritrate"), b: d.arr("dsucritrate"))
                appendPairs(lines: &lines, a: a.arr("sucrit"), b: d.arr("dsucrit"))
                appendPairs(lines: &lines, a: a.arr("sudamage"), b: d.arr("dsudamage"))
                appendPairs(lines: &lines, a: a.arr("supenettration"), b: d.arr("dec_supenettration"))
                appendPairs(lines: &lines, a: a.arr("dec_sutoughness"), b: d.arr("sutoughness"))
            }
        }
        lines.append("-----------特殊属性-------------")
        lines.append("腐蚀/抵御")
        attr.arr("kuozhanattr")?.forEach { o in
            lines.append("\(o.str("name")):\(o.str("fs"))/\(o.str("dy"))")
        }
        return lines.joined(separator: "\n")
    }

    private static func appendPairs(lines: inout [String], a: [[String: Any]]?, b: [[String: Any]]?) {
        guard let a, let b else { return }
        for i in 0..<min(a.count, b.count) {
            let ao = a[i]
            let bo = b[i]
            lines.append("\(ao.str("name")):\(ao.str("value"))/\(bo.str("value"))")
        }
    }

    private static func parsePower(rank: [String: Any]?) -> PowerBlock {
        guard let rank, rank.int("result") == 0 else {
            return PowerBlock()
        }
        let leftKeys: [(String, String)] = [
            ("武器", "weapon"), ("技能", "skill"), ("经脉", "merid"), ("佣兵", "mercenary"),
            ("等级", "level"), ("神装", "outfit_fc_bonus"), ("专精", "weapon_spe_bonus"),
            ("星盘", "astrolabe_bonus"), ("觉醒", "weapon_awaken_bonus"), ("奥义", "skill_enhance_bonus"),
            ("神魔录", "ancient_god_bonus"), ("神器符石", "weapon_god_bonus"), ("神将录", "godly_general_bonus"),
            ("大乱斗", "luandou_bonus"), ("封印", "weapon_seal_bonus"), ("帮派称号", "facsig_bonus"),
            ("飞升", "ascend_heaven_bonus"), ("附魔", "enchant_bonus"), ("侠客岛", "knight_island_bonus"),
            ("世界树", "world_tree_bonus"), ("职业元武阁", "career_bonus"),
        ]
        let rightKeys: [(String, String)] = [
            ("魂珠", "inlaied"), ("帮修", "factionTrainSkill"), ("五行", "five"), ("助阵", "formation"),
            ("徒弟", "dis"), ("达人", "vip"), ("徽章", "badges_bonus"), ("铭刻", "inscription_bonus"),
            ("门派", "sect_bonus"), ("元婴", "doppelganger_bonus"), ("佣兵天赋", "mercenary_talent"),
            ("斗技", "scene_skill_bonus"), ("称号", "title_bonus"), ("侠士", "warriorinn_bonus"),
            ("铁匠铺", "black_smith_bonus"), ("仙武", "immortals_bonus"), ("深渊", "abyss_tide_bonus"),
            ("头像", "profile_bonus"), ("时空遗迹", "space_relic_bonus"), ("龙凰之境", "dragon_phoenix_bonus"),
        ]
        func collect(_ keys: [(String, String)]) -> [(String, String)] {
            keys.compactMap { label, key in
                let v = rank.str(key)
                if v.isEmpty || v == "0" || v == "0.0" { return nil }
                return (label, v)
            }
        }
        return PowerBlock(
            rank: "排名：\(rank.str("per"))  \(rank.str("rankname"))",
            left: collect(leftKeys),
            right: collect(rightKeys)
        )
    }

    // MARK: - Weapon helpers

    private static func weaponColor(_ name: String) -> UInt64 {
        if name.contains("神·") { return 0xFFC62828 }
        if cuiHuo.contains(where: { name.contains($0) }) { return 0xFF1565C0 }
        if name.contains("仙·") || name.contains("仙化") { return 0xFF1565C0 }
        if jingLiang.contains(where: { name.contains($0) }) { return 0xFF2E7D32 }
        if name.contains("精·") || name.contains("精良") { return 0xFF2E7D32 }
        return 0xFF212121
    }

    private static func sortWeapons(_ list: [WeaponItem]) -> [WeaponItem] {
        list.sorted { a, b in
            func rank(_ c: UInt64) -> Int {
                switch c {
                case 0xFFC62828: return 0
                case 0xFF1565C0: return 1
                case 0xFF2E7D32: return 2
                default: return 3
                }
            }
            return rank(a.color) < rank(b.color)
        }
    }

    // MARK: - HTML helpers

    private static func htmlLineAfter(html: String, marker: String) -> String {
        let norm = html
            .replacingOccurrences(of: "<br/>", with: "<br />")
            .replacingOccurrences(of: "<br>", with: "<br />")
        let parts = norm.components(separatedBy: "<br />")
        for i in parts.indices {
            if parts[i].contains(marker), i + 1 < parts.count {
                return parts[(i + 1)...].joined(separator: "<br />")
            }
        }
        if let r = norm.range(of: marker) {
            return String(norm[r.upperBound...])
        }
        return ""
    }

    private static func htmlLineContaining(html: String, key: String) -> String {
        let norm = html
            .replacingOccurrences(of: "<br/>", with: "<br />")
            .replacingOccurrences(of: "<br>", with: "<br />")
        let raw = norm.components(separatedBy: "<br />").first(where: { $0.contains(key) }) ?? ""
        return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func compactHtml(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private static func firstMatchInt(text: String, regex: NSRegularExpression) -> Int? {
        guard let s = firstMatchString(text: text, regex: regex) else { return nil }
        return Int(s)
    }

    private static func firstMatchString(text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

// MARK: - JSON helpers

private func parseObj(_ json: String) -> [String: Any]? {
    var t = json.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.first == "\u{FEFF}" { t.removeFirst() }
    guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start <= end else { return nil }
    let slice = String(t[start...end])
    guard let data = slice.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return obj
}

private func firstNonBlank(_ values: String?...) -> String? {
    values.compactMap { $0 }.first(where: { !$0.isEmpty })
}

private func trimNum(_ v: Double) -> String {
    if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
    return String(v)
}

private extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String {
        guard let v = self[key] else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if v is NSNull { return "" }
        return "\(v)"
    }

    func int(_ key: String) -> Int {
        guard let v = self[key] else { return 0 }
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter { $0.isNumber || $0 == "-" }) ?? 0 }
        return 0
    }

    func double(_ key: String) -> Double {
        guard let v = self[key] else { return 0 }
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    func obj(_ key: String) -> [String: Any]? {
        guard let v = self[key] else { return nil }
        if let o = v as? [String: Any] { return o }
        return nil
    }

    func arr(_ key: String) -> [[String: Any]]? {
        guard let v = self[key] else { return nil }
        if let a = v as? [[String: Any]] { return a }
        if let a = v as? [Any] {
            let mapped = a.compactMap { $0 as? [String: Any] }
            return mapped.isEmpty ? nil : mapped
        }
        return nil
    }
}
