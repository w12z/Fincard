# Fincard 开发变更记录

本文档记录本项目自骨架搭建以来的全部变更与设计决策。当前状态：**可运行的完整骨架 + 一套可直接试玩的样板数据**（Godot 4.7.1，导入与启动均无错误）。

---

## 1. 项目初始化

- 建立 Godot 4 工程 `project.godot`，主场景 `presentation/main.tscn`。
- 确立分层架构，依赖方向 `presentation → app → core`：
  - `core/`：纯逻辑内核，不依赖场景树，确定性、可回放。
  - `app/`：文件 IO 与装配（加载数据、构建内核）。
  - `presentation/`：UI 与交互。
- 确定性随机 `core/rng.gd`（注入种子的 LCG），保证同种子同结果。

## 2. 数据驱动内容模型

新增以下定义类（均为纯数据，支持从 JSON 构建）：

| 文件 | 说明 |
| --- | --- |
| `core/card_def.gd` | 卡牌（双成本、标签、效果） |
| `core/scenario_def.gd` | 开局情形 / 国家 |
| `core/goal_def.gd` + `core/condition.gd` | 最终目标与胜负条件（`ge/le/gt/lt/eq`） |
| `core/economy_event_def.gd` + `core/event_choice.gd` | 随机事件（可带选项） |
| `core/cabinet_def.gd` | 内阁（遗物：永久修正 + 触发器） |
| `core/aid_def.gd` | 外部援助（消耗品） |
| `core/budget_plan_def.gd` | 年度预算档位 |
| `core/reward.gd` | 财年奖励选项 |
| `core/trigger.gd` + `core/trigger_engine.gd` | 触发器系统（级联、带安全上限） |
| `core/group_def.gd` | 组（单类型，`members` 列成员） |
| `core/effect.gd` + `core/effect_resolver.gd` | 效果与结算 |
| `core/modifier.gd` | 数值修正器（ADD/MUL/OVERRIDE，永久或限时） |

数据加载：`app/config_loader.gd`、`app/data_loader.gd`。

## 3. 财年 / 回合流程

- 回合状态机 `core/turn_state_machine.gd`：`TURN_START → DRAW → MAIN → TURN_END`。
- 一财年 = `rules.turns_per_year` 个回合。
- **开局即第一财年的财年总结**：开局先强制选择预算档位 + 三选一奖励，再进入第一财年的回合。
- 每满一财年进入财年总结：先选预算档位，再选三选一奖励（卡牌 / 内阁 / 援助），随后进入下一财年。
- 失败线：`loss_conditions` 任一满足；或超过 `deadline_years` 未达成目标。

## 4. 经济内核（`core/economy_model.gd`）

- **快照 + 同时结算**：tick 时先快照上回合指标，再用快照同时计算所有增量，消除顺序依赖。
- **派生指标层**：`register_derived(id, callable)`，内置 `growth`（GDP 增长率）、`debt_ratio`（债务/GDP）。
- **GDP 为水平值指标**，增长率降级为派生指标。
- 修正器栈求值：`value()` = 基础值依次叠加 ADD/MUL/OVERRIDE。
- 联动方程与系数：`app/economy_builder.gd` + `data/config/economy.json`，含菲利普斯曲线、Okun 定律、债务流量、信心/民意的反馈等，系数全部外置、默认 0。
- 债务公式（已按反馈去掉通胀侵蚀项）：`Δ债务 = 支出 − 收入 + 利息`。

## 5. 双资源系统

- 出牌同时消耗 **财政预算**（`cost`）与 **政治行动点**（`political_cost`）。
- 财政预算：按财年重设（预算档位的 `budget`）。
- 政治行动点：
  - 每财年一次**大额补充**（预算档位的 `political_capital`，累加）。
  - 每回合**小额补充** = `rules.political_capital_per_turn` + `economy.value("political_capital_gain")`（可由卡牌/内阁用修正器提升）。
- 已彻底移除旧的"每回合行动点"（`action_points`）。

## 6. 分组系统

- **每个组只属于一种类型**，独立文件 `data/groups/*.json`：
  ```json
  { "id": "example_card_group", "type": "cards",
    "display_name": "示例卡牌组", "members": ["card_id"] }
  ```
  `type` 取 `cards` / `cabinets` / `aids` / `budgets` / `events`。
- 国家用 `groups` 声明允许的组，支持按类型字典或平铺数组（平铺时组按自身 `type` 归类）。
- 规则：某类型配置了非空组列表后，仅"属于这些组且组类型匹配"的条目可用；未配置则不限制。
- 生效范围：财年奖励（卡牌/内阁/援助）、预算档位、每回合随机事件。
- 定义文件不需要 `group` 字段，成员关系全部集中在组文件；UI 悬停详情显示"所属组"。

## 7. 效果与条件

- 效果类型：`adjust_indicator`、`apply_modifier`、`remove_modifier`、`draw_cards`、`gain_budget`、`gain_political_capital`。
- **条件效果**：任意效果可带可选 `condition`（结构同目标条件），不满足则不生效。例：若通货膨胀 > 5，则通货膨胀 −1。
- 统一由 `Effect.from_dict` 解析，`EffectResolver` 结算。

## 8. 表现层 UI（`presentation/`）

- 全部程序化构建（无手写 tscn 节点），内核与 UI 完全解耦。
- `main.gd`：菜单 ↔ 游戏界面切换，应用主题与渐变背景。
- `scenario_menu.gd`：开局选择界面。
- `game_ui.gd`：游戏主界面
  - 顶栏：财年 / 回合 / 财政预算 / 政治行动点 / 状态。
  - 左栏：最终目标、经济指标（含派生）、生效修正、内阁、外部援助。
  - 中栏：手牌（显示双成本与效果明细）、牌库/弃牌、结束回合。
  - 右栏：事件日志。
  - 弹窗：随机事件、预算选择（强制）、财年奖励、胜负结算。
- `ui_theme.gd`：统一主题（渐变背景、圆角面板、PrimaryButton / CardButton 变体、明快配色）。
- `text_formatter.gd`：把 id 与效果翻译为中文描述。

## 9. 中文显示与结构化描述

- `data/config/labels.json`：指标 / 资源 / 事件名的中文映射；未配置的 id 原样回退。
- 采用"**标题 + 文本描述 + 具体作用**"结构；具体作用由 `effects` 自动生成，含具体数值，无需手写：
  - `2 回合内 税率 +2`
  - `若 通货膨胀 > 5，通货膨胀 -1`
  - `当「回合开始」时：政治行动点 +1`
  - `国内生产总值 ≥ 110`

## 10. 样板数据（可直接试玩）

- `data/config/`：`rules.json`、`economy.json`、`labels.json`、`reward_pools.json`。
- `data/cards/example_card.json`（含条件效果示例）
- `data/events/example_event.json`
- `data/cabinets/example_cabinet.json`
- `data/aids/example_aid.json`
- `data/budgets/example_budget.json`
- `data/groups/example_group.json`
- `data/scenarios/example_country.json`
- 样板经调参保持稳定，约第 2 财年可达成目标。

## 11. 文档

- `README.md`：玩法循环、目录结构、分层、运行方式、全部 JSON 数据格式、效果/修正/触发器参考、命令与事件接口、分组规则、扩展点、设计提示。
- 本 `CHANGELOG.md`：开发变更记录。

## 12. 已知扩展点 / 后续可做

- 经济模型的软限幅（`tanh`/夹取）尚未内置，需在方程中处理，避免强正反馈跑飞。
- 修正器的 `delay`（滞后生效）尚未实现。
- 内容量：目前仅一套样板，可继续按国家/组扩充卡牌、内阁、援助、事件、预算。
