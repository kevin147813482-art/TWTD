<template>
  <div class="game-board" ref="gameBoardRef" @dragover="onGlobalDragOver">

    <!-- 顶部信息栏 -->
    <div class="top-bar">
      <!-- 左：暂停 + 粮食 -->
      <div class="top-left">
        <button class="btn-pause" @click="store.togglePause()"
          :disabled="store.phase === 'prep'">
          {{ store.phase === 'paused' ? '▶' : '⏸' }}
        </button>
        <div class="food-count">
          <span>🍞</span><span>{{ store.playerFood }}</span>
        </div>
      </div>
      <!-- 中：关卡名 + 波次 -->
      <div class="top-center">
        <div v-if="store.phase === 'prep'" class="map-name prep-text">護駕！先布防</div>
        <div v-else class="map-name">{{ store.mapName }}</div>
        <div class="wave-label">
          <span v-if="store.bossWarning" class="boss-tag">⚠ BOSS波</span>
          <span v-else-if="store.phase === 'prep'">準備中</span>
          <span v-else>第{{ store.wave }}波</span>
        </div>
      </div>
      <!-- 右：击杀数 -->
      <div class="top-right">
        <div class="score-pill">擊{{ store.playerScore }}</div>
      </div>
    </div>

    <!-- ══ AI 区（上半） ══ -->
    <div class="section ai-section">
      <div class="grid-wrap">
        <div class="board-grid">
          <template v-for="(row, ri) in store.aiBoard" :key="ri">
            <div v-for="(cell, ci) in row" :key="ci"
              class="cell"
              :class="{
                'cell-path':     cell.kind === 'path',
                'cell-unlocked': cell.kind === 'unlocked',
                'cell-locked':   cell.kind === 'locked',
              }">
              <!-- 蔣（AI: [0,0]）带HP血条，准备阶段隐藏（蔣在走路） -->
              <div v-if="ri === AI_JIANG_CELL[0] && ci === AI_JIANG_CELL[1] && store.phase!=='prep'"
                class="jiang-cell">
                <div class="jiang-hp-row">
                  <span v-for="i in store.aiJiangMaxHp" :key="i"
                    :class="['jhp', i <= store.aiJiangHp ? 'on' : 'off']">♥</span>
                </div>
                <span class="jiang-char">蔣</span>
              </div>
              <!-- 营（AI: [0,7]）出兵口装饰 -->
              <div v-else-if="ri === AI_YING_CELL[0] && ci === AI_YING_CELL[1]"
                class="spawn-gate ai-gate">
                <div class="gate-clouds">
                  <span class="cloud c1">☁</span>
                  <span class="cloud c2">☁</span>
                  <span class="cloud c3">☁</span>
                </div>
                <div class="gate-arch"></div>
              </div>
              <!-- 单位 -->
              <div v-else-if="cell.unit" class="unit"
                :class="[`ut-${cell.unit.type}`, { atk: cell.unit.attacking }]">
                {{ cell.unit.type === 'general_char' ? cell.unit.char : cell.unit.key }}
                <span v-if="cell.unit.level > 1" class="lv">{{ cell.unit.level }}</span>
              </div>
            </div>
          </template>
        </div>
        <!-- AI 蔣行走（准备阶段） -->
        <div v-if="store.phase==='prep'" class="enemy-layer">
          <div class="jiang-walker ai-walker"
            :style="getEnemyStyle(store.aiJiangProgress, true)">
            <div class="walker-hp">
              <span v-for="i in store.aiJiangMaxHp" :key="i"
                :class="['whp', i<=store.aiJiangHp?'on':'off']">♥</span>
            </div>
            <span class="walker-char">蔣</span>
          </div>
        </div>
        <!-- AI 投射物 -->
        <div class="enemy-layer">
          <div v-for="p in store.projectiles.filter(p=>p.side==='ai')" :key="p.id"
            class="projectile"
            :class="`proj-${p.kind}`"
            :style="{ '--sx':p.sx,'--sy':p.sy,'--ex':p.ex,'--ey':p.ey }">
            {{ p.kind==='shell'?'●':p.kind==='bullet'?'·':p.kind==='arrow'?'→':'✦' }}
          </div>
        </div>
        <!-- AI 敌军 -->
        <div class="enemy-layer">
          <div v-for="e in store.aiEnemies" :key="e.id"
            class="enemy"
            :class="{ boss: e.isBoss }"
            :style="{ ...getEnemyStyle(e.pathProgress, true), color: ECOLOR[e.key] }">
            <div class="ehp">
              <div class="ehpf" :style="{ width: (e.hp/e.maxHp*100)+'%', background: e.isBoss?'#e53935':'#66bb6a' }"></div>
            </div>
            {{ e.key }}
          </div>
        </div>
        <!-- AI 危险警告 -->
        <transition name="danger-fade">
          <div v-if="store.aiDanger" class="danger-overlay">危</div>
        </transition>
      </div>
    </div>

    <!-- 分割线 -->
    <div class="divider">── 對決 ──</div>

    <!-- ══ 玩家区（下半） ══ -->
    <div class="section player-section">
      <div class="grid-wrap">
        <div class="board-grid">
          <template v-for="(row, ri) in store.playerBoard" :key="ri">
            <div v-for="(cell, ci) in row" :key="ci"
              class="cell"
              :class="{
                'cell-path':     cell.kind === 'path',
                'cell-unlocked': cell.kind === 'unlocked',
                'cell-locked':   cell.kind === 'locked',
                'cell-dragover': dragOver === `${ri}-${ci}`,
              }"
              @dragover.prevent="dragOver = `${ri}-${ci}`; dragHover = [ri, ci]"
              @dragleave="dragOver = null"
              @drop="onDrop(ri, ci)"
              @click="onCellClick(ri, ci)">
              <!-- 蔣（玩家: [4,7]）带HP血条，准备阶段隐藏 -->
              <div v-if="ri === PLAYER_JIANG_CELL[0] && ci === PLAYER_JIANG_CELL[1] && store.phase!=='prep'"
                class="jiang-cell" :class="{ damaged: jiangFlash }">
                <div class="jiang-hp-row">
                  <span v-for="i in store.playerJiangMaxHp" :key="i"
                    :class="['jhp', i <= store.playerJiangHp ? 'on' : 'off']">♥</span>
                </div>
                <span class="jiang-char">蔣</span>
              </div>
              <!-- 营（玩家: [4,0]）出兵口装饰 -->
              <div v-else-if="ri === PLAYER_YING_CELL[0] && ci === PLAYER_YING_CELL[1]"
                class="spawn-gate player-gate">
                <div class="gate-arch"></div>
                <div class="gate-clouds">
                  <span class="cloud c1">☁</span>
                  <span class="cloud c2">☁</span>
                  <span class="cloud c3">☁</span>
                </div>
              </div>
              <!-- 单位 -->
              <div v-else-if="cell.unit" class="unit"
                :class="[`ut-${cell.unit.type}`, { atk: cell.unit.attacking, dragging: boardDrag && boardDrag[0]===ri && boardDrag[1]===ci }]"
                draggable="true"
                @dragstart.stop="onBoardDragStart(ri, ci, $event)"
                @dragend.stop="boardDrag = null; clearDragLine()"
                @click.stop="infoUnit = cell.unit">
                {{ cell.unit.type === 'general_char' ? cell.unit.char : cell.unit.key }}
                <span v-if="cell.unit.level > 1" class="lv">{{ cell.unit.level }}</span>
              </div>
              <div v-else-if="cell.kind === 'locked'" class="lock-plus">+</div>
            </div>
          </template>
        </div>
        <!-- 玩家 蔣行走（准备阶段） -->
        <div v-if="store.phase==='prep'" class="enemy-layer">
          <div class="jiang-walker player-walker"
            :style="getEnemyStyle(store.playerJiangProgress, false)">
            <div class="walker-hp">
              <span v-for="i in store.playerJiangMaxHp" :key="i"
                :class="['whp', i<=store.playerJiangHp?'on':'off']">♥</span>
            </div>
            <span class="walker-char">蔣</span>
          </div>
        </div>
        <!-- 玩家投射物 -->
        <div class="enemy-layer">
          <div v-for="p in store.projectiles.filter(p=>p.side==='player')" :key="p.id"
            class="projectile"
            :class="`proj-${p.kind}`"
            :style="{ '--sx':p.sx,'--sy':p.sy,'--ex':p.ex,'--ey':p.ey }">
            {{ p.kind==='shell'?'●':p.kind==='bullet'?'·':p.kind==='arrow'?'→':'✦' }}
          </div>
        </div>
        <!-- 玩家敌军 -->
        <div class="enemy-layer">
          <div v-for="e in store.playerEnemies" :key="e.id"
            class="enemy"
            :class="{ boss: e.isBoss }"
            :style="{ ...getEnemyStyle(e.pathProgress, false), color: ECOLOR[e.key] }">
            <div class="ehp">
              <div class="ehpf" :style="{ width: (e.hp/e.maxHp*100)+'%', background: e.isBoss?'#e53935':'#66bb6a' }"></div>
            </div>
            {{ e.key }}
          </div>
        </div>
        <!-- 拖拽范围预览圆圈 -->
        <div v-if="dragRangeStyle" class="range-preview" :style="dragRangeStyle"></div>
        <!-- 玩家 危险警告 -->
        <transition name="danger-fade">
          <div v-if="store.playerDanger" class="danger-overlay">危</div>
        </transition>
      </div>
    </div>

    <!-- ══ 底部操作区 ══ -->
    <div class="bottom-ui">
      <!-- 手牌行：营 + 手牌 + 铲子 -->
      <div class="hand-row">
        <!-- 营 图标 -->
        <div class="side-icon ying-icon">
          <span class="side-icon-char">營</span>
        </div>

        <!-- 手牌 -->
        <div class="hand-cards">
          <div v-for="(card, i) in store.playerHand" :key="i"
            class="card"
            :class="{ empty: !card, selected: selectedCard === i }"
            draggable="true"
            @dragstart="dragging = i; boardDrag = null; recordDragStart($event)"
            @dragend="dragging = null; clearDragLine()"
            @dragover.prevent
            @drop="onDropToHand(i)"
            @click="onCardClick(i)">
            <template v-if="card">
              <span class="card-char" :style="cardStyle(card)">{{ card.key }}</span>
              <span v-if="card.level" class="card-lv">{{ card.level }}</span>
            </template>
          </div>
        </div>

        <!-- 铲子/广告 图标 -->
        <div class="side-icon shovel-icon" @click="onGetShovel">
          <span class="side-icon-char">⛏</span>
          <span class="side-icon-sub">x2</span>
        </div>
      </div>

      <!-- 征兵按钮行 -->
      <div class="recruit-row">
        <button class="recruit-btn"
          :class="{ disabled: !store.canPlayerRecruit, ready: store.canPlayerRecruit }"
          @click="store.playerRecruit()">
          <span>征兵</span>
          <span class="cost">🍞{{ store.playerRecruitCost }}</span>
        </button>
      </div>
    </div>

    <!-- 拖拽虚线 -->
    <svg v-if="showDragLine" class="drag-line-svg">
      <line
        :x1="dragLineStart.x" :y1="dragLineStart.y"
        :x2="dragLineCur.x"   :y2="dragLineCur.y"
        stroke="rgba(255,215,0,0.75)" stroke-width="2"
        stroke-dasharray="6,4" stroke-linecap="round"
      />
    </svg>

    <!-- 单位弹窗 -->
    <div v-if="infoUnit" class="popup-mask" @click="infoUnit = null">
      <div class="popup" @click.stop>
        <div class="popup-char" :style="unitStyle(infoUnit)">
          {{ infoUnit.type === 'general_char' ? infoUnit.char : infoUnit.key }}
        </div>
        <div class="popup-info">
          <div class="popup-name">{{ unitName(infoUnit) }}</div>
          <div class="popup-stats">攻{{ unitAtk(infoUnit).toFixed(0) }} 速{{ unitSpd(infoUnit).toFixed(1) }} Lv{{ infoUnit.level }}</div>
        </div>
        <button class="popup-x" @click="infoUnit = null">✕</button>
      </div>
    </div>

  </div>
</template>

<script setup>
import { ref, watch, computed } from 'vue'
import { gameStore as store, PLAYER_JIANG_CELL, AI_JIANG_CELL, PLAYER_YING_CELL, AI_YING_CELL } from '../stores/gameStore.js'
import { getEnemyStyle, getUnitRange } from '../game/engine.js'
import { BASIC_UNITS, GENERALS, GAME_CONFIG } from '../game/config.js'

const ECOLOR = { 匪:'#555', 共:'#1a237e', 赤:'#c62828', 寇:'#4e342e' }

const dragging     = ref(null)   // 手牌index
const boardDrag    = ref(null)   // [row, col] 棋盘单位拖动源
const dragOver     = ref(null)
const dragHover    = ref(null)   // [row, col] 当前悬停格
const selectedCard = ref(null)
const infoUnit     = ref(null)
const jiangFlash   = ref(false)

const gameBoardRef  = ref(null)
const dragLineStart = ref(null)  // {x, y} 相对于 game-board
const dragLineCur   = ref(null)  // {x, y} 相对于 game-board

const showDragLine = computed(() =>
  (dragging.value !== null || boardDrag.value !== null) &&
  dragLineStart.value && dragLineCur.value
)

function recordDragStart(e) {
  if (!gameBoardRef.value) return
  const rect = e.currentTarget.getBoundingClientRect()
  const boardRect = gameBoardRef.value.getBoundingClientRect()
  dragLineStart.value = {
    x: rect.left + rect.width / 2 - boardRect.left,
    y: rect.top  + rect.height / 2 - boardRect.top,
  }
  dragLineCur.value = { ...dragLineStart.value }
}

function onGlobalDragOver(e) {
  if (dragging.value === null && !boardDrag.value) return
  if (!gameBoardRef.value) return
  const boardRect = gameBoardRef.value.getBoundingClientRect()
  dragLineCur.value = {
    x: e.clientX - boardRect.left,
    y: e.clientY - boardRect.top,
  }
}

function clearDragLine() {
  dragLineStart.value = null
  dragLineCur.value   = null
  dragHover.value     = null
}

watch(() => store.playerJiangHp, () => {
  jiangFlash.value = true
  setTimeout(() => { jiangFlash.value = false }, 400)
})

function cardStyle(card) {
  if (card.type === 'general' || card.type === 'general_char') return { color: '#c8960c', fontWeight: 'bold' }
  if (card.type === 'shovel') return { color: '#8b4513' }
  return { color: '#111' }
}
function unitStyle(unit) {
  if (unit.type === 'general') return { color: '#c8960c' }
  if (unit.type === 'general_char') return { color: '#9c6b00' }
  return { color: '#111' }
}
function unitName(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.fullName || unit.key
  if (unit.type === 'general_char') return `${unit.char}（武將字）`
  return BASIC_UNITS[unit.key]?.name || unit.key
}
function unitAtk(unit) {
  const base = unit.type === 'general' ? (GENERALS[unit.key]?.atk||6) : (BASIC_UNITS[unit.key]?.atk||2)
  return base + (unit.level - 1) * 1.5
}
function unitSpd(unit) {
  return unit.type === 'general' ? (GENERALS[unit.key]?.atkSpeed||1.5) : (BASIC_UNITS[unit.key]?.atkSpeed||1.5)
}

function onCardClick(i) {
  selectedCard.value = selectedCard.value === i ? null : i
}

function onCellClick(r, c) {
  if (selectedCard.value === null) return
  const card = store.playerHand[selectedCard.value]
  if (!card) { selectedCard.value = null; return }
  if (card.type === 'shovel') store.openCell(selectedCard.value, r, c)
  else store.deployUnit(selectedCard.value, r, c)
  selectedCard.value = null
}

function onBoardDragStart(r, c, e) {
  dragging.value = null
  dragHover.value = null
  recordDragStart(e)
  setTimeout(() => { boardDrag.value = [r, c] }, 0)
}

function onDrop(r, c) {
  dragOver.value = null
  dragHover.value = null
  // 棋盘单位拖到棋盘格
  if (boardDrag.value) {
    const [sr, sc] = boardDrag.value
    if (sr === r && sc === c) { boardDrag.value = null; return }
    store.moveOrMergeUnit(sr, sc, r, c)
    boardDrag.value = null
    return
  }
  // 手牌拖到棋盘格
  if (dragging.value === null) return
  const card = store.playerHand[dragging.value]
  if (!card) { dragging.value = null; return }
  if (card.type === 'shovel') store.openCell(dragging.value, r, c)
  else store.deployUnit(dragging.value, r, c)
  dragging.value = null
}

function onDropToHand(slotIndex) {
  // 棋盘单位拖回手牌栏（退回为卡牌）
  if (!boardDrag.value) return
  const [r, c] = boardDrag.value
  store.returnUnitToHand(r, c, slotIndex)
  boardDrag.value = null
}

function onGetShovel() {
  // 预留：看广告获得铲子
}

const COLS = GAME_CONFIG.BOARD_COLS
const ROWS = GAME_CONFIG.BOARD_ROWS

function getDragCard() {
  if (boardDrag.value) {
    const [r, c] = boardDrag.value
    return store.playerBoard[r]?.[c]?.unit || null
  }
  if (dragging.value !== null) return store.playerHand[dragging.value] || null
  return null
}

const dragRangeStyle = computed(() => {
  const isDragging = boardDrag.value || dragging.value !== null
  if (!isDragging || !dragHover.value) return null
  const card = getDragCard()
  if (!card || card.type === 'shovel') return null
  const [r, c] = dragHover.value
  const range = getUnitRange(card)
  const cx = (c + 0.5) / COLS * 100
  const cy = (r + 0.5) / ROWS * 100
  const rw = range / COLS * 100 * 2
  const rh = range / ROWS * 100 * 2
  return {
    left:   `${cx}%`,
    top:    `${cy}%`,
    width:  `${rw}%`,
    height: `${rh}%`,
    transform: 'translate(-50%, -50%)',
  }
})
</script>

<style scoped>
/* ── 整体布局 ── */
.game-board {
  /* 顶栏 58px + 分隔线 22px ≈ 80px，底部约 35%
     cell 取「宽/8」和「5.1vh」两者较小值，保持格子正方形 */
  --cell: min(calc(min(100vw, 420px) / 8), 5.1vh);
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #1e1e1e;
  font-family: 'Noto Serif TC', serif;
  overflow: hidden;
}

/* ── 顶部栏（三栏：左暂停+粮食 / 中关卡+波次 / 右击杀） ── */
.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 10px;
  background: rgba(0,0,0,0.82);
  color: #ffd700;
  flex-shrink: 0;
  min-height: 58px;
}

.top-left, .top-right {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 72px;
}
.top-right { justify-content: flex-end; }

.top-center {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex: 1;
  gap: 1px;
}

.btn-pause {
  background: rgba(255,255,255,0.12);
  border: 1px solid rgba(255,255,255,0.3);
  border-radius: 6px;
  color: #fff;
  font-size: 1rem;
  width: 30px;
  height: 30px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  flex-shrink: 0;
}
.btn-pause:disabled { opacity: 0.35; cursor: default; }

.food-count {
  display: flex;
  align-items: center;
  gap: 3px;
  font-size: 0.85rem;
  background: rgba(255,255,255,0.1);
  padding: 2px 7px;
  border-radius: 10px;
}

.map-name {
  font-size: 0.7rem;
  color: #c8960c;
  letter-spacing: 0.06em;
}
.wave-label {
  font-size: 1rem;
  font-weight: bold;
  color: #ffd700;
  line-height: 1.2;
}

.score-pill {
  background: rgba(255,255,255,0.1);
  padding: 2px 8px;
  border-radius: 10px;
  font-size: 0.8rem;
}
.boss-tag  { color: #ff4444; font-weight: bold; animation: pulse 0.4s infinite alternate; }
.prep-text { color: #ffd700; animation: pulse 0.8s infinite alternate; }
@keyframes pulse { from {opacity:.6} to {opacity:1} }

/* ── 战场区（上下两半） ── */
.section {
  display: flex;
  justify-content: center;  /* 棋盤水平居中 */
  flex-shrink: 0;
}

/* ── 棋盘容器：必须与棋盘格子完全同尺寸，enemy-layer 百分比才正确 ── */
.grid-wrap {
  position: relative;
  width: calc(var(--cell) * 8);
  height: calc(var(--cell) * 5);
}

/* ── 棋盘格子 ── */
.board-grid {
  display: grid;
  grid-template-columns: repeat(v-bind('GAME_CONFIG.BOARD_COLS'), var(--cell));
  grid-template-rows: repeat(v-bind('GAME_CONFIG.BOARD_ROWS'), var(--cell));
}

.cell {
  border: 1px solid rgba(0,0,0,0.18);
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
}

/* 三种格子颜色 */
.cell-path     { background: #a8c4a0; }
.cell-unlocked { background: #f0ece0; }
.cell-locked   { background: #6a8c68; cursor: pointer; }
.cell-dragover { outline: 2px solid #ffd700; }

.lock-plus {
  color: rgba(255,255,255,0.3);
  font-size: 0.9rem;
}

/* ── 出兵口装饰（营格） ── */
.spawn-gate {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;
}

.gate-arch {
  width: 70%;
  height: 45%;
  border-radius: 50% 50% 0 0;
  background: rgba(30, 20, 10, 0.75);
  border: 2px solid rgba(160, 120, 60, 0.8);
  border-bottom: none;
  position: relative;
  z-index: 1;
}

.ai-gate .gate-arch {
  border-radius: 0 0 50% 50%;
  border-top: none;
  border-bottom: 2px solid rgba(160, 120, 60, 0.8);
}

.gate-clouds {
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.cloud {
  position: absolute;
  color: rgba(255, 255, 255, 0.82);
  font-size: clamp(0.6rem, 2.2vw, 1.1rem);
  animation: cloudDrift 3s ease-in-out infinite;
  filter: drop-shadow(0 0 2px rgba(200,200,255,0.5));
}

.player-gate .c1 { bottom: 55%; left: 5%;  animation-delay: 0s;    animation-duration: 2.8s; }
.player-gate .c2 { bottom: 60%; left: 30%; animation-delay: 0.9s;  animation-duration: 3.2s; }
.player-gate .c3 { bottom: 52%; left: 55%; animation-delay: 0.4s;  animation-duration: 2.5s; }

.ai-gate .c1 { top: 55%; left: 5%;  animation-delay: 0s;    animation-duration: 2.8s; }
.ai-gate .c2 { top: 60%; left: 30%; animation-delay: 0.9s;  animation-duration: 3.2s; }
.ai-gate .c3 { top: 52%; left: 55%; animation-delay: 0.4s;  animation-duration: 2.5s; }

@keyframes cloudDrift {
  0%, 100% { transform: translateX(0) translateY(0); opacity: 0.7; }
  50%       { transform: translateX(3px) translateY(-2px); opacity: 1; }
}

/* ── 蔣格（路线格内，带HP） ── */
.jiang-cell {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1px;
}
.jiang-hp-row {
  display: flex;
  gap: 1px;
  justify-content: center;
}
.jhp {
  font-size: clamp(0.5rem, 1.8vw, 0.75rem);
  line-height: 1;
}
.jhp.on  { color: #e53935; }
.jhp.off { color: rgba(0,0,0,0.25); }

.jiang-char {
  font-size: clamp(1.1rem, 4.5vw, 2.2rem);
  font-weight: bold;
  color: #ffd700;
  text-shadow: 0 0 8px rgba(255,215,0,0.8);
  line-height: 1;
}

.jiang-cell.damaged .jiang-char {
  color: #ff5722;
  animation: shake 0.3s;
}
@keyframes shake {
  0%,100% { transform: translateX(0) }
  25%      { transform: translateX(-3px) }
  75%      { transform: translateX(3px) }
}

/* ── 棋盘内单位 ── */
.unit {
  width: 88%;
  height: 88%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f5f0e0;
  border: 1.5px solid #bbb;
  border-radius: 3px;
  font-size: clamp(0.65rem, 2.2vw, 1rem);
  font-weight: bold;
  color: #111;
  cursor: pointer;
  position: relative;
  transition: border-color 0.1s, transform 0.1s;
}
.unit.atk      { border-color: #ff5722; transform: scale(1.1); }
.unit.dragging { opacity: 0.35; border: 2px dashed #ffd700 !important; background: rgba(255,215,0,0.1); }
.unit.atk::after {
  content: '';
  position: absolute;
  inset: -4px;
  border-radius: 4px;
  background: radial-gradient(circle, rgba(255,100,0,0.5) 0%, transparent 70%);
  animation: meleeFlash 0.2s ease-out forwards;
  pointer-events: none;
}
@keyframes meleeFlash {
  0%   { opacity: 1; transform: scale(0.8); }
  100% { opacity: 0; transform: scale(1.6); }
}
.unit.ut-general {
  border-color: #c8960c;
  background: linear-gradient(135deg, #fff8e1, #ffecb3);
  color: #c8960c;
}
.unit.ut-general_char {
  border-color: #9c6b00;
  border-style: dashed;
  color: #9c6b00;
}
.lv {
  position: absolute;
  top: 1px; right: 2px;
  font-size: 0.42rem; color: #888; font-weight: normal;
}

/* ── 敌军层 ── */
.enemy-layer {
  position: absolute;
  inset: 0;
  pointer-events: none;
  overflow: visible;
}

.enemy {
  position: absolute;
  transform: translate(-50%, -50%);
  width: 26px;
  height: 26px;
  background: rgba(255,255,255,0.9);
  border: 1.5px solid currentColor;
  border-radius: 3px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.85rem;
  font-weight: bold;
  transition: left 0.06s linear, top 0.06s linear;
}
.enemy.boss { width:34px; height:34px; font-size:1.1rem; background:rgba(255,200,200,0.92); }

/* ── 投射物动画 ── */
.projectile {
  position: absolute;
  left: var(--sx);
  top:  var(--sy);
  transform: translate(-50%, -50%);
  pointer-events: none;
  font-size: 0.85rem;
  font-weight: bold;
  z-index: 10;
  animation: projFly 0.35s linear forwards;
}
@keyframes projFly {
  0%   { left: var(--sx); top: var(--sy); opacity: 1;   transform: translate(-50%,-50%) scale(1); }
  80%  { opacity: 1; }
  100% { left: var(--ex); top: var(--ey); opacity: 0.2; transform: translate(-50%,-50%) scale(0.6); }
}

.proj-bullet { color: #ffeb3b; font-size: 1rem; }
.proj-shell  { color: #ff6f00; font-size: 1.1rem; }
.proj-arrow  { color: #8d6e63; font-size: 1rem; }
.proj-slash  { color: rgba(255,80,0,0.8); font-size: 1.2rem; }

.ehp {
  position: absolute;
  top: -5px; left:0; right:0;
  height: 3px; background:rgba(0,0,0,0.25); border-radius:2px;
}
.ehpf { height:100%; border-radius:2px; transition: width 0.1s; }

/* ── 蔣行走（准备阶段） ── */
.jiang-walker {
  position: absolute;
  transform: translate(-50%, -50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
  pointer-events: none;
  z-index: 5;
}
.walker-hp {
  display: flex;
  gap: 1px;
}
.whp { font-size: 0.6rem; line-height:1; }
.whp.on  { color: #e53935; }
.whp.off { color: rgba(0,0,0,0.2); }
.walker-char {
  font-size: clamp(1rem, 4vw, 1.8rem);
  font-weight: bold;
  line-height: 1;
  text-shadow: 0 1px 3px rgba(0,0,0,0.5);
}
.player-walker .walker-char { color: #ffd700; }
.ai-walker .walker-char     { color: #7cb8e0; }

/* ── 拖拽范围预览圆圈 ── */
.range-preview {
  position: absolute;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.12);
  border: 1.5px solid rgba(255, 255, 255, 0.5);
  pointer-events: none;
  z-index: 20;
}

/* ── 拖拽虚线 SVG ── */
.drag-line-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 50;
  overflow: visible;
}

/* ── 危险警告 ── */
.danger-overlay {
  position: absolute;
  top: 50%;
  right: 6px;
  transform: translateY(-50%);
  font-size: 2.2rem;
  font-weight: 900;
  color: #ff1744;
  text-shadow: 0 0 12px #ff1744, 0 0 4px #fff;
  animation: dangerPulse 0.5s ease-in-out infinite alternate;
  pointer-events: none;
  z-index: 30;
}
@keyframes dangerPulse {
  from { opacity: 0.7; transform: translateY(-50%) scale(0.9); }
  to   { opacity: 1;   transform: translateY(-50%) scale(1.1); }
}
.danger-fade-enter-active, .danger-fade-leave-active { transition: opacity 0.3s; }
.danger-fade-enter-from, .danger-fade-leave-to { opacity: 0; }

/* ── 分割线 ── */
.divider {
  text-align: center;
  color: #666;
  font-size: 0.65rem;
  padding: 2px 0;
  background: rgba(0,0,0,0.6);
  letter-spacing: .15em;
  flex-shrink: 0;
}

/* ══ 底部操作区：flex:1 吸收剩余空间，让底部占屏幕约35-40% ══ */
.bottom-ui {
  display: flex;
  flex-direction: column;
  justify-content: center;
  background: rgba(0,0,0,0.7);
  flex: 1;
  padding: 8px 10px 12px;
  gap: 8px;
}

/* 手牌行 */
.hand-row {
  display: flex;
  align-items: center;
  gap: 5px;
}

/* 侧边圆形图标（营 / 铲子） */
.side-icon {
  width: 46px;
  height: 46px;
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  cursor: pointer;
  position: relative;
}
.ying-icon {
  background: radial-gradient(circle at 40% 35%, #c0392b, #7b241c);
  border: 2px solid #e74c3c;
  box-shadow: 0 2px 6px rgba(0,0,0,0.5);
}
.shovel-icon {
  background: radial-gradient(circle at 40% 35%, #d4ac0d, #9a7a00);
  border: 2px solid #f1c40f;
  box-shadow: 0 2px 6px rgba(0,0,0,0.5);
}
.side-icon-char {
  font-size: 1.3rem;
  font-weight: bold;
  color: #fff;
  line-height: 1;
}
.side-icon-sub {
  font-size: 0.55rem;
  color: rgba(255,255,255,0.85);
  line-height: 1;
}

/* 手牌 */
.hand-cards {
  display: flex;
  flex: 1;
  gap: 4px;
}

.card {
  flex: 1;
  aspect-ratio: 0.72;
  background: #f5f0e0;
  border: 1.5px solid #bbb;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: grab;
  position: relative;
  min-height: 60px;
  max-height: 100px;
}
.card.empty { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.15); }
.card.selected { border-color: #ffd700; background: #fff8d0; }
.card:not(.empty):hover { border-color: #999; }

.card-char { font-size: 1.2rem; font-weight: bold; }
.card-lv {
  position: absolute;
  top: 2px; right: 4px;
  font-size: 0.45rem; color: #aaa;
}

/* 征兵按钮行 */
.recruit-row {
  display: flex;
  justify-content: center;
}

.recruit-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 24px;
  background: linear-gradient(135deg, #6b3010, #3d1a04);
  border: 2px solid #c8960c;
  border-radius: 20px;
  color: white;
  cursor: pointer;
  font-family: inherit;
  font-size: 0.95rem;
  font-weight: bold;
  min-width: 130px;
  justify-content: center;
}
.recruit-btn.disabled { opacity: 0.4; cursor: not-allowed; }
.recruit-btn.ready {
  animation: recruitGlow 1.2s ease-in-out infinite alternate;
}
@keyframes recruitGlow {
  from { box-shadow: 0 0 4px #c8960c; border-color: #c8960c; }
  to   { box-shadow: 0 0 14px #ffd700, 0 0 4px #fff; border-color: #ffd700; }
}
.cost { font-size: 0.8rem; color: #ffd700; }

/* 弹窗 */
.popup-mask {
  position: absolute; inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex; align-items: center; justify-content: center;
  z-index: 100;
}
.popup {
  background: #1a1a1a;
  border: 2px solid #c8960c;
  border-radius: 8px;
  padding: 12px;
  display: flex; gap: 10px; align-items: center;
  position: relative; min-width: 190px;
}
.popup-char {
  font-size: 2rem; font-weight: bold;
  background: #f5f0e0;
  border: 2px solid #c8960c; border-radius: 4px;
  width: 50px; height: 50px;
  display: flex; align-items: center; justify-content: center;
}
.popup-info { flex: 1; color: white; }
.popup-name { font-size: 0.9rem; color: #ffd700; font-weight: bold; }
.popup-stats { font-size: 0.72rem; color: #ccc; margin-top: 4px; }
.popup-x {
  position: absolute; top: 4px; right: 6px;
  background: none; border: none; color: #aaa; cursor: pointer;
}
</style>
