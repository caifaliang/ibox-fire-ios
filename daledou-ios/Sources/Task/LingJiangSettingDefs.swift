import Foundation

/// 真源：`SettingPageDefs.lingJiang`
enum LingJiangSettingDefs {
    static let feature = "lingjiang"
    static let sections: [SettingSection] = [
        SettingSection(title: "每日奖励", items: [
            .init("cb_day_fenxiang", "一键分享", true),
            .init("cb_day_login", "每日礼包", true),
            .init("cb_day_chuangongfu", "传功符", true),
            .init("cb_day_daren", "达人礼包", true),
            .init("cb_day_tianshu", "天书礼包", true),
            .init("cb_day_doubi", "斗币礼包", true),
            .init("cb_day_huoli", "活力礼包"),
            .init("cb_day_tequan", "微端特权"),
            .init("cb_day_dipan", "地盘奖励"),
            .init("cb_day_dd_yueka", "豆豆月卡"),
            .init("cb_day_yaoqing", "邀请抽奖"),
            .init("cb_day_jianghu", "江湖礼包"),
            .init("cb_day_sj_yueka", "神将月卡"),
            .init("cb_day_xl_6", "白天巡礼"),
            .init("cb_day_xl_18", "晚上巡礼"),
            .init("cb_day_hslj", "论剑奖励"),
            .init("cb_day_xl_zdtz", "巡礼获得次数后自动挑战"),
            .init("cb_day_fmrw", "附魔任务"),
            .init("cb_day_yjrw", "游记任务"),
            .init("cb_day_hylb", "每日活跃礼包"),
            .init("cb_day_sjs", "世界树经验"),
            .init("cb_day_sjs_1", "世界树任务1"),
            .init("cb_day_sjs_2", "世界树任务2"),
            .init("cb_day_sjs_sjlq", "世界树手机一键领取经验奖励"),
            .init("cb_day_ybs_mfwy1", "源宝树-免费温养1次"),
            .init("cb_day_fx", "历程分享-领奖和重置分享"),
        ]),
        SettingSection(title: "优惠秘籍", items: [
            .init("cb_yhmj_mf", "免费礼包"),
            .init("cb_yhmj_bp", "帮派礼包"),
        ]),
        SettingSection(title: "侠士客栈", items: [
            .init("cb_kezhan_yilou", "一楼奖励"),
            .init("cb_kezhan_erlou", "二楼奖励"),
            .init("cb_kezhan_tianzhuan", "自动添砖"),
            .init("cb_kezhan_gzhk", "共建回馈"),
        ]),
        SettingSection(title: "豪侠出世", items: [
            .init("cb_hxcs_qdhl", "签到好礼"),
            .init("cb_hxcs_xszl", "侠士战令"),
            .init("cb_hxcs_hxzl", "豪侠战令"),
            .init("cb_hxcs_zmdb", "招募达标"),
        ]),
        SettingSection(title: "龙凰之境", items: [
            .init("cb_lhzj_day", "每日领奖"),
            .init("cb_lhzj_saiji", "赛季领奖"),
            .init("cb_lhzj_cishu", "次数领奖"),
            .init("cb_lhzj_zhenfaku", "阵法库领奖"),
            .init("cb_lhzj_longyuan", "报名龙渊"),
            .init("cb_lhzj_huangji", "报名凰极"),
            .init("cb_lhzj_dh_lwq", "换论武券"),
            .init("cb_lhzj_dh_ly", "换龙玉"),
            .init("cb_lhzj_dh_hs", "换凰髓"),
            .init("cb_lhzj_dh_hh", "换凰火"),
        ]),
        SettingSection(title: "遗迹征伐", items: [
            .init("cb_yjzf_1", "每周任务"),
            .init("cb_yjzf_2", "赛季任务"),
            .init("cb_yjzf_3", "赛季排行"),
            .init("cb_yiji_yaoqing", "自动邀请"),
            .init("ed_yiji_yaoqing", "邀请QQ(每行一个)", kind: .text),
            .init("cb_yiji_jinzu", "自动进组"),
            .init("ed_yiji_jinzu", "进组邀请人QQ", kind: .text),
        ]),
        SettingSection(title: "乐斗激运牌", items: [
            .init("cb_ldjyp_1", "活跃任务"),
            .init("cb_ldjyp_2", "鹅币任务"),
            .init("cb_ldjyp_3", "抽奖"),
        ]),
        SettingSection(title: "大侠回归", items: [
            .init("cb_dxhg_1", "累计登录"),
            .init("cb_dxhg_2", "累计活跃"),
            .init("cb_dxhg_3", "累计消耗"),
        ]),
        SettingSection(title: "豆油召回", items: [
            .init("cb_day_hl_1", "回流礼包"),
            .init("cb_day_hl_2", "热心助人"),
            .init("cb_day_hl_3", "豪情快意"),
        ]),
        SettingSection(title: "领取经验", items: [
            .init("cb_jy_td", "徒弟经验"),
            .init("cb_jy_mj", "10次木简"),
            .init("cb_jy_hy", "100活跃领微端经验淬火礼包"),
            .init("cb_jy_hy2", "80活跃领微端经验礼包"),
        ]),
        SettingSection(title: "邪神月卡", items: [
            .init("cb_xie_s_cz", "超值月卡"),
            .init("cb_xie_s_jx", "惊喜月卡"),
            .init("cb_xie_s_zz", "至尊月卡"),
        ]),
        SettingSection(title: "虎年年卡", items: [
            .init("cb_year_dd", "斗豆年卡"),
            .init("cb_year_jx", "觉醒年卡"),
            .init("cb_year_bf", "缤纷年卡"),
            .init("cb_year_qh", "强化年卡"),
            .init("cb_year_xy", "幸运年卡"),
        ]),
        SettingSection(title: "兔年年卡", items: [
            .init("cb_year_dd_tu", "斗豆年卡"),
            .init("cb_year_jx_tu", "觉醒年卡"),
            .init("cb_year_bf_tu", "缤纷年卡"),
            .init("cb_year_qh_tu", "强化年卡"),
            .init("cb_year_xy_tu", "幸运年卡"),
        ]),
        SettingSection(title: "龙年年卡", items: [
            .init("cb_year_dd_long", "斗豆年卡"),
            .init("cb_year_jx_long", "觉醒年卡"),
            .init("cb_year_bf_long", "缤纷年卡"),
            .init("cb_year_qh_long", "强化年卡"),
            .init("cb_year_xy_long", "幸运年卡"),
        ]),
        SettingSection(title: "蛇年年卡", items: [
            .init("cb_year_dd_she", "斗豆年卡"),
            .init("cb_year_jx_she", "觉醒年卡"),
            .init("cb_year_bf_she", "缤纷年卡"),
            .init("cb_year_qh_she", "强化年卡"),
            .init("cb_year_xy_she", "幸运年卡"),
        ]),
        SettingSection(title: "马年年卡", items: [
            .init("cb_year_dd_da_ma", "斗豆年卡（大）"),
            .init("cb_year_dd_xiao_ma", "斗豆年卡（小）"),
            .init("cb_year_jx_da_ma", "觉醒年卡（大）"),
            .init("cb_year_jx_xiao_ma", "觉醒年卡（小）"),
            .init("cb_year_sq_da_ma", "神器年卡（大）"),
            .init("cb_year_sq_xiao_ma", "神器年卡（小）"),
            .init("cb_year_fm_da_ma", "附魔年卡（大）"),
            .init("cb_year_fm_xiao_ma", "附魔年卡（小）"),
            .init("cb_year_xk_da_ma", "侠客年卡（大）"),
            .init("cb_year_xk_xiao_ma", "侠客年卡（小）"),
            .init("cb_year_all_ma", "全部年卡"),
        ]),
        SettingSection(title: "限时登录兑换商店", items: [
            .init("cb_login_dh", "自动兑换"),
            .init("ed_login_dh_type", "兑换物type(默认1221中体力)", kind: .text),
        ]),
        SettingSection(title: "限时活动", items: [
            .init("cb_xs_cd", "乐斗菜单"),
            .init("cb_xs_lp", "幸运转盘"),
            .init("cb_xs_yz", "乐斗驿站"),
            .init("cb_xs_bbs", "好礼步步升"),
            .init("cb_xs_dl", "登录有礼"),
            .init("cb_xs_zz", "周周礼包"),
            .init("cb_xs_hylb", "活跃礼包"),
            .init("cb_xs_ggk", "惊喜刮刮卡"),
            .init("cb_xs_cash", "长安盛会"),
            .init("cb_xs_hjbx", "浩劫宝箱"),
            .init("cb_xs_zl", "徽章战令"),
            .init("cb_xs_jld", "企鹅吉利兑"),
            .init("cb_xs_mrdh", "每日兑换"),
            .init("cb_xs_xcbn", "新春拜年"),
            .init("cb_xs_xctj", "喜从天降"),
            .init("cb_xs_xcdl", "新春登录"),
            .init("cb_xs_znyr", "周年预热"),
            .init("cb_xs_sxfk", "生肖福卡"),
            .init("cb_xs_qxfq", "夫妻甜蜜好礼"),
            .init("cb_xs_qxds", "单身鹅鼓励好礼"),
            .init("cb_xs_sj_mr", "双节签到-每日奖励"),
            .init("cb_xs_sj_end", "双节签到-最后奖励"),
            .init("cb_xs_tbsh", "重阳太白诗会"),
            .init("cb_xs_zqlh", "中秋礼盒"),
            .init("cb_xs_xye", "幸运鹅"),
            .init("cb_xs_ldhyl", "乐斗回忆录"),
            .init("cb_xs_yxlb", "迎新礼包"),
            .init("cb_xs_sdlb", "圣诞礼包"),
            .init("cb_xs_yuanxiao_lb", "元宵礼包"),
            .init("cb_xs_bxqy", "冰雪企缘"),
        ]),
        SettingSection(title: "乐斗大笨钟", items: [
            .init("cb_dbz_1", "9-12点"),
            .init("cb_dbz_2", "12-15点"),
            .init("cb_dbz_3", "15-18点"),
            .init("cb_dbz_4", "18-21点"),
        ]),
        SettingSection(title: "菜菜厨房", items: [
            .init("cb_cc_sw", "12-14点"),
            .init("cb_cc_xw", "18-20点"),
            .init("cb_cc_ws", "22-24点"),
        ]),
        SettingSection(title: "幸运金蛋", items: [
            .init("cb_jd_sw", "11-14点"),
            .init("cb_jd_xw", "19-22点"),
        ]),
        SettingSection(title: "问鼎助威相关", items: [
            .init("rb_wd_1", "东海"),
            .init("rb_wd_2", "南荒"),
            .init("rb_wd_3", "西泽"),
            .init("rb_wd_4", "北寒"),
            .init("cb_wd_zw_6", "周六助威"),
            .init("cb_wd_zw_7", "周日助威"),
            .init("cb_bangpai_wending", "问鼎奖励"),
        ]),
        SettingSection(title: "乐斗黄历", items: [
            .init("cb_hl_lgz", "领龟甲"),
            .init("cb_hl_zb", "领占卜"),
        ]),
        SettingSection(title: "全民乱斗", items: [
            .init("cb_ld_hw", "六门会武"),
            .init("cb_ld_mz", "武林盟主"),
            .init("cb_ld_wl", "武林大会"),
        ]),
        SettingSection(title: "首胜许愿", items: [
            .init("cb_xy_jl", "许愿奖励"),
            .init("cb_xy_zd", "自动许愿"),
            .init("cb_xy_bx", "许愿宝箱"),
        ]),
        SettingSection(title: "生日祝福", items: [
            .init("cb_sr_dl", "专属大礼"),
            .init("cb_sr_zf", "自动祝福"),
            .init("cb_sr_lb", "友好礼包"),
        ]),
        SettingSection(title: "收发礼物", items: [
            .init("cb_lw_sq", "收取礼物"),
            .init("cb_lw_sy", "索要礼物"),
            .init("cb_lw_zs", "赠送礼物"),
        ]),
        SettingSection(title: "每日宝箱", items: [
            .init("cb_bx_1", "铜制宝箱"),
            .init("cb_bx_2", "银制宝箱"),
            .init("cb_bx_3", "金制宝箱"),
        ]),
        SettingSection(title: "每日兑换", items: [
            .init("cb_duihuan_tuposhi", "10突破"),
            .init("cb_duihuan_zhulong", "10烛龙"),
            .init("cb_duihuan_huangniao", "10黄鸟"),
            .init("cb_duihuan_kuiniu", "10夔牛"),
            .init("cb_duihuan_taotie", "10饕餮"),
            .init("cb_duihuan_canmo", "10残魔"),
            .init("cb_duihuan_lianqi", "10炼器石"),
            .init("cb_duihuan_qianghuashu", "10强化书"),
            .init("cb_duihuan_zhenjin", "10真金"),
            .init("cb_duihuan_xiuwei", "10修为丹"),
            .init("cb_duihuan_xunjieshi", "10迅捷石"),
            .init("cb_duihuan_ziheiyu", "10紫黑玉"),
            .init("cb_duihuan_riyao", "10日曜石"),
            .init("cb_duihuan_yueguang", "10月光石"),
            .init("cb_duihuan_feicui", "10翡翠石"),
            .init("cb_duihuan_manao", "10玛瑙石"),
            .init("cb_duihuan_aomi", "10奥秘元素"),
            .init("cb_duihuan_siling", "10四灵魂石"),
        ]),
        SettingSection(title: "梦想之旅", items: [
            .init("cb_lvyou_putong", "普通机票"),
            .init("cb_lvyou_quyu", "区域奖励"),
            .init("cb_lvyou_zong", "总奖励"),
        ]),
        SettingSection(title: "邪神秘宝", items: [
            .init("cb_xieshen_gaoji", "高级秘宝"),
            .init("cb_xieshen_jipin", "极品秘宝"),
            .init("cb_xieshen_jinse", "金色秘宝"),
        ]),
        SettingSection(title: "帮派商会", items: [
            .init("cb_shanghui_baoku", "帮派宝库"),
            .init("cb_shanghui_jiaoyi", "交易会所"),
            .init("ed_shanghui_jiaoyi", "交易会所商品ID(可选,逗号分隔)", kind: .text),
            .init("cb_shanghui_shangdian", "兑换商店"),
            .init("ed_shanghui_shangdian", "兑换商店type_id(可选)", kind: .text),
        ]),
        SettingSection(title: "帮派奖励", items: [
            .init("cb_bangpai_huoyue", "帮派活跃"),
            .init("cb_bangpai_bangzhan", "帮战奖励"),
        ]),
        SettingSection(title: "巅峰之战", items: [
            .init("cb_dianfeng_lingjiang", "自动领奖"),
            .init("cb_dianfeng_baoming", "自动报名"),
            .init("rb_dianfeng_nan", "南派", true, radioGroup: "lj_dianfeng"),
            .init("rb_dianfeng_bei", "北派", radioGroup: "lj_dianfeng"),
            .init("rb_dianfeng_suiji", "随机", radioGroup: "lj_dianfeng"),
        ]),
        SettingSection(title: "飞升大作战", items: [
            .init("cb_feisheng_lingjiang", "自动领奖"),
            .init("cb_feisheng_baoming", "自动报名"),
            .init("cb_feisheng_baoming_sp", "使用双排"),
            .init("rb_feisheng_pipei", "匹配", radioGroup: "feisheng"),
            .init("rb_feisheng_paiwei", "排位", radioGroup: "feisheng"),
            .init("rb_feisheng_suiji", "随机6:1", true, radioGroup: "feisheng"),
            .init("cb_feisheng_paiwei_beizhan", "飞升-单排-自动备战"),
        ]),
        SettingSection(title: "武林盟主", items: [
            .init("cb_mengzhu_lingjiang", "自动领奖"),
            .init("cb_mengzhu_baoming", "自动报名"),
            .init("cb_mengzhu_jingcai", "自动竞猜"),
            .init("rb_mengzhu_huangjin", "黄金", true, radioGroup: "lj_mengzhu"),
            .init("rb_mengzhu_baiyin", "白银", radioGroup: "lj_mengzhu"),
            .init("rb_mengzhu_qingtong", "青铜", radioGroup: "lj_mengzhu"),
        ]),
        SettingSection(title: "黄金帮派联赛", items: [
            .init("cb_liansai_lingjiang", "领小宝箱"),
            .init("cb_liansai_lingjiang_saiji", "领大宝箱"),
            .init("cb_liansai_fangshou", "自动防守"),
        ]),
        SettingSection(title: "帮派远征", items: [
            .init("cb_yuanzheng_jiedian", "领节点"),
            .init("cb_yuanzheng_daoyu", "领岛屿"),
        ]),
        SettingSection(title: "群雄逐鹿", items: [
            .init("cb_qunxiong_lingjiang", "领本轮"),
            .init("cb_qunxiong_lingjiang_paihang", "领排行"),
            .init("cb_qunxiong_baoming", "自动报名"),
        ]),
        SettingSection(title: "竞技场", items: [
            .init("cb_jingjichang_lingjiang", "领每日"),
            .init("cb_jingjichang_paihang", "领排行"),
            .init("cb_jingjichang_hetu", "换10河图"),
        ]),
        SettingSection(title: "会武", items: [
            .init("cb_huiwu_zhuwei", "助威丐帮"),
            .init("cb_huiwu_lingjiang", "自动领奖"),
        ]),
        SettingSection(title: "门派邀请赛", items: [
            .init("cb_menpai_lingjiang", "自动领奖"),
            .init("cb_menpai_yaoqing", "自动邀请"),
            .init("ed_menpai_yaoqing", "邀请QQ(每行一个)", kind: .text),
            .init("cb_menpai_jinzu", "自动进组"),
            .init("ed_menpai_jinzu", "进组邀请人QQ", kind: .text),
        ]),
        SettingSection(title: "粮草掠夺战", items: [
            .init("cb_liangcao_lingjiang", "领参与"),
            .init("cb_liangcao_shengfu", "领胜负"),
        ]),
        SettingSection(title: "帮派踢馆站", items: [
            .init("cb_tiguan_lingjiang", "领排行"),
            .init("cb_tiguan_shengfu", "领胜负"),
        ]),
        SettingSection(title: "武林", items: [
            .init("cb_wulin_shouji", "手机区"),
            .init("cb_wulin_diannao", "电脑区"),
            .init("cb_wulin_diannao_15", "15点报电脑区"),
        ]),
        SettingSection(title: "报名侠侣", items: [
            .init("cb_baoming_xialv", "手机侠侣"),
            .init("cb_baoming_xialv_diannao", "电脑侠侣"),
        ]),
        SettingSection(title: "报名群侠", items: [
            .init("cb_baoming_qunxia", "13点报群侠"),
            .init("cb_baoming_qunxia_2", "15点报群侠"),
        ]),
        SettingSection(title: "结拜争霸赛", items: [
            .init("cb_jiebai_baoming", "自动报名"),
            .init("rb_jb_bm_1", "50↓", radioGroup: "lj_jb_bm"),
            .init("rb_jb_bm_2", "70↓", radioGroup: "lj_jb_bm"),
            .init("rb_jb_bm_3", "90↓", radioGroup: "lj_jb_bm"),
            .init("rb_jb_bm_5", "110↓", radioGroup: "lj_jb_bm"),
            .init("rb_jb_bm_4", "无限制", true, radioGroup: "lj_jb_bm"),
            .init("cb_jiebai_zhuwei", "自动助威"),
            .init("rb_jb_zw_1", "霸王队", true, radioGroup: "lj_jb_zw"),
            .init("rb_jb_zw_2", "工号队", radioGroup: "lj_jb_zw"),
            .init("cb_jiebai_lingjiang", "自动领奖"),
        ]),
    ]

    static var defaultMap: [String: Bool] {
        var map: [String: Bool] = [:]
        for sec in sections {
            for item in sec.items where item.kind == .check {
                map[item.key] = item.default
            }
        }
        return map
    }

    static let bucketNames = ["全部", "每日", "报名", "年卡", "更多"]

    static func matchesBucket(_ section: SettingSection, _ bucket: String) -> Bool {
        let t = section.title
        let daily = t.contains("每日") || t.contains("优惠") || t.contains("领取经验")
        let signup = t.contains("报名") || t.contains("龙凰") || t.contains("遗迹")
        let card = t.contains("年卡") || t.contains("月卡")
        switch bucket {
        case "每日": return daily
        case "报名": return signup
        case "年卡": return card
        case "更多": return !daily && !signup && !card
        default: return true
        }
    }
}
