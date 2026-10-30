# Project Structure

审计、设计或迁移目录时完整读取本文件。

## 按需骨架

```text
<项目根目录>/
├── README.md
├── CLAUDE.md
├── ROADMAP.md
├── CHANGELOG.md
├── DESIGN.md                       # 存在正式报告时创建
├── sources/
│   ├── INDEX.md
│   ├── <source-file>               # 文件名表达类型与用途
│   └── <source-unit>/              # 存在独立边界时创建
├── outputs/
│   ├── INDEX.md
│   ├── <deliverable-file>          # 文件名表达产物类型与用途
│   ├── <delivery-unit>/            # 存在独立交付边界时创建
│   └── phaseN-<阶段名>/             # 多个材料构成阶段维护单元时创建
└── tools/                          # 存在项目工具时创建
```

`sources/`、`outputs/` 及其全局 `INDEX.md` 固定存在；其他层级按当前材料创建。

## YAGNI 边界

每个目录必须对应当前可验证的边界：

- 资源相对路径；
- 构建或执行入口；
- 权限边界；
- 多个文件构成的协作或交付单元；
- 外部稳定路径；
- 独立维护范围。

目录缺少上述边界时执行收敛：

- 唯一子目录上移到最近的必要父目录；
- 单个文件上移，并用语义化文件名表达类型与用途；
- 同一主题在不同分类下的同名目录上移到最近共同边界，或改用语义化文件名；
- `INDEX.md`、占位文件和空目录不计为支撑层级的真实内容。

未来扩展不构成当前边界。后续文件增加且出现真实结构成本时再建立目录；文件数量本身不触发升级。同名目录分别满足独立边界时可以保留，并在设计方案中说明边界。

## 正式交付形态

| 形态 | 判断 | 组织方式 |
|---|---|---|
| 单文件交付 | 一个文件可独立交付，无配套资源或构建依赖 | 直接放 `outputs/`，文件名表达产物类型与用途 |
| 并列多文件 | 文件各自独立，不构成共同维护单元 | 直接并列放 `outputs/` |
| 独立交付包 | 多个文件共同构成资源、构建、入口或维护单元 | 建立命名明确的子目录 |

多个文件共享类型不等于形成交付包。

## 分类与命名

| 内容 | 单文件默认路径 | 独立边界出现后 |
|---|---|---|
| 正式需求 brief、评审输入 | `sources/REQ-<date>-<topic>.md` | `sources/requests/` |
| 原始截图、HTML、PDF、API 导出、评论数据 | `sources/raw-<topic>.<ext>` | `sources/raw/` |
| 摘录、清洗、统计、审计、证据包 | `sources/derived-<topic>.<ext>` | `sources/derived/` |
| 采集参数、权限、失败和异常记录 | `sources/log-<topic>.<ext>` | `sources/logs/` |
| 正式报告 | `outputs/report-<topic>.<ext>` | `outputs/reports/` |
| 其他正式交付 | `outputs/<artifact-type>-<topic>.<ext>` | 命名明确的交付目录 |
| 单个阶段材料 | `outputs/phaseN-<name>-<material>.<ext>` | `outputs/phaseN-<name>/` |

临时提取、缓存、渲染和调试文件进入 Git 忽略范围或在任务结束后清理。

## 局部 INDEX 升级

`sources/INDEX.md` 与 `outputs/INDEX.md` 是固定全局入口。其他目录仅在当前满足任一条件时创建 `INDEX.md`：

1. 多个文件存在必要阅读顺序；
2. 文件用途无法从命名和上级索引判断；
3. 目录具有独立范围、验收条件或维护规则；
4. 上级索引无法快速导航。

局部 INDEX 记录关键入口，不维护精确文件数量，不抄录正文元数据。目录只有一个命名清晰的文件，或索引只重复上级链接时，使用上级索引直接导航。未来可能增加文件不触发 INDEX 升级。
