/**
 * Turn Notify Extension for OMP
 *
 * Posts a macOS notification when a captain-facing session needs attention:
 *   - the agent calls `ask` (a decision is waiting)
 *   - a run really ends with assistant text (the reply is finished)
 * Skipped for background workers (FM_TASK_ID set), sessions without UI (subagents,
 * print mode), and while the host terminal app is frontmost.
 * OMP_TURN_NOTIFY_CMD replaces osascript with a command that receives (title, body).
 */

import { execFile } from "node:child_process";
import { basename, resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const NOOP_REPLY = "Captain, shipshape.";
const BODY_LIMIT = 180;
const TERMINAL_BUNDLES: Record<string, string> = {
	tern: "so.stencil.tern",
	ghostty: "com.mitchellh.ghostty",
	Apple_Terminal: "com.apple.Terminal",
	"iTerm.app": "com.googlecode.iterm2",
};

export async function sessionLabel(cwd: string): Promise<string> {
	return basename(resolve(cwd));
}

/** First line that carries words, with markdown markers stripped and length capped. */
export function firstMeaningfulLine(text: string): string | undefined {
	for (const raw of text.split("\n")) {
		const line = raw
			.trim()
			.replace(/^(?:#+|[-*+>]|\d+\.)\s+/, "")
			.replace(/\*\*|__|`/g, "")
			.trim();
		if (!line || /^[-=|:*_~\s]+$/.test(line)) continue;
		return line.length > BODY_LIMIT ? `${line.slice(0, BODY_LIMIT - 1)}…` : line;
	}
	return undefined;
}

type TextBlock = { type: "text"; text: string };
type AssistantLike = { role: "assistant"; stopReason?: string; content?: string | unknown[] };

/** Notification body for a settled run, or undefined when the run should stay silent. */
export function finishedBody(messages: readonly unknown[]): string | undefined {
	const assistant = messages.findLast(
		(message): message is AssistantLike =>
			typeof message === "object" && message !== null && "role" in message && message.role === "assistant",
	);
	// aborted = interrupted by the captain; error = provider failure that auto-retry may still recover
	if (!assistant || assistant.stopReason === "aborted" || assistant.stopReason === "error") return undefined;
	const content = assistant.content ?? "";
	const text = (
		typeof content === "string"
			? content
			: content
					.filter(
						(block): block is TextBlock =>
							typeof block === "object" && block !== null && "type" in block && block.type === "text",
					)
					.map((block) => block.text)
					.join("\n")
	).trim();
	if (!text || text === NOOP_REPLY) return undefined;
	return firstMeaningfulLine(text);
}

/** Fire and forget: label the session, skip if the host terminal is frontmost, then post. */
function notify(cwd: string, status: string, body: string) {
	const ignore = () => {};
	const post = (label: string) => {
		const title = `${label} · ${status}`;
		const override = process.env.OMP_TURN_NOTIFY_CMD;
		if (override) {
			execFile(override, [title, body], { timeout: 5000 }, ignore);
			return;
		}
		// argv keeps title/body out of the AppleScript source, so no escaping is needed
		execFile(
			"osascript",
			[
				"-e",
				"on run argv",
				"-e",
				"display notification (item 2 of argv) with title (item 1 of argv)",
				"-e",
				"end run",
				title,
				body,
			],
			{ timeout: 5000 },
			ignore,
		);
	};
	const host = process.env.__CFBundleIdentifier || TERMINAL_BUNDLES[process.env.TERM_PROGRAM ?? ""];
	sessionLabel(cwd)
		.then((label) => {
			// Unknown host or failed detection: notify rather than risk a silent miss.
			if (!host) return post(label);
			execFile(
				"/bin/sh",
				["-c", 'lsappinfo info -only bundleID "$(lsappinfo front)"'],
				{ timeout: 2000 },
				(error, stdout) => {
					if (error || !stdout.includes(`"${host}"`)) post(label);
				},
			);
		})
		.catch(ignore);
}

export default function (pi: ExtensionAPI) {
	if (process.env.FM_TASK_ID) return;

	let running = false;

	pi.on("agent_start", () => {
		running = true;
	});

	pi.on("tool_execution_start", (event, ctx) => {
		if (event.toolName !== "ask" || ctx.hasUI !== true) return;
		const questions: unknown[] = Array.isArray(event.args?.questions) ? event.args.questions : [];
		const first = questions.find(
			(entry): entry is { question: string } =>
				typeof entry === "object" && entry !== null && "question" in entry && typeof entry.question === "string",
		);
		notify(ctx.cwd, "decision needed", firstMeaningfulLine(first?.question ?? "") ?? "Waiting for your answer");
	});

	pi.on("agent_end", (event, ctx) => {
		// OMP can emit duplicate or late end events; only the first end after a start counts.
		if (!running || event.willContinue === true) return;
		running = false;
		if (ctx.hasUI !== true) return;
		const body = Array.isArray(event.messages) ? finishedBody(event.messages) : undefined;
		if (body) notify(ctx.cwd, "finished", body);
	});
}
