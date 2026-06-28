// scripts/fable/memory-pipeline.ts
// ============================================================
// Fable Toolkit 件 4：Memory Pipeline（規則蒸餾）
// ------------------------------------------------------------
// 從失敗 propose 規則 draft → 累積 N 次升格到 user memory。
//
// 跑法：
//   tsx scripts/fable/memory-pipeline.ts propose --name slug --desc "..." --rule "..." --why "..."
//   tsx scripts/fable/memory-pipeline.ts propose --from-smoke /tmp/smoke.log    # 掃 smoke 失敗自動 draft
//   tsx scripts/fable/memory-pipeline.ts list                                    # 列 draft + trigger count
//   tsx scripts/fable/memory-pipeline.ts promote <slug>                          # 升格到 user memory
//
// 鐵律 #0：draft 寧缺勿濫；同類失敗才 +trigger_count，不亂塞。
// ============================================================

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const DRAFT_DIR = path.resolve(process.cwd(), ".claude/memory/drafts");
const PROMOTION_THRESHOLD = 3;
// user 層 memory（auto-memory）目錄
// 專案 slug 由 cwd 自動推導：Claude Code 把專案路徑的 : \ / 都換成 -
// 例："E:\greed-island-app" → "E--greed-island-app"
// 可被 .claude/toolkit-config.yaml > memory.promote_to_user_memory 覆寫
function deriveProjectSlug(): string {
  return process.cwd().replace(/[:\\/]/g, "-");
}
function resolveUserMemoryDir(): string {
  const cfgPath = path.resolve(process.cwd(), ".claude/toolkit-config.yaml");
  if (fs.existsSync(cfgPath)) {
    const src = fs.readFileSync(cfgPath, "utf-8");
    const m = src.match(/promote_to_user_memory:\s*(.+)/);
    if (m) {
      const raw = m[1].trim().replace(/^['"]|['"]$/g, "");
      return raw.replace(/^~/, os.homedir());
    }
  }
  return path.join(os.homedir(), ".claude", "projects", deriveProjectSlug(), "memory");
}
const USER_MEMORY_DIR = resolveUserMemoryDir();

interface DraftMeta {
  name: string;
  description: string;
  type: "feedback" | "project" | "reference";
  trigger_count: number;
  first_seen: string;
  related_commits: string[];
}

function ensureDirs() {
  fs.mkdirSync(DRAFT_DIR, { recursive: true });
}

function parseArg(flag: string): string | undefined {
  const i = process.argv.indexOf(flag);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function draftPath(slug: string): string {
  return path.join(DRAFT_DIR, `${slug}.md`);
}

function readDraft(slug: string): { meta: DraftMeta; body: string } | null {
  const p = draftPath(slug);
  if (!fs.existsSync(p)) return null;
  const src = fs.readFileSync(p, "utf-8");
  const m = src.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) return null;
  const fm = m[1];
  const body = m[2];
  const meta: DraftMeta = {
    name: (fm.match(/name:\s*(.+)/)?.[1] ?? slug).trim(),
    description: (fm.match(/description:\s*(.+)/)?.[1] ?? "").trim(),
    type: (fm.match(/type:\s*(.+)/)?.[1]?.trim() as DraftMeta["type"]) ?? "project",
    trigger_count: parseInt(fm.match(/trigger_count:\s*(\d+)/)?.[1] ?? "1", 10),
    first_seen: (fm.match(/first_seen:\s*(.+)/)?.[1] ?? "").trim(),
    related_commits: (fm.match(/related_commits:\s*\[(.*?)\]/)?.[1] ?? "")
      .split(",").map((s) => s.trim()).filter(Boolean),
  };
  return { meta, body };
}

function writeDraft(meta: DraftMeta, body: string) {
  const content = `---
name: ${meta.name}
description: ${meta.description}
type: ${meta.type}
trigger_count: ${meta.trigger_count}
first_seen: ${meta.first_seen}
related_commits: [${meta.related_commits.join(", ")}]
---

${body.trim()}
`;
  fs.writeFileSync(draftPath(meta.name), content);
}

function currentCommit(): string {
  try {
    const { execSync } = require("node:child_process");
    return execSync("git rev-parse --short HEAD", { encoding: "utf-8" }).trim();
  } catch {
    return "unknown";
  }
}

// ── propose ──
function propose() {
  ensureDirs();
  const fromSmoke = parseArg("--from-smoke");
  if (fromSmoke) {
    proposeFromSmoke(fromSmoke);
    return;
  }
  const name = parseArg("--name");
  const desc = parseArg("--desc");
  const rule = parseArg("--rule");
  const why = parseArg("--why");
  const how = parseArg("--how") ?? "";
  const type = (parseArg("--type") as DraftMeta["type"]) ?? "project";
  if (!name || !desc || !rule) {
    console.error("用法: propose --name slug --desc \"...\" --rule \"...\" [--why \"...\"] [--how \"...\"] [--type project|feedback|reference]");
    process.exit(1);
  }

  const existing = readDraft(name);
  if (existing) {
    existing.meta.trigger_count++;
    const commit = currentCommit();
    if (!existing.meta.related_commits.includes(commit)) existing.meta.related_commits.push(commit);
    writeDraft(existing.meta, existing.body);
    console.log(`[memory] ⏫ draft "${name}" trigger_count → ${existing.meta.trigger_count}${existing.meta.trigger_count >= PROMOTION_THRESHOLD ? "（已達升格門檻！跑 promote）" : ""}`);
    return;
  }

  const body = `**Rule:** ${rule}\n**Why:** ${why ?? "（待補）"}\n**How to apply:** ${how || "（待補）"}`;
  writeDraft({
    name,
    description: desc,
    type,
    trigger_count: 1,
    first_seen: new Date().toISOString(),
    related_commits: [currentCommit()],
  }, body);
  console.log(`[memory] ✏️  新 draft: ${draftPath(name)}`);
}

function proposeFromSmoke(logPath: string) {
  if (!fs.existsSync(logPath)) {
    console.error(`[memory] smoke log 不存在: ${logPath}`);
    process.exit(1);
  }
  const log = fs.readFileSync(logPath, "utf-8");
  const fails = log.split(/\r?\n/).filter((l) => /❌|💥|FAILED/.test(l));
  if (fails.length === 0) {
    console.log("[memory] smoke log 無失敗，不 propose");
    return;
  }
  console.log(`[memory] 偵測到 ${fails.length} 條失敗線索，產生 draft 提示：`);
  for (const f of fails) console.log(`   - ${f.trim().slice(0, 120)}`);
  console.log(`\n[memory] 請人工判斷後跑 propose --name ... 落地（鐵律 #0：寧缺勿濫，不自動亂塞）`);
}

// ── list ──
function list() {
  ensureDirs();
  const files = fs.readdirSync(DRAFT_DIR).filter((f) => f.endsWith(".md"));
  if (files.length === 0) {
    console.log("[memory] 無 draft");
    return;
  }
  console.log(`[memory] ${files.length} 個 draft：\n`);
  for (const f of files) {
    const slug = f.replace(/\.md$/, "");
    const d = readDraft(slug);
    if (!d) continue;
    const ready = d.meta.trigger_count >= PROMOTION_THRESHOLD ? " 🟢可升格" : "";
    console.log(`  [${d.meta.trigger_count}x]${ready} ${slug} — ${d.meta.description}`);
  }
  console.log(`\n升格門檻：${PROMOTION_THRESHOLD}x（或手動 promote <slug>）`);
}

// ── promote ──
function promote() {
  const slug = process.argv[3];
  if (!slug || slug.startsWith("--")) {
    console.error("用法: promote <slug>");
    process.exit(1);
  }
  const d = readDraft(slug);
  if (!d) {
    console.error(`[memory] draft 不存在: ${slug}`);
    process.exit(1);
  }

  fs.mkdirSync(USER_MEMORY_DIR, { recursive: true });
  const targetFile = path.join(USER_MEMORY_DIR, `${slug}.md`);
  const memContent = `---
name: ${d.meta.name}
description: ${d.meta.description}
metadata:
  type: ${d.meta.type}
---

${d.body.trim()}

> 升格自 Fable Toolkit memory draft（trigger ${d.meta.trigger_count}x，commits: ${d.meta.related_commits.join(", ")}）
`;
  fs.writeFileSync(targetFile, memContent);

  // 更新 MEMORY.md 索引
  const indexFile = path.join(USER_MEMORY_DIR, "MEMORY.md");
  if (fs.existsSync(indexFile)) {
    const pointer = `- [${d.meta.description}](${slug}.md) — 升格自 Fable Toolkit\n`;
    fs.appendFileSync(indexFile, pointer);
  }

  // 移除 draft
  fs.unlinkSync(draftPath(slug));
  console.log(`[memory] ✅ 升格: ${targetFile}`);
  console.log(`[memory] 已更新 MEMORY.md 索引 + 刪除 draft`);
}

function main() {
  const cmd = process.argv[2];
  switch (cmd) {
    case "propose": propose(); break;
    case "list": list(); break;
    case "promote": promote(); break;
    default:
      console.error("用法: memory-pipeline.ts <propose|list|promote>");
      process.exit(1);
  }
}

main();
