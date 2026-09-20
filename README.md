# Fincard

一款"玩家作为国家经济决策者、通过出牌影响经济"的类肉鸽卡牌游戏骨架。

- 引擎：**Godot 4**（开发验证版本 4.7.1）
- 语言：GDScript
- 目标平台：PC（轻量、重 UI、轻渲染）
- 设计原则：**经济模拟内核与引擎解耦**，纯逻辑、确定性、可单元测试、可回放

---

## 1. 核心玩法循环

```
选择开局情形（国家）
  └ 获得：初始牌组 + 初始经济状态 + 独特事件池 + 最终经济目标
        │
        ▼
   开局即第一财年的财年总结
        │  强制选预算档位 + 三选一奖励（与年末流程相同）
        │
        ▼
   每个回合（turns_per_year 次 = 一财年）
        │  TURN_START
        │    └ 政治行动点按「基础 + 增益」小额补充
        │    └ 随机事件（来自该国事件池）：可能要求玩家抉择
        │  DRAW  抽牌
        │  MAIN  出牌（同时消耗「财政预算」与「政治行动点」）
        │  TURN_END  经济结算 tick → 修正器倒计时 → 检查胜负
        │
        ▼
   财年总结（每满一财年）
        │  1) 强制确定下一年度预算档位
        │       → 财政预算按档位重设；政治行动点获得一次大额补充
        │       → 立即施加效果（影响市场信心、债务、通胀预期等）
        │  2) 三选一奖励（可选跳过）：
        │       · 新卡牌 / 任命内阁（遗物）/ 申请外部援助（药水）
        │
        ▼
   下一财年（难度/危机递进） …… 直到达成目标 或 触发失败
```

**双资源经济**：出牌同时消耗 `财政预算` 与 `政治行动点`。财政预算按财年重设；政治行动点在**财年总结时获得一次大额补充**，并在**每回合按「基础值 + 增益」小额补充**。预算档位在财年总结时决定——**开局即先进行一次财年总结**（视为第一财年），之后每年年末各一次。

**肉鸽性来源**：随机开局国情、随机事件、随机奖励、牌组构筑、内阁/援助的构筑维度、预算档位抉择、确定性种子（可复现、可做每日挑战）。

---

## 2. 目录结构

```
Fincard/
├─ project.godot              # Godot 工程配置，主场景 = presentation/main.tscn
├─ README.md
├─ core/                      # 纯逻辑内核（不依赖场景树，确定性）
│  ├─ rng.gd                  # 注入种子的确定性随机（LCG）
│  ├─ game_state.gd           # 全局状态：指标/修正/牌堆/内阁/援助/预算/年份/待决项
│  ├─ modifier.gd             # 数值修正器：ADD / MUL / OVERRIDE，可永久或限时
│  ├─ effect.gd               # 效果类型（卡牌/事件/内阁/援助/预算共用）
│  ├─ effect_resolver.gd      # 效果 → 状态变更 + 事件
│  ├─ economy_model.gd        # 指标/派生指标注册、快照同时结算、修正器栈求值
│  ├─ turn_state_machine.gd   # 回合阶段状态机
│  ├─ command.gd              # 玩家命令（输入）
│  ├─ event.gd                # 内核事件（输出，表现层订阅）
│  ├─ trigger.gd              # 触发器：监听某类事件 → 执行效果
│  ├─ trigger_engine.gd       # 触发器级联处理（带安全上限）
│  ├─ card_def.gd             # 卡牌定义（双成本）
│  ├─ scenario_def.gd         # 开局情形 / 国家定义
│  ├─ goal_def.gd             # 最终经济目标（胜利/失败条件）
│  ├─ condition.gd            # 指标条件：ge/le/gt/lt/eq
│  ├─ economy_event_def.gd    # 随机事件定义（可带选项）
│  ├─ event_choice.gd         # 事件选项
│  ├─ cabinet_def.gd          # 内阁（遗物）
│  ├─ aid_def.gd              # 外部援助（消耗品）
│  ├─ budget_plan_def.gd      # 年度预算档位
│  ├─ reward.gd               # 财年奖励选项
│  └─ simulation.gd           # 门面：编排整局流程
├─ app/                       # 应用层（文件 IO、装配）
│  ├─ config_loader.gd        # 读取单个 JSON
│  ├─ data_loader.gd          # 扫描目录、批量构建定义
│  ├─ economy_builder.gd      # 按系数配置注册经济方程与派生指标
│  └─ game_controller.gd      # Node：加载数据 + 持有 Simulation + 派发命令
├─ presentation/              # 表现层（UI）
│  ├─ main.tscn / main.gd     # 启动场景，负责菜单 ↔ 游戏界面切换
│  ├─ scenario_menu.gd        # 开局选择界面
│  └─ game_ui.gd              # 游戏主界面（指标/手牌/日志/事件/预算/奖励弹窗）
└─ data/                      # 数据（含可直接运行的样板，数值可自由替换）
   ├─ config/
   │  ├─ rules.json           # 回合与奖励规则
   │  ├─ economy.json         # 经济联动系数
   │  ├─ labels.json          # 指标/资源/事件的中文显示名
   │  └─ reward_pools.json    # 财年奖励池（可选）
   ├─ cards/                  # 卡牌 JSON
   ├─ scenarios/              # 国家 JSON
   ├─ events/                 # 随机事件 JSON
   ├─ cabinets/               # 内阁 JSON
   ├─ aids/                   # 援助 JSON
   ├─ budgets/                # 年度预算档位 JSON
   └─ groups/                 # 组 JSON（按 id 列出成员）
```

分层依赖方向：`presentation → app → core`，`core` 不反向依赖上层，也不依赖场景树。

---

## 3. 运行方式

1. 用 Godot 4 打开本目录（导入 `project.godot`）。
2. 在 `data/` 下按第 4 节格式添加数据文件。
3. 运行主场景（F6/F5）。启动后进入开局选择界面，选择国家即可开始。

> 仓库内置两套可运行内容：**示例国**（`example_*`，演示 schema 的最小样板）与 **阿卡迪亚联邦**（`arcadia*`，以大萧条时期美国为原型的完整内容：3 个卡牌组共 16 张卡、6 名内阁、8 个事件、4 份预算案、3 项援助）。启动后在开局界面选择即可试玩。所有数值均可自由替换；若清空数据目录，菜单会提示"未找到开局数据"。

命令行验证（可选）：

```powershell
godot --headless --editor --path . --quit   # 导入并检查脚本错误
godot --headless --path . --quit            # 启动主场景
```

---

## 4. 数据格式

所有数值留空，由你填写。文件放入对应目录后自动加载；缺失的文件/目录会被安全跳过。

### 4.1 `data/config/rules.json`

```json
{
  "draw_per_turn": 0,
  "turns_per_year": 0,
  "reward_option_count": 0,
  "trigger_iteration_limit": 0,
  "political_capital_per_turn": 0,
  "base_budget": 0,
  "base_political_capital": 0,
  "base_budget_scale": 0
}
```

- `draw_per_turn`：每回合抽牌数。
- `turns_per_year`：一年分几个回合。
- `reward_option_count`：财年总结时每组奖励给出几个候选。
- `trigger_iteration_limit`：触发器级联的安全上限，`0` 表示使用内置兜底值。
- `political_capital_per_turn`：每回合政治行动点的基础小额补充（实际补充 = 此值 + `political_capital_gain` 的修正值）。
- `base_*`：无预算档位时的兜底（也用于第一财年，若国家未定义初始值）。

### 4.2 `data/config/economy.json`（经济联动系数与指标边界）

方程采用**配比语义**：GDP/债务为存量，所有流量以**占 GDP 的百分比**表达；通胀/失业/利率等百分点变量靠**回归锚**稳定（如失业向自然失业率回归、通胀向目标回归），并配硬上下限防止任何一环把系统拖飞。

```json
{
  "coefficients": {
    "natural_unemployment": 6,
    "neutral_rate": 3,
    "neutral_tax": 20,
    "debt_threshold": 0.9,
    "confidence_neutral": 50,
    "inflation_target": 2,

    "gdp_auto": 0.3,
    "gdp_conf": 0.15,
    "gdp_rate_gap": 0.02,
    "gdp_tax_gap": 0.03,
    "gdp_crowd": 1.0,
    "gdp_stim": 0.4,

    "infl_anchor": 0.3,
    "infl_phillips": 0.15,
    "infl_demand": 0.1,
    "infl_stim": 0.03,
    "infl_rate": 0.1,

    "u_okun": 0.25,
    "u_revert": 0.08,

    "debt_spend": 0.002,
    "debt_rev": 0.05,
    "debt_int_pass": 0.25,

    "conf_growth": 0.5,
    "conf_infl": 0.2,
    "conf_debt": 4.0,
    "conf_stim": 0.1,
    "conf_anchor": 0.2
  },
  "bounds": {
    "inflation": [-20, 40],
    "unemployment": [0.5, 60],
    "interest_rate": [0, 25],
    "tax_rate": [0, 70],
    "confidence": [0, 100],
    "debt_ratio": [0, 5],
    "growth": [-8, 8]
  }
}
```

联动的表达式语义：

- **GDP 增长率**（`growth`，每回合百分比）：潜在增长 `gdp_auto` + 信心敏感 `gdp_conf × (信心−50)/100` − 利率缺口敏感 `gdp_rate_gap × (利率−中性利率)` − 税率缺口敏感 `gdp_tax_gap × (税率−中性税率)` − 债务挤出 `gdp_crowd × max(0, 债务率−阈值)` + 财政刺激 `gdp_stim × 预算规模`。然后 **`ΔGDP = GDP ×增长率/100`**（乘法，不再是"金币式"线性加法）。
- **通胀**（百分点）：锚定目标 `infl_anchor×(目标−通胀)` + 菲利普斯 → 需求拉动 → 财政刺激 − 利率反应（即可用的货币政策沟道：加息既拖增长又压通胀）。
- **失业率**（百分点）：`u_revert × (自然失业−失业)` − `u_okun × 增长率`。
- **债务**（存量）：`Δ债务 = GDP × (赤字 − 收入 + 利息负担)`，其中赤字 `debt_spend×规模`、收入 `debt_rev×税率/100`、利息 `debt_int_pass×债务率×利率/100`——全部按 GDP 比例表达，债务率越大利息负担越重（债务螺旋通道）。
- **信心**（0-100 点）：对增长、通胀、债务率、财政刺激响应，且向中性值回归。
- `bounds`：指标的硬上下限，tick 与任何效果调值都会被夹取（如失业非负、利率非负、情绪 0~100）。

只有国家在 `indicators` 中定义了某个 id，该指标才会被 tick 演化。派生指标自动生成：`growth`（每回合 GDP 增长率 %）、`debt_ratio`（债务/GDP）。

### 4.3 `data/config/reward_pools.json`（可选）

不填则默认使用全部已加载的卡牌/内阁/援助/预算作为奖励与预算池。

```json
{ "cards": ["card_id"], "cabinets": ["id"], "aids": ["id"], "budgets": ["id"] }
```

### 4.4 卡牌 `data/cards/*.json`

```json
{
  "id": "card_id",
  "display_name": "标题（显示给玩家）",
  "description": "文本描述（显示给玩家）",
  "card_type": "investment",
  "cost": 0,
  "political_cost": 0,
  "effects": [
    { "kind": "adjust_indicator", "params": { "target": "unemployment", "amount": -1 } },
    { "kind": "adjust_indicator", "params": { "target": "gdp", "amount": 3, "percent": true } },
    { "kind": "apply_modifier", "params": { "target": "inflation", "op": "mul", "value": 1.0, "duration": 3 } },
    {
      "kind": "adjust_indicator",
      "params": { "target": "inflation", "amount": -1 },
      "condition": { "indicator": "inflation", "comparator": "gt", "value": 5 }
    }
  ]
}
```

- `cost` = 财政预算消耗，`political_cost` = 政治行动点消耗。
- `card_type`（可选）：`investment` 投资与援助 / `policy` 政策 / `reform` 改革，缺省 `investment`；UI 按此中文名与分类色显示。
- `once_per_run`（可选，`true`）：法案型卡牌，整局只能打出一次——打出后移除所有同名副本，不再回到牌库。**带永久性效果（`duration: -1` 或结构性法案）的卡牌建议都设为一次性**，可重复打出的持久改值会失控。
- 可重复的政策卡如需"改利率/通胀"等，建议用**限时修正（`duration` 3~4 回合）**而不是永久改值，否则可无上限累加。
- `display_name` = 标题，`description` = 文本描述；**具体作用由 `effects` 自动生成中文说明**（含具体数值），无需手写。
- 效果可带可选 `condition`（指标条件）；UI 会显示为"若 通货膨胀 > 5，通货膨胀 -1"。`comparator` 取 `ge/le/gt/lt/eq`。
- `adjust_indicator` 的 `percent: true` 表示数量按**占 GDP 的百分比**结算（用于 `gdp`、`debt` 这类存量目标）；对百分比类指标（通胀/失业/税率/信心等）不要加 `percent`。

### 4.5 年度预算档位 `data/budgets/*.json`

```json
{
  "id": "budget_id",
  "display_name": "档位名",
  "description": "说明",
  "budget": 0,
  "political_capital": 0,
  "scale": 0,
  "effects": [
    { "kind": "adjust_indicator", "params": { "target": "confidence", "amount": 0 } }
  ]
}
```

- `budget`：下一年度的财政预算（按档位重设）。
- `political_capital`：下一年度政治行动点的**大额补充**（累加）。
- `scale`：预算规模（进入经济方程，用于债务/增长/通胀/信心的联动）。
- `effects`：选定后立即施加（即"影响外界展望"）。

### 4.6 开局情形 / 国家 `data/scenarios/*.json`

```json
{
  "id": "scenario_id",
  "display_name": "国家名",
  "description": "简介",
  "starting_deck": ["card_id"],
  "indicators": { "gdp": 0, "inflation": 0, "debt": 0, "confidence": 0 },
  "event_pool": ["event_id"],
  "innate_modifiers": [
    { "kind": "apply_modifier", "params": { "target": "gdp", "op": "add", "value": 0, "duration": -1 } }
  ],
  "budget_pool": ["budget_id"],
  "groups": ["group_id"],
  "scheduled_events": [
    { "turn": 24, "event": "event_id" }
  ],
  "goal": {
    "description": "目标描述",
    "deadline_years": 0,
    "after_turn": 0,
    "conditions": [
      { "indicator": "debt_ratio", "comparator": "le", "value": 0 },
      { "indicator": "gdp", "comparator": "ge", "value": 0 }
    ],
    "loss_conditions": [
      { "indicator": "inflation", "comparator": "gt", "value": 0 }
    ]
  }
}
```

- `conditions` 全部满足 → 胜利；`loss_conditions` 任一满足 → 失败。
- `deadline_years`：超过该财年仍未达成 → 失败（`0` 表示不限时）。
- `after_turn`（可选）：胜利条件自该回合**之后**才开始判定（`0` = 立即生效）。用于"先经历 scripted 剧情再判定胜利"的剧本（失败条件始终生效）。
- `scheduled_events`（可选）：定时事件表，**到指定回合必定触发**（回合从 1 计），适合表现"历史剧本"（如大崩盘按 Suk 定时间爆发）。定时事件绕过事件组过滤，直接生效；随机事件池照常在非脚本回合抽取。
- 条件可引用派生指标（如 `growth`、`debt_ratio`）。

### 4.7 随机事件 `data/events/*.json`

有 `choices` 时玩家必须抉择；否则 `effects` 自动结算。

```json
{
  "id": "event_id",
  "title": "事件标题",
  "description": "事件描述",
  "choices": [
    { "label": "选项 A", "description": "说明", "effects": [ { "kind": "adjust_indicator", "params": { "target": "gdp", "amount": 0 } } ] }
  ]
}
```

### 4.8 内阁 `data/cabinets/*.json`

任命时应用 `modifiers`（建议 `duration: -1` 永久），`triggers` 为被动监听。

```json
{
  "id": "cabinet_id",
  "display_name": "内阁名",
  "description": "描述",
  "modifiers": [
    { "kind": "apply_modifier", "params": { "target": "gdp", "op": "add", "value": 0, "duration": -1 } }
  ],
  "triggers": [
    { "on": "turn_ended", "effects": [ { "kind": "adjust_indicator", "params": { "target": "confidence", "amount": 0 } } ] }
  ]
}
```

### 4.9 外部援助 `data/aids/*.json`

```json
{
  "id": "aid_id",
  "display_name": "援助名",
  "description": "描述",
  "uses": 0,
  "effects": [ { "kind": "adjust_indicator", "params": { "target": "debt", "amount": 0 } } ]
}
```

### 4.10 显示名称 `data/config/labels.json`

把代码里的 id 映射为玩家看到的中文名。UI 与日志全部走这张表；未配置的 id 会原样显示。

```json
{
  "indicators": { "gdp": "国内生产总值", "inflation": "通货膨胀", "debt_ratio": "债务率" },
  "resources": { "budget": "财政预算", "political_capital": "政治行动点" },
  "events": { "turn_started": "回合开始", "turn_ended": "回合结束" }
}
```

- `indicators`：所有指标 id（含派生指标如 `growth`、`debt_ratio`）。
- `resources`：资源 id。
- `events`：内阁触发器 `on` 用的事件名。

### 4.11 组 `data/groups/*.json` 与按国限定

**每个组只属于一种类型**，独立成一个文件，用 `members` 列出该类型的成员 id（成员需已在对应目录中存在）：

```json
{
  "id": "example_card_group",
  "type": "cards",
  "display_name": "示例卡牌组",
  "members": ["card_id", "card_id2"]
}
```

`type` 取 `cards` / `cabinets` / `aids` / `budgets` / `events`。各类各建各的组，例如 `data/groups/fiscal_cards.json`（type=cards）、`data/groups/standard_budgets.json`（type=budgets）。

国家用 `groups` 声明本局允许使用哪些组。两种写法：

```json
"groups": {
  "cards": ["example_card_group"],
  "cabinets": ["example_cabinet_group"],
  "aids": ["example_aid_group"],
  "budgets": ["example_budget_group"],
  "events": ["example_event_group"]
}
```

```json
"groups": ["example_card_group", "example_budget_group"]
```

（平铺写法：组按自身 `type` 归入对应类型。）

规则：

- 某类型一旦配置了非空组列表，则该类型只有**属于这些组（且组类型匹配）**的条目可用。
- 未配置 `groups`（或某类型列表为空）时，该类型不做限制（全部可用）。
- 生效范围：财年奖励（卡牌/内阁/援助）、预算档位、每回合随机事件（`event_pool` 非空时在其基础上按组过滤；为空时从全部事件里按组抽取）。
- 定义文件（卡牌/内阁等）不需要 `group` 字段；成员关系全部写在组文件里。UI 悬停详情会显示条目"所属组"。

---

## 5. 效果 / 修正 / 触发器参考

### 效果 `kind`（卡牌、事件、内阁、援助、预算通用）

| kind | params |
| --- | --- |
| `adjust_indicator` | `target`, `amount` |
| `apply_modifier` | `target`, `op`(`add`/`mul`/`override`), `value`, `duration`(正数=回合数，`-1`=永久) |
| `remove_modifier` | `target`, `source` |
| `draw_cards` | `count` |
| `gain_budget` | `amount` |
| `gain_political_capital` | `amount` |
| `branch` | `condition`, `then`(效果数组), `else`(效果数组，可省略) |

任何效果都可附加可选 `condition` 字段（结构同目标条件），条件不满足时该效果不生效：

```json
{ "kind": "adjust_indicator", "params": { "target": "inflation", "amount": -1 },
  "condition": { "indicator": "inflation", "comparator": "gt", "value": 5 } }
```

**分支效果**：`branch` 在条件成立与不成立时分别执行 `then` / `else` 两组效果，可嵌套（在 `then`/`else` 里再放 `branch`）以实现多路分支。单一条件的普通 conditional 效果是它的简写形式。

```json
{
  "kind": "branch",
  "params": {
    "condition": { "indicator": "inflation", "comparator": "gt", "value": 5 },
    "then": [ { "kind": "adjust_indicator", "params": { "target": "gdp", "amount": 1 } } ],
    "else": [ { "kind": "adjust_indicator", "params": { "target": "confidence", "amount": 1 } } ]
  }
}
```

UI 中显示为：`若 通货膨胀 > 5：国内生产总值 +1；否则：市场信心 +1`。

### 修正器求值

指标"最终值" = 基础值依次叠加所有修正器：

```
add  → 值 += value
mul  → 值 *= value
override → 值 = value
```

`EconomyModel.value(state, id)` 返回最终值；`state.indicators[id]` 为基础值。

**每回合政治行动点补充** = `rules.political_capital_per_turn` + `economy.value(state, "political_capital_gain")`。卡牌/内阁可对 `political_capital_gain` 施加修正器来提升每回合补充（该 id 无需在国家的 `indicators` 中定义，仅靠修正器即可生效）。

### 经济结算顺序（`EconomyModel.tick`）

1. 快照上回合指标到 `state.prev_indicators`。
2. 用快照**同时**计算所有指标的增量（互不污染）。
3. 应用增量。
4. 计算派生指标（`growth`、`debt_ratio`）并写入 `state.indicators`。

### 触发器 `on` 可用事件名

`turn_started`、`turn_ended`、`card_played`、`card_gained`、`cards_drawn`、`indicator_changed`、`modifier_applied`、`modifier_expired`、`resource_changed`、`year_started`、`year_ended`、`event_triggered`、`event_resolved`、`cabinet_appointed`、`aid_used`、`aid_gained`、`budget_offered`、`budget_chosen`、`reward_offered`、`reward_chosen`、`run_won`、`run_lost`、`custom`。

> 完整枚举见 `core/event.gd`。触发器对事件级联响应，由 `trigger_iteration_limit` 防止死循环。

---

## 6. 命令与事件（程序接口）

玩家操作通过 `Command` 进入内核，内核返回 `Event[]` 供表现层消费。

命令（`core/command.gd`）：

```gdscript
Command.play_card(card_id)
Command.end_turn()
Command.resolve_event(choice_index)   # 无选项事件传 -1
Command.use_aid(aid_id)
Command.choose_budget(plan_id)        # 财年预算档位（强制）
Command.choose_reward([index_per_group])
```

典型调用：

```gdscript
var events := controller.dispatch(Command.play_card(&"tax"))
for event in events:
    # 根据 event.kind / event.params 播放动画、更新 UI
    pass
```

界面所需的待决信息直接读取 `controller.simulation.state`：

- `pending_event` / `pending_event_choices`：待处理事件
- `pending_budget_plans`：待选预算档位（id 列表）
- `pending_rewards`：待选财年奖励（每组含 `type` 与 `options`）
- `run_status`：`RUNNING` / `WON` / `LOST`
- `budget` / `political_capital`：当前年度资源池
- `budget_plan` / `budget_scale`：本年度预算档位与规模
- `year` / `turn_in_year` / `hand` / `indicators` / `prev_indicators` / `modifiers` / `cabinets` / `aids`

**显示与描述**：`presentation/text_formatter.gd` 负责把 id 与效果翻译成中文：

- `indicator/resource/event_name(labels, id)`：按 `labels.json` 取中文名。
- `effect_text(labels, effect)`：把效果渲染成带具体数值的中文，如"2 回合内 税率 +2"、"若 通货膨胀 > 5，通货膨胀 -1"。
- `condition_text(labels, condition)`：条件渲染，如"国内生产总值 ≥ 110"。
- `trigger_text(labels, trigger)`：如"当「回合开始」时：政治行动点 +1"。

UI 采用"**标题 + 文本描述 + 具体作用**"的结构：卡牌/事件/内阁/援助/预算都显示标题与描述，并自动列出由 `effects` 生成的具体作用，无需在数据里手写数值文案。

---

## 7. 扩展点

- **经济方程与系数**：在 `app/economy_builder.gd` 调整/新增方程；系数放 `data/config/economy.json`。方程签名为 `Callable(state, economy, rng) -> float`（返回本回合增量），派生指标签名为 `Callable(state, economy) -> float`，用 `EconomyModel.register_derived(id, callable)` 注册。若某指标无方程，tick 会跳过它（保持常量）。
- **新效果类型**：在 `core/effect.gd` 的 `Kind` 与 `KIND_NAMES` 增加，并在 `core/effect_resolver.gd` 的 `resolve` 中处理。
- **新事件种类**：在 `core/event.gd` 增加枚举与名称，表现层 `_describe` 增加文案。
- **多国内容**：只需新增 `data/scenarios/*.json` 及其引用的卡牌/事件/内阁/援助/预算，系统无需改动。
- **表现层**：`presentation/game_ui.gd` 是纯程序化构建的 UI，可按需替换为 `.tscn` 或美术资源；内核与 UI 完全解耦。

---

## 8. 设计提示

- **GDP 用水平值，增长率用派生指标**：这样 `债务/GDP`、`预算/GDP` 等比率才有意义。
- **债务是存量、按流量变化**：`Δ债务 = 支出 − 收入 + 利息`，由此产生债务螺旋与挤出效应。
- **随机应是"输入随机"**（决策前给出题目：抽牌、事件、奖励、预算），而非"输出随机"（决策后判定成败）。
- **指标要少而互相拉扯**（建议 5~7 个），每个决策都有代价。
- **务必做软限幅**：经济模型是强正反馈系统，容易指数跑飞。对增量做 `tanh`/夹取，或给指标设上下限（当前框架未内置，需你在方程中处理）。
- **确定性种子**：同种子同结果，便于调试、回放与每日挑战。
