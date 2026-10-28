# Fincard

经济题材卡牌构筑游戏。选择一个国家，通过投资、政策和改革应对经济变化，在期限内完成发展目标。

## 开始游戏

从 [Releases](https://github.com/w12z/Fincard/releases) 下载 Windows 试玩包，完整解压后运行 `Fincard.exe`。无需安装 Godot，也不需要联网。

- 支持 Windows 10/11 64位，需要支持 OpenGL 3.3 的显卡及驱动。
- 默认分辨率为1920×1080，窗口大小可调。
- 新港共和国仅仅是调试测试国家，游戏内容缺乏；建议游玩阿卡迪亚共和国。
- 目前不支持存档，退出或返回菜单后需要重新开局。

## 玩法

每回合抽5张牌，使用预算和政治行动点出牌。预算按财年发放，政治点每回合重置。内阁提供持续效果，援助是一次性消耗品。每4回合有一组随机奖励，跨年时领取财年奖励。

| 国家 | 任期与目标 | 特点 |
| --- | --- | --- |
| 新港共和国 · 入门 | 3年内达到 GDP ≥135、失业率 ≤6、通胀 ≤6；最早第9回合获胜 | 熟悉投资、就业和物价之间的取舍 |
| 阿卡迪亚联邦 · 危机 | 5年内达到 GDP ≥210、失业率 ≤6、信心 ≥45；最早第24回合获胜 | 从繁荣期经历金融危机，再选择复苏路线 |

满足全部目标后，在回合结束时判胜；触及失败线或任期届满仍未达标则失败。各国的具体条件可在游戏内「最终目标」查看。

## 从源码运行

使用 Godot **4.7.1** 导入 `project.godot`，按 F5 运行。Windows 命令行中的 `godot` 可替换为 `godot_console`。

```sh
godot --path .
```

主要目录：

| 路径 | 内容 |
| --- | --- |
| `core/` | 游戏状态、命令、效果和回合结算 |
| `app/` | 数据加载与经济模型 |
| `presentation/` | 界面、动画和音效 |
| `data/` | 国家、卡牌、事件、内阁和援助定义 |
| `assets/` | 插画、头像、图标、字体和音效 |
| `tests/` | 规则与界面检查 |
| `tools/` | 素材生成脚本 |

结算公式与数据结构见 [economy.md](economy.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

启动和经济规则检查示例：

```sh
godot --headless --path . tests/sfx_startup_probe.tscn --audio-driver Dummy
godot --headless --path . --script tests/growth_feedback_tests.gd
```

## 资源

卡牌插画和内阁头像由 GLM-Image 生成，成品随游戏提供。重新生成图片会调用付费接口，所需的 `ZHIPU_API_KEY` 通过本机环境变量设置。

音效由本地脚本合成，文件说明见 [音效资源](assets/audio/sfx/README.md)。数字字体使用 Roboto Mono，许可见 [字体资源](assets/fonts/README.md)。
