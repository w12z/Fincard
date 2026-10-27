"""Generate card illustrations with GLM-Image; never save credentials or signed URLs."""

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
    "example_aid": "一艘小货船停在码头，前景是成排援助物资箱与麦穗，无人物",
    "arcadia_aid_fireside": "一台老式收音机、复古话筒与壁炉火焰，舒适温暖的小房间，无人物",
    "arcadia_aid_foreign_loan": "来自远方的资金箱、盖圆印的汇票信封与两座由虚线连接的小银行，无人物",
    "arcadia_aid_gold": "保险柜前放着整齐金条与一个打开的储备箱，简洁有力的金色几何块",
    "temporary_fiscal_support": "两个并排的封好资金袋、两格装饰性日历与一本财政账册，无人物",
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
    target = OUTPUT / f"{identifier}.png"
    if target.exists() and not overwrite:
        return identifier, None
    if stopped.is_set():
        return identifier, None
    scene = SCENES.get(identifier, definition.get("description", definition["display_name"]))
    prompt = (
        "为经济主题桌游绘制一幅非写实的二维手绘插画，不画卡牌边框。"
        f"具体画面：{scene}。"
        "统一采用平面绘本与复古丝网版画风：粗而清晰的深蓝轮廓、简化几何造型、大色块、轻微纸张颗粒，"
        "仅用奶油白、藏蓝、青绿与陶土橙四种主色，图案鲜明，像手绘桌游插画而非照片。"
        "以物件、文书和建筑为主体，完全不画人物、人脸、人像、手部或身体。"
        "不使用写实油画、半写实、电影光照、摄影、逼真材质、三维渲染或复杂细节。"
        "主体集中在画面中央的横向区域，上下保留环境空间，适合裁切为横向卡牌插画。"
        "不出现任何可读文字、字母、数字、标语、真实国旗、水印、边框或游戏界面，不画拼贴或多格画面。"
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
        ImageOps.fit(image.convert("RGB"), (512, 288), Image.Resampling.LANCZOS).save(temporary, format="PNG")
    temporary.replace(target)
    return identifier, {"model": "glm-image", "style": "flat-print-v1", "prompt": prompt}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--workers", type=int, choices=[1, 2], default=1)
    parser.add_argument("--icons-only", action="store_true")
    parser.add_argument("--only", nargs="*", help="Generate selected IDs only")
    args = parser.parse_args()
    generate_icons()
    if args.icons_only:
        return
    key = os.environ.get("ZHIPU_API_KEY")
    if not key:
        parser.error("Set ZHIPU_API_KEY")
    from PIL import Image  # Resolve the dependency before paid requests.
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUTPUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    definitions = [json.loads(path.read_text(encoding="utf-8-sig")) for folder in ["cards", "aids"] for path in sorted((ROOT / "data" / folder).glob("*.json"))]
    if args.only:
        definitions = [definition for definition in definitions if definition["id"] in args.only]
    stopped = threading.Event()
    failed = False
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(generate, definition, key, args.overwrite, stopped) for definition in definitions]
        for future in as_completed(futures):
            try:
                identifier, entry = future.result()
                if entry:
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
