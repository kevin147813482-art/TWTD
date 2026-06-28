// scripts/fable/visual-verify.ts
// ============================================================
// Fable Toolkit 件 3：Visual Verify（Playwright 視覺回歸偵測）
// ------------------------------------------------------------
// 對 critical_pages 截圖 → 跟 baseline diff → 報告回歸。
// 解決「UI 改了沒人實機看」的盲點（如 Loot Box 動畫、Tailwind v4 source order bug）。
//
// 跑法：
//   tsx scripts/fable/visual-verify.ts                # 跟 baseline diff
//   tsx scripts/fable/visual-verify.ts --baseline      # 重生 baseline（UI 故意改後）
//
// 依賴：playwright (chromium) + pngjs（皆已裝）。pixel diff 自寫，不加 pixelmatch。
//
// 鐵律 #0：dev server 沒起時明確報「未驗證」並 exit 2，不假裝 PASS。
// ============================================================

import fs from "node:fs";
import path from "node:path";

interface PageCfg {
  url: string;
  name: string;
  animate?: boolean; // 動畫頁：截 3 frame
  waitMs?: number;
}
interface Viewport {
  name: string;
  width: number;
  height: number;
}
interface VisualConfig {
  base_url: string;
  dev_server_wait_url?: string;
  storage_state?: string; // 已登入 session（Playwright storageState JSON 路徑）
  critical_pages: PageCfg[];
  viewports: Viewport[];
  diff_threshold: number; // 0.02 = 2% 像素差才算回歸
}

const DEFAULT_CONFIG: VisualConfig = {
  base_url: "http://localhost:4000",
  critical_pages: [{ url: "/", name: "home" }],
  viewports: [
    { name: "mobile", width: 390, height: 844 },
    { name: "desktop", width: 1440, height: 900 },
  ],
  diff_threshold: 0.02,
};

// ── 從 .claude/toolkit-config.yaml 讀 visual config（極簡解析）──
function loadConfig(): VisualConfig {
  const cfgPath = path.resolve(process.cwd(), ".claude/toolkit-config.yaml");
  if (!fs.existsSync(cfgPath)) return DEFAULT_CONFIG;
  try {
    const src = fs.readFileSync(cfgPath, "utf-8");
    const visualBlock = extractBlock(src, "visual");
    if (!visualBlock) return DEFAULT_CONFIG;

    const cfg: VisualConfig = { ...DEFAULT_CONFIG, critical_pages: [], viewports: [] };
    const baseUrl = visualBlock.match(/^\s*base_url:\s*['"]?(.+?)['"]?\s*$/m);
    if (baseUrl) cfg.base_url = baseUrl[1];
    const waitUrl = visualBlock.match(/^\s*dev_server_wait_url:\s*['"]?(.+?)['"]?\s*$/m);
    if (waitUrl) cfg.dev_server_wait_url = waitUrl[1];
    const storage = visualBlock.match(/^\s*storage_state:\s*['"]?(.+?)['"]?\s*$/m);
    if (storage) cfg.storage_state = storage[1];
    const thr = visualBlock.match(/^\s*diff_threshold:\s*([\d.]+)/m);
    if (thr) cfg.diff_threshold = parseFloat(thr[1]);

    // critical_pages: - { url: /x, name: y, animate: true }
    for (const m of visualBlock.matchAll(/-\s*\{\s*url:\s*['"]?([^,'"}\s]+)['"]?\s*,\s*name:\s*['"]?([^,'"}\s]+)['"]?(?:\s*,\s*animate:\s*(true|false))?[^}]*\}/g)) {
      cfg.critical_pages.push({ url: m[1], name: m[2], animate: m[3] === "true" });
    }
    // viewports: - { name: mobile, width: 390, height: 844 }
    for (const m of visualBlock.matchAll(/-\s*\{\s*name:\s*['"]?([^,'"}\s]+)['"]?\s*,\s*width:\s*(\d+)\s*,\s*height:\s*(\d+)\s*\}/g)) {
      cfg.viewports.push({ name: m[1], width: parseInt(m[2], 10), height: parseInt(m[3], 10) });
    }
    if (cfg.critical_pages.length === 0) cfg.critical_pages = DEFAULT_CONFIG.critical_pages;
    if (cfg.viewports.length === 0) cfg.viewports = DEFAULT_CONFIG.viewports;
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

function extractBlock(src: string, key: string): string | null {
  const lines = src.split(/\r?\n/);
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (new RegExp(`^${key}:\\s*$`).test(lines[i])) { start = i + 1; break; }
  }
  if (start === -1) return null;
  const out: string[] = [];
  for (let i = start; i < lines.length; i++) {
    if (/^\S/.test(lines[i])) break; // 回到頂層
    out.push(lines[i]);
  }
  return out.join("\n");
}

// ── 自寫 pixel diff（pngjs only）──
async function pixelDiff(
  baselinePath: string,
  currentPath: string,
  diffOutPath: string,
): Promise<{ ratio: number; width: number; height: number; sizeMismatch: boolean }> {
  const { PNG } = await import("pngjs");
  const baseline = PNG.sync.read(fs.readFileSync(baselinePath));
  const current = PNG.sync.read(fs.readFileSync(currentPath));

  if (baseline.width !== current.width || baseline.height !== current.height) {
    return { ratio: 1, width: current.width, height: current.height, sizeMismatch: true };
  }

  const { width, height } = baseline;
  const diff = new PNG({ width, height });
  let changed = 0;
  const THRESHOLD = 30; // 單一 channel 差 > 30 才算不同 pixel（抗 antialiasing 噪音）

  for (let i = 0; i < width * height; i++) {
    const idx = i * 4;
    const dr = Math.abs(baseline.data[idx] - current.data[idx]);
    const dg = Math.abs(baseline.data[idx + 1] - current.data[idx + 1]);
    const db = Math.abs(baseline.data[idx + 2] - current.data[idx + 2]);
    const isDiff = dr > THRESHOLD || dg > THRESHOLD || db > THRESHOLD;
    if (isDiff) {
      changed++;
      // diff 圖標紅
      diff.data[idx] = 255;
      diff.data[idx + 1] = 0;
      diff.data[idx + 2] = 0;
      diff.data[idx + 3] = 255;
    } else {
      // 淡化原圖
      diff.data[idx] = baseline.data[idx];
      diff.data[idx + 1] = baseline.data[idx + 1];
      diff.data[idx + 2] = baseline.data[idx + 2];
      diff.data[idx + 3] = 60;
    }
  }
  fs.writeFileSync(diffOutPath, PNG.sync.write(diff));
  return { ratio: changed / (width * height), width, height, sizeMismatch: false };
}

async function isServerUp(url: string): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(url, { signal: controller.signal, redirect: "manual" });
    clearTimeout(timer);
    // 3xx redirect（如 307 導到 locale）也算 server 活著；只有 5xx 或連不上才算 down
    return res.status < 500;
  } catch {
    return false;
  }
}

async function main() {
  const baselineMode = process.argv.includes("--baseline");
  const cfg = loadConfig();

  const baseDir = path.resolve(process.cwd(), ".claude/visual-baselines");
  const curDir = path.resolve(process.cwd(), ".claude/visual-current");
  const diffDir = path.resolve(process.cwd(), ".claude/visual-diffs");
  for (const d of [baseDir, curDir, diffDir]) fs.mkdirSync(d, { recursive: true });

  // dev server 健康檢查
  const healthUrl = cfg.dev_server_wait_url || cfg.base_url;
  if (!(await isServerUp(healthUrl))) {
    console.error(`[visual] ❌ dev server 未啟動 (${healthUrl})`);
    console.error(`[visual] 請先在另一個終端跑：npm run dev -- -p 4000`);
    console.error(`[visual] 鐵律 #0：未實機驗證不假裝 PASS。exit 2。`);
    process.exit(2);
  }

  const { chromium } = await import("playwright");
  const browser = await chromium.launch();
  const contextOpts: Record<string, unknown> = {};
  if (cfg.storage_state && fs.existsSync(path.resolve(process.cwd(), cfg.storage_state))) {
    contextOpts.storageState = path.resolve(process.cwd(), cfg.storage_state);
  }

  interface Result { page: string; viewport: string; status: "BASELINE" | "PASS" | "REGRESSION" | "SIZE_CHANGE"; ratio?: number; }
  const results: Result[] = [];

  for (const vp of cfg.viewports) {
    const context = await browser.newContext({ ...contextOpts, viewport: { width: vp.width, height: vp.height } });
    const page = await context.newPage();

    for (const pc of cfg.critical_pages) {
      const tag = `${pc.name}-${vp.name}`;
      const url = cfg.base_url + pc.url;
      try {
        // dev server 有 HMR websocket / 輪詢 → networkidle 永不觸發，改 domcontentloaded
        await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
        // 等內容渲染（dev 首次編譯較慢）；動畫頁多等
        await page.waitForTimeout(pc.waitMs ?? (pc.animate ? 2000 : 1500));
      } catch (err) {
        console.error(`[visual] ⚠️ ${tag} 載入失敗: ${err instanceof Error ? err.message : err}`);
        results.push({ page: pc.name, viewport: vp.name, status: "REGRESSION" });
        continue;
      }

      const curPath = path.join(curDir, `${tag}.png`);
      await page.screenshot({ path: curPath, fullPage: true });

      const basePath = path.join(baseDir, `${tag}.png`);
      if (baselineMode || !fs.existsSync(basePath)) {
        fs.copyFileSync(curPath, basePath);
        results.push({ page: pc.name, viewport: vp.name, status: "BASELINE" });
        continue;
      }

      const diffPath = path.join(diffDir, `${tag}-diff.png`);
      const { ratio, sizeMismatch } = await pixelDiff(basePath, curPath, diffPath);
      if (sizeMismatch) {
        results.push({ page: pc.name, viewport: vp.name, status: "SIZE_CHANGE", ratio: 1 });
      } else if (ratio > cfg.diff_threshold) {
        results.push({ page: pc.name, viewport: vp.name, status: "REGRESSION", ratio });
      } else {
        results.push({ page: pc.name, viewport: vp.name, status: "PASS", ratio });
      }
    }
    await context.close();
  }
  await browser.close();

  // 報告
  console.log("\n─── Visual Verify 結果 ───");
  let regressions = 0;
  for (const r of results) {
    const icon = r.status === "PASS" ? "✅" : r.status === "BASELINE" ? "📸" : "❌";
    const pct = r.ratio !== undefined ? ` (${(r.ratio * 100).toFixed(2)}% diff)` : "";
    console.log(`  ${icon} ${r.page}-${r.viewport}: ${r.status}${pct}`);
    if (r.status === "REGRESSION" || r.status === "SIZE_CHANGE") regressions++;
  }

  if (baselineMode) {
    console.log(`\n[visual] 📸 baseline 已重生（${results.length} 張）`);
    process.exit(0);
  }
  if (regressions > 0) {
    console.error(`\n[visual] ❌ ${regressions} 個視覺回歸 — 看 .claude/visual-diffs/`);
    console.error(`[visual] 若是故意改 UI，跑 npm run fable:visual:baseline 更新基準`);
    process.exit(1);
  }
  console.log(`\n[visual] ✅ 全部通過，無視覺回歸`);
  process.exit(0);
}

main().catch((err) => {
  console.error("[visual] FATAL:", err);
  process.exit(2);
});
