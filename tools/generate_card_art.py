"""Generate card and event illustrations with GLM-Image; never save credentials or signed URLs."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
import json
import os
from pathlib import Path
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "cards"
ICONS = ROOT / "assets" / "icons" / "modifiers"
ENDPOINT = "https://open.bigmodel.cn/api/paas/v4/images/generations"

SCENES = {
    "investment_capacity_update": "一座简洁的工厂内，旧齿轮和新的青绿色机械并排，缓慢传动的传送带与几只工具箱，画面没有人物",
    "investment_local_procurement": "地方小仓库前堆放木箱、工具与食材，旁边是采购清单和封好的小钱袋，画面没有人物",
    "investment_inventory_restock": "整齐排列的木货架上放着麦袋、金属零件和运输箱，前景是一辆装满物资的小推车，画面没有人物",
    "policy_asset_disposal": "一只打开的旧资产储藏箱、铜色钥匙、封好的交易凭证与两叠硬币，画面没有人物",
    "policy_procedural_motion": "一枚木槌、一张折起的议事动议文件与一枚议会印章，背景是简洁的议事厅剪影，画面没有人物",
    "policy_agenda_sorting": "桌面上一张收起的议程纸页和两张新展开的方案，旁边摆着分类夹与钢笔，纸张只有装饰线条，画面没有人物",
    "policy_process_review": "一份夹在文件板上的流程清单、放大镜与半开的档案抽屉，纸张只画几何符号，画面没有人物",
    "policy_special_approval": "一份有圆形橙红印记的拨款核准单、两枚金币与小型建筑模型，画面没有人物",
    "example_card": "对称摆放的面包、蔬菜篮和米袋，一架平衡的小天平与没有文字的价签",
    "starter_infrastructure": "横跨蓝色河流的红色钢桥、铁路、起重机与简洁城市剪影",
    "starter_small_business": "一间带条纹遮阳棚的小面包店，窗台上摆着面包，门口有盆栽",
    "starter_training": "摊开的技能教材旁放着扳手、齿轮与一台小型车床，工具是主体",
    "starter_efficiency": "一份盖有蜡印的行政文书，旁边是整齐档案与一枚齿轮形印章",
    "arcadia_policy_bond_yield": "桌上斜放的装饰性证券纸张、铜色怀表与逐渐升高的三叠硬币",
    "arcadia_recover_open_market": "中央位置一叠盖圆印的证券纸张，旁边是打开的钱箱与简洁银行建筑剪影",
    "arcadia_recover_tariff": "码头上的木制货箱、机械吊钩与海关印章，背景只有货轮轮廓",
    "arcadia_recover_trade": "一份两侧盖着不同形状蜡印的贸易契约，两艘小货船由弧线连接",
    "arcadia_recover_sec": "一份压在放大镜下的证券法案文书，旁边有木槌、装饰性折线图和整齐证券",
    "arcadia_recover_fdic": "一份带圆形金色蜡印的保险法案文书，后方是关闭的金库与整齐存折",
    "arcadia_recover_bank_holiday": "关闭的复古银行铁门，一把大钥匙与门边没有文字的小挂牌",
    "arcadia_recover_gold": "脱开的金色链环与一枚金币，金币下面压着盖蜡印的货币文书",
    "arcadia_recover_aaa": "铺在桌上的农业法案文书，一束麦穗、小谷仓与横向条带状农田",
    "arcadia_reform_tax_wealth": "盖有铜色蜡印的法案文书，左右高低不同的硬币堆与一架小天平",
    "arcadia_reform_austerity": "整齐的账本、算盘和分类文件夹，几张收据被整理成规整的小叠",
    "arcadia_reform_labor_rights": "中央是一份盖蜡印的劳动法案，左右交叉摆放两把扳手，背景为工厂齿轮轮廓",
    "arcadia_reform_social_security": "一份盖蜡印的社会保障文书，旁边是小房屋、医药盒与一袋粮食",
    "arcadia_reform_labor_education": "一份教育法案文书、摊开的书本、铅笔与蓝色齿轮，构图简洁",
    "arcadia_relief_works": "铺设一半的石砌道路、独轮车、铁铲与远处公共建筑，画面不出现人物",
    "arcadia_relief_ccc": "成排的小树、山坡梯田、溪流与一把铲子，几何分块的绿色山林",
    "arcadia_relief_dole": "装有面包、牛奶与蔬菜的救济纸袋，旁边放一只封好的信封",
    "arcadia_relief_farm": "一片休耕农田和一片麦田并排，前景放着农具与补贴信封",
    "policy_legislative_liaison": "一只复古电话、两个敞开的文件夹与议事厅建筑的小剪影",
    "policy_coalition_negotiation": "圆形会议桌上放着三份交叠文件与三只颜色不同的钢笔，无人物",
    "policy_national_consensus": "宏大的圆形会议桌、围成一圈的空座椅与中央盖印的共同文件，无人物",
    "policy_emergency_cabinet_meeting": "深蓝背景中的圆桌、复古电话、紧急文件夹与一盏明亮台灯，无人物",
    "policy_emergency_relief": "打开的应急物资箱，里面整齐放着粮食、药品和封好的资金信封",
    "reform_executive_mandate": "一张展开的授权文书、粗大的印章与羽毛笔，中央红色蜡印清晰突出",
    "reform_earmarked_funds": "一份带专用封签的拨款文书、金币袋与一座小型桥梁模型",
    "reform_policy_synergy": "三份不同颜色的部门文件由几何连线连接，中央是一份盖蜡印的协调法案",
    "reform_deficit_spending": "一本展开的预算账册、一份带红色蜡印的法案、空钱箱与倾斜的小天平",
    "reform_fiscal_capacity": "一份盖蜡印的财政文书、账册与从低到高排列的三叠硬币",
    "reform_budget_reserve": "一份卷起的结转法案、带锁储备箱与一只怀表，箱中露出少量金币",
    "reform_research_network": "盖印的研究法案文书居中，周围是放大镜、笔记本与相互连接的圆形节点",
    "special_national_strategy": "一张蓝色规划文书铺在桌上，用白色几何线连接桥梁、工厂、铁路与港口模型",
    "reform_emergency_authority": "带醒目红色蜡印的授权文书、一枚木槌与一束风格化闪电，物件居中",
    "reform_policy_reserve": "一本夹着单张备忘录的皮质文件夹，纸页上有装饰性线条，旁边是书签和钢笔",
    "reform_rotation_execution": "一份轮值法案文书与围成环形的三枚不同印章，环形箭头仅为图案",
    "reform_project_continuity": "两份几乎相同的工程文书前后叠放，中间由弧形箭头连接，旁边是桥梁模型",
    "reform_midterm_review": "放大镜下一份待审文书，旁边一张收起的文件和两张展开的备选文件",
    "reform_agenda_reserve": "一份带书签的议程文书、两个封好的文件夹与一只怀表",
    "reform_permanent_coordination": "一张常设圆形会议桌与三张空座椅居中，桌面摆着三份只有装饰线条的协调文件、一枚橙色圆印和复古台钟，后方是青绿色议事厅拱窗，没有人物，纸张上完全无字",
    "example_aid": "一艘小货船停在码头，前景是成排援助物资箱与麦穗，无人物",
    "arcadia_aid_fireside": "一台老式收音机、复古话筒与壁炉火焰，舒适温暖的小房间，无人物",
    "arcadia_aid_foreign_loan": "来自远方的资金箱、盖圆印的汇票信封与两座由虚线连接的小银行，无人物",
    "arcadia_aid_gold": "保险柜前放着整齐金条与一个打开的储备箱，简洁有力的金色几何块",
    "temporary_fiscal_support": "两个并排的封好资金袋、两格装饰性日历与一本财政账册，无人物",
    "route_construction_restart_law": "一份盖有陶土橙蜡印的复工法案居中，旁边摆放工厂模型、扳手和重新连接的传动齿轮",
    "route_construction_extension_law": "一份带蜡印的工程接续法案，两侧是前后相连的桥梁模型与一卷展开的施工蓝图",
    "route_construction_repayment_law": "一份盖蜡印的回款制度文书、工程进度夹板与从桥梁模型回到钱箱的几枚硬币",
    "route_construction_key_projects": "一座正在接续施工的大型钢桥，桥下是河流，旁边有起重机、石材与重新铺设的铁轨",
    "route_construction_local_projects": "小镇街道旁正在铺设的水管、路面石块与小型水塔，前景放着施工工具和配套物资箱",
    "route_construction_project_returns": "一份盖圆印的工程验收收据与打开的钱箱，几枚硬币沿弧线从小型桥梁模型流回账本",
    "route_construction_national_mobilization": "横向展开的铁路、钢桥与水坝构成简洁建设网络，前景是大型起重机吊钩和卷起的工程蓝图",
    "route_construction_joint_acceptance": "两份并排的工程验收夹板、醒目的橙色圆印与桥梁模型，纸页上只有装饰性勾形图案",
    "route_construction_equipment_coordination": "整齐摆放的施工车辆模型、齿轮与工具箱，中央一台青绿色吊车向另一处工地调配设备",
    "route_employment_guarantee_law": "一份盖蜡印的就业保障法案，旁边是工具箱、工厂模型和整齐叠放的岗位文件",
    "route_employment_consumption_law": "一份盖蜡印的消费法案、装有面包和蔬菜的购物篮与小商店模型，几枚硬币围在一旁",
    "route_employment_mutual_support_law": "一份盖蜡印的互助法案居中，周围小房屋、药箱与粮食袋由简洁圆弧连接",
    "route_employment_community_rebuilding": "一处修缮中的社区广场、小图书馆与成排屋顶，前景是木板、砖块、工具箱和新栽的树苗",
    "route_employment_emergency_allowance": "打开的生活补助信封、少量硬币与装有面包牛奶的纸袋，旁边是温暖的小房屋模型",
    "route_employment_job_matching": "两只展开的岗位档案夹由一枚齿轮连接，旁边是扳手、工厂模型和没有文字的几何清单",
    "route_employment_national_jobs": "铁路、农田与工厂在横向画面中相连，前景整齐摆放铁铲、扳手和一份盖圆印的计划文件",
    "route_employment_consumer_credit": "一间重新开门的小商店、打开的银行账册与几枚硬币，前景放着购物篮和简洁贷款凭证",
    "route_employment_national_broadcast": "一台老式收音机与复古广播话筒居中，柔和的同心波纹连接远处的商店与房屋剪影",
    "route_fiscal_coordination_law": "一份盖蜡印的财政统筹法案、多只分类资金信封与中央账本，简洁连线汇入同一个钱箱",
    "route_fiscal_financing_law": "一份盖蜡印的融资法案、两座银行模型与一架平衡天平，前景摆着整齐资金袋",
    "route_fiscal_rapid_disbursement_law": "一份带醒目蜡印的拨付制度文书，旁边是打开的文件传递盒、怀表与整齐硬币",
    "route_fiscal_emergency_allocation": "一只刚打开的应急资金箱、橙色封签与几叠硬币，旁边台灯照亮一份拨款文件",
    "route_fiscal_coordination_funding": "圆桌上两份相互衔接的部门文件、封好的资金信封与复古电话，文件只有装饰线条",
    "route_fiscal_joint_financing": "两个资金袋共同围着一座新建工厂模型，前景是一份双圆印的融资契约与少量硬币",
    "route_fiscal_special_recovery_budget": "一本厚实的特别预算账册、大型资金箱与成排资金信封，中央拨款文件带醒目橙色圆印",
    "route_fiscal_cross_department_mobilization": "三份不同颜色的部门文件在圆桌中央交叠，周围是复古电话、齿轮和三枚印章，无人物",
    "route_fiscal_public_private_investment": "公共建筑模型与工厂模型并排，两侧资金袋通过弧线连接中央正在建设的桥梁",
    "arcadia_ev_bank_panic": "空荡的银行大厅横向展开，敞开的金库露出空货架，前景是倾倒的硬币筒和散落的存折，窗外几座银行建筑的灯光熄灭，表现连锁恐慌，无人物无文字",
    "arcadia_ev_bank_run": "一座复古银行的取款窗口和打开的抽屉，前景几本空白存折、提款凭证与快要见底的钱箱，画面没有队伍或人物，没有可读文字",
    "arcadia_ev_black_thursday": "宏大的复古证券交易所立面，前景证券纸张和断开的齿轮散落，陶土橙色阶梯折线从左上猛然坠向右下，图表不带坐标数字，象征金融崩盘，无人物无字",
    "arcadia_ev_bonus_army": "议会建筑外的空帐篷、旧军靴、水壶与成叠的无字请愿信封横向摆放，温和克制的历史场景，不画旗帜武器、标语、人物或文字",
    "arcadia_ev_congress_block": "空议事厅内的长桌和高背空座椅，中央一枚木槌压着被横杆挡住的无字卷宗，窗外深蓝建筑轮廓，表现法案受阻，无人物无字",
    "arcadia_ev_credit_freeze": "被霜纹覆盖的银行钱箱与停止运转的工厂齿轮，断开的青绿色资金输送管连接空厂房，前景搁着冷却的运输箱，横向场景，无人物无字",
    "arcadia_ev_dust_bowl": "陶土橙色尘风掠过干裂农田，几何分块的枯麦、倾斜谷仓与闲置犁具，远方公路上只有一辆装满家当的空拖车，无人物无字",
    "arcadia_ev_europe_default": "两座不同风格的复古海外银行隔海相望，一条断裂的资金链和封起的无字汇票信封居中，倾斜天平上压着少量硬币，无真实地图无人物无字",
    "arcadia_ev_farm_depression": "小谷仓前堆着无人收购的麦袋和农产品木箱，农田在远处横向铺开，空交易天平与合上的钱箱放在前景，没有价签和数字，无人物无字",
    "arcadia_ev_farm_foreclosure": "一座被大锁锁住的农舍和谷仓，前景是钥匙、无字抵押文件与收起的农具，篱笆后的农田安静荒芜，不画封条文字，无人物",
    "arcadia_ev_financial_reorganization": "剖开的金库模型与整齐的资产抽屉，桌上放着放大镜、分门别类的无字银行账册和重新连接的齿轮，象征整理金融秩序，无人物无字",
    "arcadia_ev_gold_outflow": "复古港口的运输轨道伸向远处货船，几箱金条正离开打开的储备金库，弧形轨迹由银行通往海面，画面不含人物、标记文字或真实国旗",
    "arcadia_ev_inequality": "一架宽阔天平两端分别是高高的硬币堆和少量面包、麦袋，背景为繁荣工厂与小房屋的对比剪影，构图简洁，无人物无文字",
    "arcadia_ev_market_flourish": "复古海港与重新运转的工厂相连，成排出口木箱、机械吊臂和驶向远方的小货船，青绿色河道与橙色码头横向展开，无人物无字",
    "arcadia_ev_market_stabilization": "稳固的银行石柱与一架重新放平的天平，前景是合好的金库门、整齐无字证券和亮起的台灯，深蓝背景中出现温暖的橙色光块，无人物无字",
    "arcadia_ev_recovery_direction": "一张无字发展蓝图铺在圆形会议桌上，几何路线连接桥梁工地、社区商店和银行模型，三种方向并置在同一个完整场景，不画多格拼贴，无人物无字",
    "arcadia_ev_recovery_institutions": "木槌和橙色圆形印章摆在三份完全无字的制度卷宗前，后方几何桥梁、社区与银行模型形成整体，纸张仅有抽象线条，无人物无文字",
    "arcadia_ev_recovery_mobilization": "一条连通工厂、钢桥、商店和银行的铁路横向穿过城市，前景有配套工具箱、物资箱和展开的无字建设蓝图，充满复苏动能，无人物无字",
    "arcadia_ev_recovery_plan": "展开的无字城市规划图上摆着公共道路、水塔和小工厂模型，铁铲、齿轮与麦穗在前景有序排列，温暖而克制的复苏场景，无人物无文字",
    "arcadia_ev_recovery_support": "前景整齐摆放建设工具、粮食纸袋与配套资金箱，后方道路将地方仓库、社区店铺和工厂相连，完整横向场景，无人物无文字",
    "arcadia_ev_speculation": "高低错落的硬币堆、装饰性证券纸张与向上攀升的橙色几何阶梯，底部支撑结构已经出现裂缝，背景证券交易所剪影，无坐标数字无人物无文字",
    "arcadia_ev_strike": "一间安静停机的工厂，静止传送带与挂起的工具箱居中，关闭的厂门前放着空白日程夹板和怀表，不画人群标语旗帜，无人物无字",
    "arcadia_ev_war_debt": "一张只有几何线条的海外债务文书横放在桌面，两侧是不同颜色的蜡印和银行模型，一枚怀表与折起的贸易契约放在旁边，无人物无字",
    "example_event": "复古国际港口里，粮食袋与原料箱堆在平衡天平旁，货船、吊车和橙色起伏折线构成横向贸易场景，无价格数字、文字或人物",
    "starter_export": "一间地方工厂通向明亮海港，前景成排的新出口货箱、麦穗和无字订单卷宗，青绿色小货船驶向远方，无人物无文字",
    "starter_supply": "码头运输轨道被堆积木箱挡住，机械吊臂停在半空，一段断开的桥梁和等待装货的小船在背景，表现物流中断，无人物无字",
}

ICON_PATHS = {
    "growth": '<path d="M6 25 13 18 19 21 28 9M21 9h7v7"/>',
    "target": '<circle cx="17" cy="17" r="12"/><circle cx="17" cy="17" r="7"/><circle cx="17" cy="17" r="2"/>',
    "employment": '<rect x="5" y="11" width="24" height="17" rx="3"/><path d="M12 11V7h10v4M5 18h24M15 17v5h4v-5"/>',
    "interest": '<path d="m4 12 13-7 13 7H4Zm3 3v11m7-11v11m7-11v11m7-11v11M4 29h26"/>',
    "income": '<rect x="5" y="11" width="24" height="18" rx="3"/><path d="M5 16h24M24 7v8m-4-4 4 4 4-4"/><circle cx="17" cy="23" r="3"/>',
    "reserve": '<rect x="6" y="6" width="22" height="24" rx="3"/><circle cx="17" cy="18" r="6"/><path d="M17 12v12m-6-6h12M3 11h3m-3 14h3"/>',
    "reward": '<path d="m17 4 4 8 9 2-6 7 1 10-8-5-8 5 1-10-6-7 9-2 4-8Z"/>',
    "confidence": '<path d="M4 19h6l4-9 6 17 4-8h6"/>',
    "draw": '<rect x="10" y="7" width="17" height="23" rx="2"/><path d="M23 7V4H6v23h4m5-12h7m-7 5h7"/>',
    "free": '<path d="m20 3-12 17h9l-3 12 13-18h-9l2-11Z"/>',
    "fund": '<path d="m5 15 12-10 12 10v15H5V15Zm6 15V19h12v11M3 15h28"/>',
    "repeat": '<path d="M7 12a11 11 0 0 1 20-1m0-6v7h-7M27 22A11 11 0 0 1 7 23m0 6v-7h7"/>',
    "retain": '<path d="M9 4h17v27l-8-6-9 6V4Z"/>',
    "review": '<rect x="5" y="5" width="18" height="24" rx="2"/><circle cx="22" cy="19" r="7"/><path d="m27 24 5 7M10 11h8m-8 5h5"/>',
    "rotation": '<path d="m17 4 6 8H11l6-8Zm-8 16 6 10H3l6-10Zm16 0 6 10H19l6-10ZM6 17a12 12 0 0 1 3-7m17 0a12 12 0 0 1 3 7m-9 14h-6"/>',
    "political": '<path d="m5 13 12-8 12 8H5Zm3 3v12m6-12v12m6-12v12m6-12v12M4 31h26"/>',
    "deficit": '<rect x="4" y="10" width="26" height="20" rx="3"/><path d="M4 15h26m-9 7h6M9 10V5h15v5"/>',
    "anchor": '<circle cx="17" cy="7" r="3"/><path d="M17 10v19M10 15h14M5 21c0 5 5 9 12 9s12-4 12-9M3 23l2-4 4 2m16 0 4-2 2 4"/>',
    "recovery": '<path d="M6 12a12 12 0 0 1 22 0m0-7v8h-8M28 23A12 12 0 0 1 6 23m0 6v-8h8M13 18h8m-4-4v8"/>',
    "modifier": '<path d="m17 3 4 10 10 4-10 4-4 10-4-10-10-4 10-4 4-10Z"/>',
}


class ContentBlockedError(RuntimeError):
    pass


def generate_icons():
    ICONS.mkdir(parents=True, exist_ok=True)
    for name, shape in ICON_PATHS.items():
        target = ICONS / f"{name}.svg"
        if not target.exists():
            target.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 34 34"><g fill="none" stroke="#365d82" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">' + shape + '</g></svg>\n', encoding="utf-8")


def generate(definition, key, overwrite, stopped):
    identifier = definition["id"]
    output = ROOT / "assets" / "events" if definition.get("_art_kind") == "events" else OUTPUT
    target = output / f"{identifier}.png"
    if target.exists() and not overwrite:
        return identifier, None
    if stopped.is_set():
        return identifier, None
    scene = SCENES.get(identifier, definition.get("description", definition.get("display_name", definition.get("title", identifier))))
    prompt = (
        "为经济主题桌游绘制一幅非写实的二维手绘插画，不画卡牌边框。"
        f"具体画面：{scene}。"
        "统一采用平面绘本与复古丝网版画风：粗而清晰的深蓝轮廓、简化几何造型、大色块、轻微纸张颗粒，"
        "仅用奶油白、藏蓝、青绿与陶土橙四种主色，图案鲜明，像手绘桌游插画而非照片。"
        "以物件、文书和建筑为主体，完全不画人物、人脸、人像、手部或身体。"
        "不使用写实油画、半写实、电影光照、摄影、逼真材质、三维渲染或复杂细节。"
        "主体集中在画面中央的横向区域，上下保留环境空间，适合裁切为横向卡牌插画。"
        "不出现任何可读文字、字母、数字、标语、真实国旗、水印、边框或游戏界面，不画拼贴或多格画面。"
        "文书和纸页必须完全无字，不要写出主题名称，只允许无意义装饰线条。"
    )
    payload = json.dumps({"model": "glm-image", "prompt": prompt, "size": "1280x1280"}).encode()
    request = urllib.request.Request(ENDPOINT, data=payload, headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json",
    })
    for attempt in range(5):
        if stopped.is_set():
            return identifier, None
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                result = json.load(response)
            break
        except urllib.error.HTTPError as error:
            try:
                code = str(json.loads(error.read()).get("error", {}).get("code", "unknown"))
            except (ValueError, AttributeError):
                code = "unknown"
            if error.code == 429 and code in {"1302", "1303"} and attempt < 4:
                time.sleep(15 * (attempt + 1))
                continue
            if code == "1301":
                raise ContentBlockedError(f"{identifier}: image content rejected by API (1301)") from None
            raise RuntimeError(f"{identifier}: HTTP {error.code}, API code {code}") from None
        except (TimeoutError, urllib.error.URLError):
            raise RuntimeError(f"{identifier}: generation request failed; not retried to avoid duplicate charges") from None
    url = result["data"][0]["url"]
    if not url.startswith("https://"):
        raise RuntimeError(f"{identifier}: response did not contain an HTTPS image URL")
    # Retry downloading the same generated image; never repeat a paid generation for a download error.
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                image_data = response.read()
            break
        except (urllib.error.URLError, TimeoutError):
            if attempt == 2:
                raise RuntimeError(f"{identifier}: image download failed") from None
            time.sleep(3)
    from PIL import Image, ImageOps
    with Image.open(BytesIO(image_data)) as image:
        temporary = target.with_suffix(".png.part")
        dimensions = (768, 384) if definition.get("_art_kind") == "events" else (512, 288)
        ImageOps.fit(image.convert("RGB"), dimensions, Image.Resampling.LANCZOS).save(temporary, format="PNG")
    temporary.replace(target)
    return identifier, {"model": "glm-image", "style": "flat-print-v1", "prompt": prompt}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--workers", type=int, choices=[1, 2], default=1)
    parser.add_argument("--icons-only", action="store_true")
    parser.add_argument("--only", nargs="*", help="Generate selected IDs only")
    parser.add_argument("--category", choices=["cards", "events", "all"], default="cards")
    args = parser.parse_args()
    generate_icons()
    if args.icons_only:
        return
    key = os.environ.get("ZHIPU_API_KEY")
    if not key:
        parser.error("Set ZHIPU_API_KEY")
    from PIL import Image  # Resolve the dependency before paid requests.
    folders = ["cards", "aids"] if args.category == "cards" else (["events"] if args.category == "events" else ["cards", "aids", "events"])
    definitions = []
    manifests = {}
    manifest_paths = {}
    for folder in folders:
        kind = "events" if folder == "events" else "cards"
        output = ROOT / "assets" / kind
        output.mkdir(parents=True, exist_ok=True)
        manifest_path = output / "manifest.json"
        if kind not in manifests:
            manifests[kind] = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
            manifest_paths[kind] = manifest_path
        for path in sorted((ROOT / "data" / folder).glob("*.json")):
            definition = json.loads(path.read_text(encoding="utf-8-sig"))
            definition["_art_kind"] = kind
            definitions.append(definition)
    if args.only:
        unknown = set(args.only) - {definition["id"] for definition in definitions}
        if unknown:
            parser.error("Unknown illustration IDs: " + ", ".join(sorted(unknown)))
        definitions = [definition for definition in definitions if definition["id"] in args.only]
    kinds = {definition["id"]: definition["_art_kind"] for definition in definitions}
    stopped = threading.Event()
    failed = False
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(generate, definition, key, args.overwrite, stopped) for definition in definitions]
        for future in as_completed(futures):
            try:
                identifier, entry = future.result()
                if entry:
                    manifest = manifests[kinds[identifier]]
                    manifest_path = manifest_paths[kinds[identifier]]
                    manifest[identifier] = entry
                    temporary = manifest_path.with_suffix(".json.part")
                    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                    temporary.replace(manifest_path)
                    print(f"{identifier}: generated with glm-image", flush=True)
            except Exception as error:
                if not isinstance(error, ContentBlockedError):
                    stopped.set()
                failed = True
                # Only our sanitized errors are printed; never print headers or response URLs.
                print(str(error) if isinstance(error, RuntimeError) else f"Image generation stopped: {type(error).__name__}", flush=True)
    if failed:
        raise SystemExit(1)
    print(f"GLM-Image assets ready: {len(definitions)} illustrations", flush=True)


if __name__ == "__main__":
    main()
