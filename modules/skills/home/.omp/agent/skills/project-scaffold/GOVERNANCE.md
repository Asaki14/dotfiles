# Project Governance

创建或修改治理文件时读取对应章节；裁定权威信息分工时先读第一节。

## 职责分工

| 文件 | 唯一职责 |
|---|---|
| `README.md` | 项目定位、当前入口和实际目录树 |
| `CLAUDE.md` | Agent 上下文、硬约束、维护规则和验证命令 |
| `ROADMAP.md` | 当前阶段、待办、依赖、风险和验收状态 |
| `CHANGELOG.md` | 已完成的重大决策、迁移、里程碑和用户可感知变化 |
| `DESIGN.md` | 全部正式报告共用的视觉规范 |
| `sources/INDEX.md` | 需求、原始证据、派生证据和采集日志总览 |
| `outputs/INDEX.md` | 正式交付、阶段材料和迁移映射总览 |

## `README.md`

```markdown
# <项目名>

<一句话说明为谁解决什么决策问题，并交付什么。>

## 当前入口

- 当前阶段：[`ROADMAP.md`](ROADMAP.md)
- Agent 规则：[`CLAUDE.md`](CLAUDE.md)
- 需求与证据：[`sources/INDEX.md`](sources/INDEX.md)
- 产出：[`outputs/INDEX.md`](outputs/INDEX.md)
- 重大变化：[`CHANGELOG.md`](CHANGELOG.md)
- 报告设计：[`DESIGN.md`](DESIGN.md) <!-- 存在正式报告时保留 -->

## 目录

<只展示实际存在的分类层级。>
```

## `CLAUDE.md`

至少说明项目定位与主要交付物、权威文件分工、项目硬约束、落盘规则和可执行验证命令。当前进度、待办和风险链接 `ROADMAP.md`。

## `ROADMAP.md`

```markdown
# ROADMAP

## 当前阶段

### P<N> <阶段名>

- 状态：<未开始 / 进行中 / 阻塞 / 已完成>
- 目标：
- 范围：
- 非目标：
- 输入：
- 正式交付：
- 依赖：
- 风险：
- 验收条件：

### 待办

- [ ] <可验证动作>

## 后续阶段

| 阶段 | 目标 | 依赖 | 状态 |
|---|---|---|---|
```

状态、待办和验收结果只在 `ROADMAP.md` 维护。

## `CHANGELOG.md`

```markdown
# CHANGELOG

## YYYY-MM-DD

### <重大变化标题>

- 决策或变化：
- 影响：
- 迁移：<如适用，链接 outputs/INDEX.md>
- 验证：
```

记录重大架构调整、路径迁移、范围裁定、里程碑和用户可感知变化；普通编辑由 Git 记录。

## `DESIGN.md`

正式报告直接触发 `DESIGN.md`；报告可以位于 `outputs/` 或具有独立边界的交付目录。

```markdown
# Report Design System

## Principles
- <视觉原则>

## Tokens
- Colors:
- Typography:
- Spacing:
- Radius:
- Shadow:

## Components
- Page:
- Section:
- Card:
- Table:
- Chart:
- Source note:

## Validation
- Design token command:
- Structure command:
- Render command:
```

全部正式报告引用同一规范。视觉变更先修改 `DESIGN.md`，再同步报告并执行 Validation 命令。

## `sources/INDEX.md`

```markdown
# sources/ 索引

## 边界

- requests / `REQ-`：正式需求和验收输入。
- raw / `raw-`：未经分析的外部资料和平台导出。
- derived / `derived-`：可复核的摘录、清洗、统计、审计和证据包。
- logs / `log-`：采集参数、权限、失败和异常记录。

## 需求入口

| 需求 | 路径 | 决策对象 | 日期 |
|---|---|---|---|

## 证据导航

| 主题或对象 | Raw | Derived | 用途与边界 |
|---|---|---|---|

## 采集日志

| 对象 | 路径 | 覆盖范围 |
|---|---|---|
```

凭证只记录访问方式和是否落盘，不记录明文。

## `outputs/INDEX.md`

```markdown
# outputs/ 索引

## 正式交付

| 产出 | 类型 | 路径 | 对应需求 | Roadmap |
|---|---|---|---|---|

## 阶段产物

| 阶段 | 材料入口 | 正式交付 | Roadmap |
|---|---|---|---|

## 迁移映射

| 原路径 | 当前路径 | 日期 | 说明 |
|---|---|---|---|
```

该索引只维护正式交付、阶段材料和迁移映射；规则链接权威治理文件，状态链接 `ROADMAP.md`。
