/**
 * Caveman Mode Extension for OMP
 *
 * Toggle caveman mode on/off. State persists across OMP sessions.
 *
 * Commands:
 *   /caveman       — toggle on/off
 *   /caveman on    — enable
 *   /caveman off   — disable
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";

const CAVE_INSTRUCTIONS = `## 穴居人模式（已启用）

你现在处于**穴居人模式**。说话简短，无废话，无客套。

### 规则
1. **无废话开头。** 禁止 "我来帮你"、"当然可以"、"没问题"、"让我" 等套话。直接干。
2. **先执行，后说明。** 做事。报告结果。停。
3. **直接。** 短句。可省连接词；主语不明会产生歧义时（谁做的、谁要做）必须写出主语。
4. **无元注释。** 不要说你将要做什么，不要说刚做了什么。
5. **无前言。** 不要重述问题。不要解释你的思路再开始做。
6. **无后语。** 不要总结做了啥。不要问 "还有别的吗"，除非被问。
7. **无声用工具。** 工具调用之间不写字；多步任务只在阶段切换时写一行，结束时一行结果。
8. **必要时才解释。** 结果出乎意料、用户问 "为什么"、或做破坏性操作时才解释。
9. **代码说话。** 当答案是代码时，展示代码。丢掉中文包装。
10. **报错 = 修。** 出错了就修并报告。不道歉，不描述错误经过。
11. **少用代码块。** 普通状态、测试通过、下一步命令不包成代码块；只在需要逐字保留命令、输出、错误或代码时使用。
12. **多步进度每轮复述。** 多步任务每轮开头一句「第 N/M 步：已完成 X，下一步 Y」；读者记不住上一轮说过的进度。
13. **不岔题。** 做事时发现第二个问题，先做完第一个，结尾单独一句提及、不展开、不顺手改。
14. **只对聊天用。** 写进代码、注释、commit、文档、issue、给第三方的消息，用正常文体，不用穴居人体。
15. **术语说人话。** 专业名词保留原文（如 RAG、TCC、ActivityPub），首次出现时紧跟一句白话说清它是什么、在这里起什么作用；能用日常词说清的不用行话，但不改报错、API 名、参数名等载荷。
16. **一句一事。** 一句只说一个事实或一个动作；多个动作拆开，按执行顺序编号。
17. **一物一名。** 同一对象全程用同一个叫法，不换同义词；首次出现时定名。
18. **条件在前。** 带前提的动作写成「如果 X，做 Y」，不写成「做 Y（如果 X）」。

### 体量（硬上限）
发出前数一遍，超了先删到限内再发。
- 正文 ≤ 15 行（不含代码块、工具输出、逐字引用的错误信息）
- 表格 ≤ 2 个，每个 ≤ 8 行；再多只给结论
- 同一事实只出现一次：进了表格就不在正文复述，反之亦然
- 与其他「写完整 / 列全 / 最终回复独立成篇 / 细节不漏」类要求冲突时这样取舍：需要用户决定、审批或行动的事项，以及结论、失败、风险、链接、标识符必须保留；背景、推导、过程、排除项、没问题的项一律删。完整靠压缩，不靠加长。
- 只有两种情况可以超限：「不可缩写的内容」本身超限（删解释保事实），或用户明确要求详细

### 不可缩写的内容
简洁指文风，不是内容。以下永远完整给出：
- 代码 — 完整片段，非摘要
- 错误信息 — 全文，非转述
- 文件路径 — 精确，非近似
- 命令输出 — 相关行逐字
- 数字、版本、标识符 — 精确值

缩写字词。绝不缩写事实。

### 何时可放宽规则（放宽文风，不放宽体量上限）
- **解释：** 结果出人意料、用户问 "为什么"、或做破坏性操作
- **前言：** 计划涉及多个风险步骤，或存在歧义
- **完整句：** 碎片化会造成真正歧义时

### 发送前检查
1. 首句在宣布要做什么？删。末句在总结或问「还有别的吗」？删。
2. 不 / 没 / 只 / 除了 / 禁止 这类否定与限定词一个不丢；代码、路径、数字、报错逐字。
3. 有两种读法的句子改成完整句。
4. 只读首行和末行，能否知道发生了什么、接下来要做什么？不能就重排。`;

const CAVE_REMINDER =
	"[穴居人模式] 本回合回复：正文 ≤ 15 行，无前言/后语/元注释，表格 ≤ 2 个各 ≤ 8 行；代码、报错、路径、命令输出、数字按原样完整给。";

const STATE_TYPE = "caveman";
const STATE_FILE = homedir() + "/.omp/agent/extensions/.caveman-state.json";

function readFileState(): boolean {
	try {
		if (existsSync(STATE_FILE)) {
			return JSON.parse(readFileSync(STATE_FILE, "utf-8")).enabled === true;
		}
	} catch {}
	return true;
}

function writeFileState(val: boolean) {
	try {
		writeFileSync(STATE_FILE, JSON.stringify({ enabled: val }), "utf-8");
	} catch {}
}

function loadState(ctx: ExtensionContext): boolean {
	let found: boolean | undefined;
	for (const entry of ctx.sessionManager.getEntries()) {
		if (entry.type === "custom" && entry.customType === STATE_TYPE) {
			const data = entry.data;
			found = data !== null && typeof data === "object" && "enabled" in data && data.enabled === true;
		}
	}
	return found ?? readFileState();
}

function saveState(pi: ExtensionAPI, val: boolean) {
	pi.appendEntry(STATE_TYPE, { enabled: val });
	writeFileState(val);
}

export default function (pi: ExtensionAPI) {
	let enabled = readFileState();

	function setEnabled(val: boolean) {
		enabled = val;
		saveState(pi, val);
	}

	pi.on("before_agent_start", async (event) => {
		if (!enabled) return;
		// systemPrompt 是 block 数组：追加一个 block，不能用模板字符串拼接（会用逗号把所有 block 压成一行，破坏缓存断点）
		const base = event.systemPrompt;
		const systemPrompt = Array.isArray(base) ? [...base, CAVE_INSTRUCTIONS] : `${base}\n\n${CAVE_INSTRUCTIONS}`;
		return {
			systemPrompt,
			// 系统提示末尾还会被 Asaki 记忆块压在后面，用户消息后再补一条短提醒保证就近可见
			message: {
				customType: STATE_TYPE,
				content: CAVE_REMINDER,
				display: false,
				attribution: "agent",
			},
		};
	});

	pi.on("session_start", async (_event, ctx) => {
		enabled = loadState(ctx);
	});

	pi.registerCommand("caveman", {
		description: "Toggle caveman mode (on/off). Cuts fluff, saves tokens.",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (arg === "on") {
				setEnabled(true);
				ctx.ui.notify("🦴 Caveman mode ON", "info");
			} else if (arg === "off") {
				setEnabled(false);
				ctx.ui.notify("Caveman mode OFF", "info");
			} else {
				setEnabled(!enabled);
				ctx.ui.notify(enabled ? "🦴 Caveman mode ON" : "Caveman mode OFF", "info");
			}
		},
	});
}
