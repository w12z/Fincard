"""Generate local cabinet art with GLM-Image. Credentials stay in the environment."""

import argparse
import json
import os
from pathlib import Path
import random
import time
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "portraits"
ENDPOINT = "https://open.bigmodel.cn/api/paas/v4/images/generations"


def generate(path: Path, key: str, overwrite: bool) -> str:
    cabinet = json.loads(path.read_text(encoding="utf-8"))
    target = OUTPUT / (cabinet["id"] + ".png")
    if target.exists() and not overwrite:
        return f"{cabinet['id']}: existing portrait retained"
    rng = random.SystemRandom()
    appearance = rng.choice([
        "中年女性，深棕色短卷发，深色西装，沉着神情",
        "中年男性，黑色侧分短发，细框眼镜，灰色西装",
        "年长男性，银灰色头发，修剪整齐的胡须，深蓝色西装",
        "中年女性，黑色盘发，棕色西装，坚毅神情",
        "中年男性，棕色短发，无胡须，粗花呢西装",
        "年长女性，银灰色短发，圆框眼镜，深绿色西装",
        "中年男性，深色皮肤，极短头发，酒红色领带，深色西装",
    ])
    prompt = (
        "为经济策略卡牌游戏绘制一张虚构内阁成员头像。"
        f"职务：{cabinet['display_name']}。人物外貌：{appearance}。"
        "1930年代复古手绘油画插画，半写实，清晰利落的笔触，低饱和藏蓝与暖金配色，"
        "柔和侧光，纯净深蓝灰背景。单个人物居中，正面或轻微侧面，头部和肩膀特写，"
        "头顶完整保留，脸部占画面大部分，缩小至64像素仍可识别。正方形构图。"
        "无文字，无字母，无数字，无标志，无水印，无边框，不画真实历史人物，不画拼贴。"
    )
    payload = json.dumps({"model": "glm-image", "prompt": prompt, "size": "1280x1280"}).encode()
    request = urllib.request.Request(ENDPOINT, data=payload, headers={
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    })
    try:
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=240) as response:
                    result = json.load(response)
                break
            except urllib.error.HTTPError as error:
                try:
                    detail = json.loads(error.read()).get("error", {})
                except (ValueError, AttributeError):
                    detail = {}
                code = str(detail.get("code", "unknown"))
                if error.code == 429 and code in {"1302", "1303"} and attempt < 2:
                    time.sleep(10 * (attempt + 1))
                    continue
                raise RuntimeError(f"{cabinet['id']}: HTTP {error.code}, API code {code}") from None
        url = result["data"][0]["url"]
        if not url.startswith("https://"):
            raise ValueError("Image response did not contain an HTTPS URL")
        with urllib.request.urlopen(url, timeout=120) as response:
            image = response.read()
        # Use Pillow to validate the image and store compact, uniform PNG assets.
        from io import BytesIO
        from PIL import Image
        with Image.open(BytesIO(image)) as source:
            source.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS).save(target)
        target.with_suffix(".json").write_text(json.dumps({
            "model": "glm-image", "cabinet_id": cabinet["id"], "prompt": prompt,
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return f"{cabinet['id']}: generated"
    except urllib.error.HTTPError as error:
        # Never print request headers, signed URLs, or credentials.
        raise RuntimeError(f"{cabinet['id']}: HTTP {error.code}") from None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="Regenerate existing portraits (paid API calls)")
    args = parser.parse_args()
    key = os.environ.get("ZHIPU_API_KEY")
    if not key:
        parser.error("Set ZHIPU_API_KEY in the environment")
    from PIL import Image  # Check the dependency before making any paid requests.
    OUTPUT.mkdir(parents=True, exist_ok=True)
    paths = sorted((ROOT / "data" / "cabinets").glob("*.json"))
    # Image generation has its own concurrency quota. Stop on the first failure.
    for path in paths:
        print(generate(path, key, args.overwrite), flush=True)


if __name__ == "__main__":
    main()
