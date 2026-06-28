// scripts/fable/iron-law-guard.ts
// ============================================================
// Fable Toolkit 件 1：Iron Law Guard（鐵律物理擋）
// ------------------------------------------------------------
// 偵測鐵律 #0（禁止過渡/fallback）+ 鐵律 #1'（單一入口）違反 pattern。
//
// 兩種模式：
//   預設（pre-commit）：只掃 staged diff 的「新增行」
//     → 不強迫清理 legacy，只擋「這次新寫的」違反，符合鐵律 #0 漸進落地
//   --all：掃 scan_paths 全 codebase（手動 audit 用）
//
// 跑法：
//   tsx scripts/fable/iron-law-guard.ts          # pre-commit（staged 新增行）
//   tsx scripts/fable/iron-law-guard.ts --all     # 全 codebase audit
//
// ERROR 違反 → exit 1（擋 commit）；WARN → 只印不擋。
// ============================================================

import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

type Severity = "error" | "warn";

interface Pattern {
  regex: RegExp;
  severity: Severity;
  rule: string;
}

interface Violation {
  file: string;
  line: number;
  severity: Severity;
  rule: string;
  snippet: string;
}

// ── 預設偵測 pattern（保守，避免 false-positive hell）──
// 設計原則：寧可漏抓也不誤殺；ERROR 必須是「幾乎一定是過渡做法」的鐵證
const DEFAULT_PATTERNS: Pattern[] = [
  // 鐵律 #0：fallback 掩蓋 bug
  { regex: /\?\?\s*['"]unknown['"]/i, severity: "error", rule: "鐵律 #0 — ?? 'unknown' 掩蓋資料缺失" },
  { regex: /\?\?\s*0\.5\b/, severity: "error", rule: "鐵律 #0 — ?? 0.5 掩蓋分母為零 bug" },
  // 鐵律 #0：中文過渡標註（幾乎一定是技術債）
  { regex: /\/\/\s*(暫時|過渡|先這樣|急用|臨時|hack\b|workaround)/i, severity: "error", rule: "鐵律 #0 — 過渡/暫時標註" },
  { regex: /\/\/\s*之後(再|補|改|修)/, severity: "error", rule: "鐵律 #0 — 「之後再修」承諾" },
  // 鐵律 #0：靜默吞錯（catch 後 return null/預設值）
  { regex: /catch\s*\([^)]*\)\s*\{\s*return\s+(null|undefined|\[\]|\{\}|0|false)\s*;?\s*\}/, severity: "warn", rule: "鐵律 #0 — catch 靜默 fallback（確認非 graceful degradation）" },
  // 鐵律 #1'：雙路徑語意
  { regex: /fallback\s+(to|到)\s/i, severity: "warn", rule: "鐵律 #1' — fallback 雙路徑語意，請改單一出口" },
  // TS 逃逸
  { regex: /@ts-ignore\b/, severity: "warn", rule: "型別逃逸 @ts-ignore（改 @ts-expect-error + 註明原因）" },
  // TODO/FIXME（只 warn，不擋）
  { regex: /\/\/\s*(TODO|FIXME)(?!\(webview\))/, severity: "warn", rule: "鐵律 #0 — TODO/FIXME 過渡承諾" },
];

// ── 可選 per-project override：.claude/toolkit-config.yaml 的 iron_law.extra_patterns ──
function loadExtraPatterns(): Pattern[] {
  const cfgPath = path.resolve(process.cwd(), ".claude/toolkit-config.yaml");
  if (!fs.existsSync(cfgPath)) return [];
  try {
    const src = fs.readFileSync(cfgPath, "utf-8");
    // 極簡 YAML 解析：只抓 iron_law.extra_patterns 下的 - regex: / severity: / rule:
    const extra: Pattern[] = [];
    const lines = src.split(/\r?\n/);
    let inExtra = false;
    let cur: Partial<Pattern> & { regexStr?: string } = {};
    for (const raw of lines) {
      const line = raw.replace(/\t/g, "  ");
      if (/^\s*extra_patterns:\s*$/.test(line)) { inExtra = true; continue; }
      if (inExtra && /^\S/.test(line)) break; // 回到頂層 → 離開
      if (!inExtra) continue;
      const mRegex = line.match(/^\s*-\s*regex:\s*['"]?(.+?)['"]?\s*$/);
      const mSev = line.match(/^\s*severity:\s*(error|warn)\s*$/);
      const mRule = line.match(/^\s*rule:\s*['"]?(.+?)['"]?\s*$/);
      if (mRegex) {
        if (cur.regexStr) { pushCur(extra, cur); cur = {}; }
        cur.regexStr = mRegex[1];
      } else if (mSev) {
        cur.severity = mSev[1] as Severity;
      } else if (mRule) {
        cur.rule = mRule[1];
      }
    }
    if (cur.regexStr) pushCur(extra, cur);
    return extra;
  } catch {
    return [];
  }
}

function pushCur(arr: Pattern[], cur: Partial<Pattern> & { regexStr?: string }) {
  if (!cur.regexStr) return;
  try {
    arr.push({
      regex: new RegExp(cur.regexStr),
      severity: cur.severity ?? "error",
      rule: cur.rule ?? `自訂 pattern: ${cur.regexStr}`,
    });
  } catch {
    console.warn(`[iron-law] 略過無效 regex: ${cur.regexStr}`);
  }
}

// ── 掃描來源 ──
const SCAN_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx"];

function shouldScanFile(file: string): boolean {
  if (!SCAN_EXTENSIONS.includes(path.extname(file))) return false;
  if (/node_modules|\.next|\.git|dist|build/.test(file)) return false;
  // 排除測試/腳本自身（toolkit 自己會含這些 pattern 字串）
  if (/scripts[\\/]fable[\\/]/.test(file)) return false;
  if (/\.test\.|\.spec\./.test(file)) return false;
  return true;
}

// 模式 A：staged diff 的新增行
function scanStagedDiff(patterns: Pattern[]): Violation[] {
  const violations: Violation[] = [];
  let diff = "";
  try {
    diff = execSync("git diff --cached -U0 --no-color", { encoding: "utf-8", maxBuffer: 50 * 1024 * 1024 });
  } catch {
    return violations;
  }

  let curFile = "";
  let curNewLine = 0;
  for (const line of diff.split(/\r?\n/)) {
    const mFile = line.match(/^\+\+\+ b\/(.+)$/);
    if (mFile) { curFile = mFile[1]; continue; }
    const mHunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (mHunk) { curNewLine = parseInt(mHunk[1], 10); continue; }
    if (line.startsWith("+") && !line.startsWith("+++")) {
      const content = line.slice(1);
      if (shouldScanFile(curFile)) {
        for (const p of patterns) {
          if (p.regex.test(content)) {
            violations.push({
              file: curFile,
              line: curNewLine,
              severity: p.severity,
              rule: p.rule,
              snippet: content.trim().slice(0, 100),
            });
          }
        }
      }
      curNewLine++;
    } else if (!line.startsWith("-")) {
      // context line（-U0 理論上不會有，但保險）
      curNewLine++;
    }
  }
  return violations;
}

// 模式 B：全 codebase
function scanAll(patterns: Pattern[]): Violation[] {
  const violations: Violation[] = [];
  const scanPaths = ["app", "lib", "components"].filter((d) =>
    fs.existsSync(path.resolve(process.cwd(), d)),
  );
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (/node_modules|\.next|\.git|dist|build/.test(full)) continue;
        walk(full);
      } else {
        const rel = path.relative(process.cwd(), full).replace(/\\/g, "/");
        if (!shouldScanFile(rel)) continue;
        const src = fs.readFileSync(full, "utf-8");
        const lines = src.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
          for (const p of patterns) {
            if (p.regex.test(lines[i])) {
              violations.push({
                file: rel,
                line: i + 1,
                severity: p.severity,
                rule: p.rule,
                snippet: lines[i].trim().slice(0, 100),
              });
            }
          }
        }
      }
    }
  };
  for (const d of scanPaths) walk(path.resolve(process.cwd(), d));
  return violations;
}

function main() {
  const allMode = process.argv.includes("--all");
  const patterns = [...DEFAULT_PATTERNS, ...loadExtraPatterns()];

  const violations = allMode ? scanAll(patterns) : scanStagedDiff(patterns);

  const errors = violations.filter((v) => v.severity === "error");
  const warns = violations.filter((v) => v.severity === "warn");

  if (violations.length === 0) {
    console.log(`[iron-law] ✅ ${allMode ? "全 codebase" : "staged 新增行"} 無鐵律違反`);
    process.exit(0);
  }

  if (errors.length > 0) {
    console.error(`\n[iron-law] ❌ ${errors.length} 個 ERROR 違反（擋 commit）：`);
    for (const v of errors) {
      console.error(`  ${v.file}:${v.line}  ${v.rule}`);
      console.error(`      ${v.snippet}`);
    }
  }
  if (warns.length > 0) {
    console.warn(`\n[iron-law] ⚠️  ${warns.length} 個 WARN（不擋，但建議檢查）：`);
    for (const v of warns) {
      console.warn(`  ${v.file}:${v.line}  ${v.rule}`);
      console.warn(`      ${v.snippet}`);
    }
  }

  if (errors.length > 0) {
    console.error("\n[iron-law] FAIL — 修掉 ERROR 違反，或若確為誤判，在 .claude/toolkit-config.yaml 的 iron_law.suppress 列出。");
    process.exit(1);
  }
  console.log("\n[iron-law] ✅ 僅 WARN，放行");
  process.exit(0);
}

main();
