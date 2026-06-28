# 塔防対決 (twtd) — Claude Code 專案指引

> 本檔案為 Claude Code 的專案級指引，每次對話開始時自動載入。

---

## 專案概述

**塔防対決** — 雙人對戰塔防遊戲（H5/APK）
- Vue 3 + Vite，純前端
- 玩家 vs AI，各自在棋盤佈防，波次擊敗對方的蔣（主將）獲勝
- 參考原型：微信小程序「趙雲與阿斗」

---

## ⚠️ 開發前必讀（每次對話都要做）

### 1. 先讀進度追蹤
```
.agent/workflows/PROGRESS.md
```

### 2. 再讀相關 SKILL 文件
根據要開發的功能，閱讀對應的 SKILL 文件（見下方索引）。

### 3. 開發後更新文件
- 更新 `PROGRESS.md` 進度與變更紀錄
- 更新相關 SKILL 文件的「實作進度」

---

## ⚠️ 關鍵規則

### 代碼規範
- 所有邏輯改動必須同步更新對應 SKILL 文件
- 繁體中文 UI 文字，簡體中文代碼註釋
- 不加不必要的 console.log

### 遊戲設計規則
- 棋盤 8列×5行，路線為U形（左列→頂行→右列 / 右列→底行→左列）
- 粮食是唯一資源，初始20，殺敵+1，蔣中招+10
- 招募費用從10起，每次+2

### AI 行為規則
- AI 要和玩家一樣逐張放兵，0.8~2秒一張
- 有手牌時偶爾合並或挪動，無牌時存糧招募

---

## 📂 SKILL 文件索引

### 🔴 進度追蹤（每次必讀）
| 檔案 | 說明 |
|------|------|
| `.agent/workflows/PROGRESS.md` | **開發進度總覽** |

### 🎮 遊戲功能模組
| 檔案 | 說明 | 狀態 |
|------|------|------|
| `.agent/workflows/board_system.md` | 棋盤、格子、拖放部署 | 🟡 |
| `.agent/workflows/combat_system.md` | 戰鬥引擎、攻擊判定、波次 | 🟡 |
| `.agent/workflows/ai_system.md` | AI 自動操作邏輯 | 🟡 |
| `.agent/workflows/ui_system.md` | 手牌、招募、UI 視覺效果 | 🟡 |

---

## 技術棧快速參考

| 層級 | 技術 |
|------|------|
| Framework | Vue 3 (Composition API) |
| Build | Vite 8 |
| State | reactive store (gameStore.js) |
| 遊戲引擎 | 純 JS requestAnimationFrame |
| 兵種配置 | src/game/config.js |
| 引擎邏輯 | src/game/engine.js |
| 狀態管理 | src/stores/gameStore.js |
| 主畫面 | src/components/GameBoard.vue |

---

## 專案術語表

| 術語 | 說明 |
|------|------|
| 蔣 | 玩家/AI 的主將，被攻擊則扣血，血量歸零輸掉 |
| 营 | 敵軍出生點 |
| 粮食 | 唯一資源，用於招募兵卡 |
| 征兵 | 玩家花費粮食抽取一手新牌 |
| 路徑格 | 敵軍行進的格子（U形路線） |
| 解鎖格 | 可以放置單位的格子 |
| 鎖定格 | 尚未解鎖，需用鏟子開啟 |

---

> ⚠️ **開發前請確認**：閱讀 `PROGRESS.md` 確認目前進度，並在開發後更新文件。
