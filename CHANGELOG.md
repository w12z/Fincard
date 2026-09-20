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

## 12. 内容：阿卡迪亚联邦（大萧条原型）

在示例样板之外，新增一套完整内容 `arcadia`（以大萧条时期美国为原型的虚拟国家）：

- **卡牌 16 张**（救济组 4 / 复兴组 8 / 改革组 4）
- **内阁 6 名**：财政部长、联邦储备主席、劳工部长、农业部长、智囊团首席顾问、内政部长（含永久修正与每回合触发器）
- **事件 8 个**（多为双选项抉择）+ 繁荣期事件 4 个（见第 14 节）
- **预算案 4 份**：平衡预算案、稳健扩张案、赤字支出案、紧急救济案
- **援助 3 项**：动用黄金储备、外国贷款、炉边谈话
- **目标**（见第 14 节剧本改动后的版本）；失败线：通缩螺旋（通胀 < −15）、支持率/信心归零

平衡性调整（`data/config/economy.json`）：`unemployment_reversion` 0.2 → 0.02、`unemployment_okun` 0.1 → 0.3、`inflation_phillips` 0.05 → 0.03——原系数会让失业率自动快速回归、抹平大萧条；调整后政策选择才真正决定成败。

## 13. 剧本改动：从"崩盘前两年"开始

阿卡迪亚的时间线由"大崩盘后第四年"改为"**大崩盘前两年**"，崩溃以**定时事件**中段爆发、胜利判定后置。为此新增了三个框架功能：

- **定时事件** `scheduled_events`（`core/scenario_def.gd` + `Simulation._schedule_event`）：回合到达指定编号时必定触发的事件（绕过事件组过滤），其余回合照常随机抽取。阿卡迪亚的连锁：第 24 回合**黑色星期四**、第 26 回合**恐慌蔓延·银行倒闭潮**（救助/放任抉择）、第 28 回合**信贷冻结**。
- **目标判定门槛** `goal.after_turn`：胜利条件自该回合后才开始判定（失败条件始终生效），防止开局即满足目标、以及崩溃途中提前胜利。UI 目标面板显示"胜利判定：自第 X 回合起"。
- **一次性法案** `once_per_run`：打出后的卡牌移除所有同名副本、不再回牌库。修复了一个严重失控：带永久效果的卡（富人税 +5 税率、存款保险 +3 信心等）原本可循环重打，曾致通胀 +47 / 税率 175 / 债务 −517。11 张结构型法案卡已标记为一次性。

救济卡同步重构为"**持续性政策**"：以工代赈/救济金/保护队的就业与支持率效果以限时修正（3~4 回合）落地、随"拨款"停发而失效——必须持续投入才能压住失业，复现了新政"拨款一停、失业反弹"的现实动态；基础设施（GDP）与少数就业指标为永久项。

新开局指标（繁荣期）：GDP 128、通胀 +2、失业 5、债务 30、信心 70、支持率 55、利率 5、税率 25；初始牌组改为复兴/改革类为主。另补充 4 个繁荣期随机事件（股市投机狂热、分配失衡之问、农业的漫长萧条、战债之争），事件池共 12 个。

模拟验证：开局龙头 → 崩溃按时到来 → 赤字/救济路线约第 4 年通关（期限第 6 年）。

## 14. 卡牌类型、tags 移除与着色

- 卡牌新增 `card_type` 字段（`investment` 投资与援助 / `policy` 政策 / `reform` 改革，缺省 `investment`）；移除无任何读取方的 `tags` 字段。
- UI：手牌卡面第一行 `［类型］卡名`；四种文字状态（普通/悬停/按下/禁用）均按类型着色（深蓝 / 蓝绿 / 蓝紫，禁用态为同色淡化）；悬停 tooltip 第一行显示 `［类型］`；财年总结中的卡牌奖励选项同样着色并在悬停显示类型。

> 修正记录：此功能第一次实现时漏改了内核 `CardDef`，导致运行时手牌渲染中断（表现为"没类型且看似没抽到牌"），后来补上。

## 15. 效果分支结构

新增效果类型 `branch`，支持 if/else：条件成立跑 `then`，不成立跑 `else`（`else` 可省略）；可嵌套实现多分支。UI 文案自动生成，如 `若 通货膨胀 > 5：国内生产总值 +1；否则：民众支持率 +1`。

```json
{
  "kind": "branch",
  "params": {
    "condition": { "indicator": "inflation", "comparator": "gt", "value": 5 },
    "then": [ { "kind": "adjust_indicator", "params": { "target": "gdp", "amount": 1 } } ],
    "else": [ { "kind": "adjust_indicator", "params": { "target": "approval", "amount": 1 } } ]
  }
}
```

配套调整：
- `core/effect.gd` 增加 `BRANCH`；`core/effect_resolver.gd` 递归解析 `then` / `else`（分支内可以是任意效果，包括再一层 `branch`）。
- 银行假日卡改为分支示范：信心 < 45 时 +8，否则 +4（恐慌越重、果断行动收益越大）。
- 样板卡同时保留"单条件效果"与"分支效果"两种示范。

验证：THEN 分支（通胀 10>5）只加 GDP；ELSE 分支（通胀 2≤5）只加支持率；错误条件下的 conditional 正确跳过。

## 16. 经济模型重写：配比语义与回归锚

原经济方程把 GDP 当金币线性累加、通胀/债务对自身水平复利（无任何比例修正），"为了稳定"直接把强联动系数设 0——本质是量纲错误，全开必爆。重写为游戏化的计量模型：

- **全部流量按「占 GDP 的百分比」表达**：`ΔGDP = GDP × 增长率/100`（乘法）；`Δ债务 = GDP × (赤字 − 收入 + 利息负担)`，债务率越高利息负担越重（债务螺旋自然成立）。
- **百分比类变量（通胀/失业/信心/支持率）**：全部采用「向目标锚回归 + 有限缺口/驱动项」的形式，通胀锚定 `inflation_target`，失业锚定自然失业率，货币政策通过 `infl_rate` 同时拖增长、压通胀（加息→通胀链路已完整打开）。
- **`bounds` 硬边界**：失业 ≥ 0.5、利率 ≥ 0、情绪 0~100、增长 ±8%/回合等，在 tick 与效果调值处统一夹取（失业不再出现负数、利率不再无界飙升）。
- 所有被关闭的联动恢复开启：挤出效应、通胀惯性（以锚定形式）、债务利息、债务 → 信心/支持率、利率 → 通胀/增长。
- `adjust_indicator` 新增 `percent: true`（按 GDP 百分比调 `gdp`/`debt`）；阿卡迪亚全部内容与样板数据随之转换为百分比语义；内阁 GDP 修正改为乘法（如 `mul 1.005` = 每回合 +0.5%）。
- 可重复"加息"类政策改为限时修正（3~4 回合），防止可无界累加把利率推到上限。
- 系数名重命名（`gdp_auto/gdp_conf/gdp_rate_gap/…`），`data/config/economy.json` 全量替换。

模拟验证：示例国第 2 年稳定通关（债务率锚定 0.60）；阿卡迪亚繁荣期增长健康（128→134.7）、通胀被锚在 2% 附近、利率不再失控，崩溃后第 3 年恢复并通关，失业/通胀均落入合理区间。数据文件已全部通过严格 UTF-8 校验。

## 17. 已知扩展点 / 后续可做

- 经济模型的软限幅（`tanh`/夹取）尚未内置，需在方程中处理，避免强正反馈跑飞。
- 修正器的 `delay`（滞后生效）尚未实现。
- 内容量：目前仅一套样板，可继续按国家/组扩充卡牌、内阁、援助、事件、预算。

## 18. 移除「支持率」机制

- **内核**：删除 `approval` 演化方程与全部 `appr_*` 系数（`app/economy_builder.gd`、`data/config/economy.json`），移除 `approval` 的 `bounds` 与 `labels` 显示名。
- **剧本**：两套剧本（`example_country`、`arcadia`）不再定义 `approval` 指标；失败线中引用 `approval < 0` 的条件删除（`arcadia` 保留通缩与信心归零两条失败线）。
- **内容**：卡牌/事件/内阁/援助/预算中所有以 `approval` 为目标的增减效果**改指向 `confidence`**（共 25 个数据文件），保留原有内容强度与"民心"维度；`example_card` 的分支演示（else 分支）随之变为加信心，功能不受影响。
- 结果：情绪维度统一为单一的「市场信心 confidence」。

## 19. 经济模型再调整：预算与增长解耦、弱化并外部化锚回归、修正债务率口径

针对经济评审结论做的三项结构性调整：

- **预算不再直接驱动经济**：删除 `gdp_stim`/`infl_stim`/`conf_stim`/`debt_spend` 四个"预算规模"系数与所有 `× 预算规模` 项；移除 `state.budget_scale`、预算档位的 `scale` 字段、`rules.base_budget_scale`、`BudgetPlanDef.scale` 及预算选项信息中的 `scale`。经济变化改为**完全由卡牌/事件/内阁/援助的 `effects` 驱动**——预算只有被实际花出去打出卡牌才起作用，作用由该卡自身效果决定。债务的自动支出通道一并移除，改由税收收入、利息负担与显式卡牌效果决定。
- **弱化并外部化锚回归**：`infl_anchor` 0.3→0.1、`u_revert` 0.08→0.05、`conf_anchor` 0.2→0.1，市场自然回归明显变慢。新增**按剧本系数覆盖**机制：剧本 JSON 可用 `economy_overrides` 覆盖任意经济系数（`ScenarioDef` 解析，`EconomyModel.apply_coefficient_overrides` 在开局时重置为基准再套用覆盖；`EconomyBuilder` 的方程改为实时读取系数，使覆盖生效且可跨剧本复位）。示例国（市场/自由，0.15/0.07/0.12）与阿卡迪亚（干预主义，0.05/0.03/0.05）已作为示范（占位值）。
- **修正债务率双口径不一致**：`_debt_ratio()` 现按 `bounds` 夹取后返回，方程、派生指标、UI 与胜负条件统一使用夹取后的债务率，消除"动力学用原始值、判定用夹取值"的分叉。另给 `adjust_indicator` 的 `percent` 增加目标校验：非 `gdp`/`debt` 目标使用 `percent` 时按绝对值处理并告警。

验证：`godot --headless --editor --path . --quit` 与主场景运行无脚本错误；临时脚本实测系数覆盖按剧本正确生效并在切换剧本时复位（通用 0.1 → 示例 0.15 → 阿卡迪亚 0.05 → 再切回正确复位）。

## 20. 经济系数全面可修正（数值肉鸽化）

让"经济系数"与指标一样可被内容动态修改，服务于数值肉鸽的快速膨胀/爆炸：

- **修正器新增作用域 `scope`**（`core/modifier.gd`）：`indicator`（默认，改指标最终值）与 `coefficient`（改经济系数）。`EffectResolver` 的 `apply_modifier`/`remove_modifier` 增加可选 `scope` 参数。
- **`EconomyModel.coefficient(state, key)`**：系数 = 全局默认（`economy.json`）→ 剧本 `economy_overrides` → `scope: coefficient` 的修正器（ADD/MUL/OVERRIDE 依次叠加）。`EconomyBuilder` 所有方程改为实时调用该方法，因此**任何系数都可在运行时改变**，支持 `add`/`mul`/`override` 与限时/永久 `duration`。
- **四个层次的系数来源**：全局默认（`economy.json`）、剧本覆盖（`economy_overrides`）、**国家精神**（剧本 `innate_modifiers`）、运行时内容（内阁 `modifiers`、改革卡/事件/援助的 `effects`）。
- **剧本可覆盖指标硬边界**：`ScenarioDef` 解析 `bounds`，`EconomyModel` 增加 `base_bounds`/`reset_bounds()`/`apply_bounds_overrides()`；`[min,max]` 覆盖、`null` 移除边界，`start_run` 先复位再套用，跨剧本可正确复位（放开膨胀）。
- **UI 与文案**：`labels.json` 增加 `coefficients` 中文名分区；`TextFormatter` 增加 `coefficient()` 与作用域感知的修正文案（前缀「系数·」）；`GameUI` 修正列表按作用域显示。
- **示范**：`example_country` 增加国家精神「自由市场」（系数 `gdp_auto` +0.2，永久）；`arcadia_cab_braintrust` 增加系数修正（`gdp_conf` +0.05）。改革卡/事件/援助使用同一 `apply_modifier` + `scope: coefficient` 即可。

验证：临时脚本确认——基准 `gdp_auto` 0.3 → 示例国国家精神 0.5 → 切至阿卡迪亚复位 0.3；剧本覆盖 `infl_anchor` 0.05 生效；内阁系数修正 `gdp_conf` 0.15→0.2；`bounds` 覆盖 `growth [-30,30]` 与复位均正确。全部 69 个 JSON 通过校验，Godot 导入与运行无脚本错误。

## 21. 代码清理：删除死代码、消除重复

- **删除死代码**：`Event.Kind.EFFECT_RESOLVED`、`CABINET_GAINED`（从未发出）、`PHASE_CHANGED`（有发出但无消费者，`TurnStateMachine.enter` 改为不产生事件、仅切状态）；`TurnStateMachine.can_transition`/`ALLOWED`、`Reward.to_dict`、`Rng.next_float`、`Modifier.PERMANENT`、`DataLoader.load_single`（均无引用）。
- **C1/C3 事件名表收敛**：`Event` 增加 `name_of(kind)` 反向映射（`static var` 惰性构建），`TextFormatter._kind_name` 不再线性反查；`GameUI._describe` 的事件前缀统一改由 `labels.events` + `Event.name_of` 生成，消除日志里硬编码的中文与 `labels` 重复；`labels.json` 补 `run_started`。
- **B1 格式化去重**：删除 `GameUI._fmt/_signed`，统一用 `TextFormatter.fmt/signed`。
- **B2 名称查找去重**：`GameUI` 的 `_card_name/_cabinet_name/_aid_name/_budget_name/_scenario_name` 合并为通用 `_display_name(db, id)`。
- **B4 修正算子收敛**：`Modifier` 提供 `OP_NAMES`/`OP_LABELS`/`op_from()`/`op_label()`；`EffectResolver` 删除本地 `OP_NAMES`/`_op_from`，`TextFormatter` 按 `Modifier.Op` 枚举匹配，`GameUI` 用 `Modifier.op_label`。作用域感知的标签抽为 `TextFormatter.modifier_target`，`MODIFIER_EXPIRED` 事件补齐 `scope` 字段。

验证：Godot 导入与运行无脚本错误/警告；临时脚本驱动 `GameUI._describe` 覆盖各事件分支，文案正确（含「系数·潜在增长率」）。




