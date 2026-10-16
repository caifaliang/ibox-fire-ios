import Foundation

struct QueryProfile {
    var uin: String
    var cookieOk: Bool
    var rawError: String?
    var header: HeaderInfo
    /// 对齐 tv_xinxi_base：达人/帮派/职位/武林/称号/状态
    var xinxiBase: String
    var baseExtra: String
    /// 基本信息里的属性块（血/力/敏/速、穿透韧性摘要等）
    var baseAttrBlock: String
    var badges: [BadgeItem]
    var weapons: [WeaponItem]
    var weaponSummary: String
    var skillsHtmlLines: [SkillLine]
    var mercOnField: String
    var mercAll: String
    var mercTalent: String
    var mercTough: String
    var mercFormation: String
    var jingMai: String
    var zhuanJing: String
    var shenZhuang: String
    var shenJiang: String
    var aoYi: String
    var luanDou: String
    var shenMo: String
    var shenMoDing: String
    var attrsText: String
    var powerRank: String
    var powerLeft: [(String, String)]
    var powerRight: [(String, String)]

    init(
        uin: String,
        cookieOk: Bool,
        rawError: String? = nil,
        header: HeaderInfo = HeaderInfo(),
        xinxiBase: String = "",
        baseExtra: String = "",
        baseAttrBlock: String = "",
        badges: [BadgeItem] = [],
        weapons: [WeaponItem] = [],
        weaponSummary: String = "",
        skillsHtmlLines: [SkillLine] = [],
        mercOnField: String = "",
        mercAll: String = "",
        mercTalent: String = "",
        mercTough: String = "",
        mercFormation: String = "",
        jingMai: String = "",
        zhuanJing: String = "",
        shenZhuang: String = "",
        shenJiang: String = "",
        aoYi: String = "",
        luanDou: String = "",
        shenMo: String = "",
        shenMoDing: String = "",
        attrsText: String = "",
        powerRank: String = "",
        powerLeft: [(String, String)] = [],
        powerRight: [(String, String)] = []
    ) {
        self.uin = uin
        self.cookieOk = cookieOk
        self.rawError = rawError
        self.header = header
        self.xinxiBase = xinxiBase
        self.baseExtra = baseExtra
        self.baseAttrBlock = baseAttrBlock
        self.badges = badges
        self.weapons = weapons
        self.weaponSummary = weaponSummary
        self.skillsHtmlLines = skillsHtmlLines
        self.mercOnField = mercOnField
        self.mercAll = mercAll
        self.mercTalent = mercTalent
        self.mercTough = mercTough
        self.mercFormation = mercFormation
        self.jingMai = jingMai
        self.zhuanJing = zhuanJing
        self.shenZhuang = shenZhuang
        self.shenJiang = shenJiang
        self.aoYi = aoYi
        self.luanDou = luanDou
        self.shenMo = shenMo
        self.shenMoDing = shenMoDing
        self.attrsText = attrsText
        self.powerRank = powerRank
        self.powerLeft = powerLeft
        self.powerRight = powerRight
    }
}

struct HeaderInfo {
    var nickname: String
    var level: Int
    var combat: Double
    var menpai: String
    var arenaRank: String
    var faction: String
    var strong: String
    var minjie: String
    var speed: String
    var hp: String
    var avatarUrl: String

    init(
        nickname: String = "?",
        level: Int = 0,
        combat: Double = 0,
        menpai: String = "",
        arenaRank: String = "",
        faction: String = "",
        strong: String = "",
        minjie: String = "",
        speed: String = "",
        hp: String = "",
        avatarUrl: String = ""
    ) {
        self.nickname = nickname
        self.level = level
        self.combat = combat
        self.menpai = menpai
        self.arenaRank = arenaRank
        self.faction = faction
        self.strong = strong
        self.minjie = minjie
        self.speed = speed
        self.hp = hp
        self.avatarUrl = avatarUrl
    }
}

struct BadgeItem {
    var name: String
    var level: String
    var iconUrl: String
    var highlight: Bool
}

struct WeaponItem {
    var namePlain: String
    var color: UInt64
    var iconUrl: String
    var weaponId: Int
    /// 如 [强12仙5]
    var qhXh: String
    /// 如 [120-130]
    var damage: String
    /// 如 剑7菜5
    var hunzhu: String
    /// 如 (Lv12)+5
    var mingke: String
    /// 符石孔位摘要（仅查自己时有）
    var fushi: String
    var xianHua: Int

    init(
        namePlain: String,
        color: UInt64,
        iconUrl: String,
        weaponId: Int = 0,
        qhXh: String = "",
        damage: String = "",
        hunzhu: String = "",
        mingke: String = "",
        fushi: String = "",
        xianHua: Int = 0
    ) {
        self.namePlain = namePlain
        self.color = color
        self.iconUrl = iconUrl
        self.weaponId = weaponId
        self.qhXh = qhXh
        self.damage = damage
        self.hunzhu = hunzhu
        self.mingke = mingke
        self.fushi = fushi
        self.xianHua = xianHua
    }
}

struct SkillLine {
    var text: String
    var emphasize: Bool
}
