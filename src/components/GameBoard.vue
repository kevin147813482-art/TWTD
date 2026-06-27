<template>
  <div class="game-board">
    <!-- 顶部信息栏 -->
    <div class="top-bar">
      <div class="wave-display">第{{ store.wave }}波</div>
      <div v-if="store.bossWarning" class="boss-tag">⚠ BOSS來襲</div>
    </div>

    <!-- AI区域（上半区）：蔣在左上，营在右上 -->
    <div class="battle-section ai-section">
      <!-- 蔣（左上） -->
      <div class="jiang ai-jiang">
        <div class="jiang-hp-row">
          <span v-for="i in store.aiJiangMaxHp" :key="i"
            :class="['hp-dot', i <= store.aiJiangHp ? 'alive' : 'dead']">♥</span>
        </div>
        <div class="jiang-char">蔣</div>
        <div class="jiang-label">AI</div>
      </div>

      <!-- 棋盘格子 -->
      <div class="grid-area">
        <div v-for="(row, ri) in store.aiBoard" :key="ri" class="board-row">
          <div v-for="(cell, ci) in row" :key="ci"
            class="board-cell"
            :class="{ unlocked: cell.unlocked, locked: !cell.unlocked }">
            <div v-if="cell.unit" class="unit-tile"
              :class="[`utype-${cell.unit.type}`, { attacking: cell.unit.attacking }]">
              {{ getUnitDisplay(cell.unit) }}
              <span v-if="cell.unit.level > 1" class="lv">{{ cell.unit.level }}</span>
            </div>
            <div v-else-if="!cell.unlocked" class="lock-icon">+</div>
          </div>
        </div>

        <!-- AI敌军层 -->
        <div class="enemy-layer">
          <div v-for="enemy in store.aiEnemies" :key="enemy.id"
            class="enemy-unit"
            :class="{ 'is-boss': enemy.isBoss }"
            :style="{ ...getAIEnemyStyle(enemy.pathProgress), color: ENEMY_COLOR[enemy.key] || '#c00' }">
            {{ enemy.key }}
            <div v-if="enemy.isBoss" class="boss-hp-bar">
              <div class="boss-hp-fill" :style="{ width: (enemy.hp / enemy.maxHp * 100) + '%' }"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- 营（右上） -->
      <div class="ying ai-ying">
        <div class="ying-char">營</div>
        <div class="ai-score-val">{{ store.aiScore }}</div>
      </div>
    </div>

    <!-- 分割线 -->
    <div class="divider">
      <span class="divider-text">── 對決 ──</span>
    </div>

    <!-- 玩家区域（下半区）：营在左下，蔣在右下 -->
    <div class="battle-section player-section">
      <!-- 营（左下） -->
      <div class="ying player-ying">
        <div class="ying-char">營</div>
        <div class="player-score-val">{{ store.playerScore }}</div>
      </div>

      <!-- 棋盘格子 -->
      <div class="grid-area"
        @dragover.prevent
        @drop.self="onDrop(-1, -1)">
        <div v-for="(row, ri) in store.playerBoard" :key="ri" class="board-row">
          <div v-for="(cell, ci) in row" :key="ci"
            class="board-cell"
            :class="{
              unlocked: cell.unlocked,
              locked: !cell.unlocked,
              'drag-over': dragOver === `${ri}-${ci}`
            }"
            @dragover.prevent="dragOver = `${ri}-${ci}`"
            @dragleave="dragOver = null"
            @drop="onDrop(ri, ci)"
            @click="onCellClick(ri, ci)">
            <div v-if="cell.unit" class="unit-tile"
              :class="[`utype-${cell.unit.type}`, { attacking: cell.unit.attacking }]"
              @click.stop="showInfo(cell.unit)">
              {{ getUnitDisplay(cell.unit) }}
              <span v-if="cell.unit.level > 1" class="lv">{{ cell.unit.level }}</span>
            </div>
            <div v-else-if="!cell.unlocked" class="lock-icon">+</div>
          </div>
        </div>

        <!-- 玩家敌军层 -->
        <div class="enemy-layer">
          <div v-for="enemy in store.playerEnemies" :key="enemy.id"
            class="enemy-unit"
            :class="{ 'is-boss': enemy.isBoss }"
            :style="{ ...getPlayerEnemyStyle(enemy.pathProgress), color: ENEMY_COLOR[enemy.key] || '#c00' }">
            {{ enemy.key }}
            <div v-if="enemy.isBoss" class="boss-hp-bar">
              <div class="boss-hp-fill" :style="{ width: (enemy.hp / enemy.maxHp * 100) + '%' }"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- 蔣（右下） -->
      <div class="jiang player-jiang" :class="{ damaged: jiangDamaged }">
        <div class="jiang-hp-row">
          <span v-for="i in store.playerJiangMaxHp" :key="i"
            :class="['hp-dot', i <= store.playerJiangHp ? 'alive' : 'dead']">♥</span>
        </div>
        <div class="jiang-char">蔣</div>
      </div>
    </div>

    <!-- 手牌区 -->
    <div class="hand-area">
      <div class="hand-cards">
        <div v-for="(card, i) in store.playerHand" :key="i"
          class="hand-card"
          :class="{ empty: !card, selected: selectedCard === i }"
          draggable="true"
          @dragstart="dragging = i"
          @dragend="dragging = null"
          @click="onCardClick(i)">
          <div v-if="card" class="card-inner" :style="getCardStyle(card)">
            {{ card.key }}
            <span v-if="card.level" class="card-lv">{{ card.level }}</span>
          </div>
        </div>
      </div>
      <button class="recruit-btn"
        :class="{ disabled: !store.canPlayerRecruit }"
        @click="store.playerRecruit()">
        <span class="recruit-label">征兵</span>
        <span class="recruit-cost">🍞{{ store.playerRecruitCost }}</span>
      </button>
    </div>

    <!-- 粮食显示 -->
    <div class="food-bar">
      <span class="food-icon">🍞</span>
      <span class="food-val">{{ store.playerFood }}</span>
    </div>

    <!-- 单位信息弹窗 -->
    <div v-if="infoUnit" class="info-popup" @click="infoUnit = null">
      <div class="popup-box" @click.stop>
        <div class="popup-char" :style="getUnitStyleObj(infoUnit)">{{ getUnitDisplay(infoUnit) }}</div>
        <div class="popup-detail">
          <div class="popup-name">{{ getUnitName(infoUnit) }}</div>
          <div class="popup-stats">攻{{ getAtk(infoUnit).toFixed(0) }} 速{{ getSpd(infoUnit).toFixed(1) }} Lv{{ infoUnit.level }}</div>
        </div>
        <button @click="infoUnit = null" class="popup-close">✕</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { gameStore as store } from '../stores/gameStore.js'
import { getPlayerEnemyStyle, getAIEnemyStyle } from '../game/engine.js'
import { BASIC_UNITS, GENERALS, GAME_CONFIG } from '../game/config.js'

const dragging = ref(null)
const dragOver = ref(null)
const selectedCard = ref(null)
const infoUnit = ref(null)
const jiangDamaged = ref(false)

// 蔣受伤闪烁效果
watch(() => store.playerJiangHp, () => {
  jiangDamaged.value = true
  setTimeout(() => { jiangDamaged.value = false }, 400)
})

const ENEMY_COLOR = {
  匪: '#555', 共: '#1a237e', 赤: '#c62828', 寇: '#4e342e',
}

function getUnitDisplay(unit) {
  if (unit.type === 'general') return unit.key
  if (unit.type === 'general_char') return unit.char
  return unit.key
}

function getUnitName(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.fullName || unit.key
  if (unit.type === 'general_char') return `${unit.char}（武將字）`
  return BASIC_UNITS[unit.key]?.name || unit.key
}

function getAtk(unit) {
  const base = unit.type === 'general' ? GENERALS[unit.key]?.atk || 6 : BASIC_UNITS[unit.key]?.atk || 2
  return base + (unit.level - 1) * 1.5
}

function getSpd(unit) {
  return unit.type === 'general' ? GENERALS[unit.key]?.atkSpeed || 1.5 : BASIC_UNITS[unit.key]?.atkSpeed || 1.5
}

function getCardStyle(card) {
  if (card.type === 'general' || card.type === 'general_char') return { color: '#c8960c', fontWeight: 'bold' }
  if (card.type === 'shovel') return { color: '#8b4513' }
  return { color: '#222' }
}

function getUnitStyleObj(unit) {
  if (unit.type === 'general') return { color: '#c8960c' }
  if (unit.type === 'general_char') return { color: '#9c6b00', fontStyle: 'italic' }
  return { color: '#222' }
}

function onCardClick(i) {
  selectedCard.value = selectedCard.value === i ? null : i
}

function onCellClick(row, col) {
  if (selectedCard.value === null) return
  const card = store.playerHand[selectedCard.value]
  if (!card) { selectedCard.value = null; return }

  if (card.type === 'shovel') {
    store.openCell(selectedCard.value, row, col)
  } else {
    store.deployUnit(selectedCard.value, row, col)
  }
  selectedCard.value = null
}

function onDrop(row, col) {
  dragOver.value = null
  if (dragging.value === null) return
  if (row === -1) { dragging.value = null; return }
  const card = store.playerHand[dragging.value]
  if (!card) { dragging.value = null; return }

  if (card.type === 'shovel') {
    store.openCell(dragging.value, row, col)
  } else {
    store.deployUnit(dragging.value, row, col)
  }
  dragging.value = null
}

function showInfo(unit) {
  infoUnit.value = unit
}
</script>

<style scoped>
.game-board {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #2a1f1a;
  position: relative;
  font-family: 'Noto Serif TC', serif;
  overflow: hidden;
}

/* 顶部信息栏 */
.top-bar {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 4px 8px;
  background: rgba(0,0,0,0.7);
  color: #ffd700;
  font-size: 0.9rem;
  font-weight: bold;
  flex-shrink: 0;
  min-height: 28px;
}
.wave-display { font-size: 1rem; }
.boss-tag {
  color: #ff4444;
  animation: pulse 0.5s infinite alternate;
  font-size: 0.85rem;
}
@keyframes pulse { from { opacity: 0.7 } to { opacity: 1 } }

/* 战场区域（上下两半） */
.battle-section {
  display: flex;
  flex-direction: row;
  align-items: stretch;
  position: relative;
  flex: 1;
  min-height: 0;
}

.ai-section {
  border-bottom: none;
}

.player-section {
  border-top: none;
}

/* 蔣 */
.jiang {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4px 2px;
  background: rgba(0,0,0,0.35);
  width: 36px;
  flex-shrink: 0;
  gap: 2px;
}
.jiang-hp-row {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.hp-dot {
  font-size: 0.7rem;
  line-height: 1;
}
.hp-dot.alive { color: #e53935; }
.hp-dot.dead { color: #444; }
.jiang-char {
  font-size: 1.5rem;
  font-weight: bold;
  color: #ffd700;
  text-shadow: 0 0 6px rgba(255,215,0,0.5);
}
.jiang-label { font-size: 0.6rem; color: #aaa; }

.player-jiang.damaged .jiang-char {
  color: #ff5722;
  transform: scale(1.2);
  transition: transform 0.1s;
}

/* 营 */
.ying {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4px 2px;
  background: rgba(0,0,0,0.25);
  width: 36px;
  flex-shrink: 0;
}
.ying-char {
  font-size: 1.1rem;
  font-weight: bold;
  color: #aaa;
}
.ai-score-val, .player-score-val {
  font-size: 0.7rem;
  color: #ffd700;
}

/* 棋盘格子区域 */
.grid-area {
  flex: 1;
  display: grid;
  grid-template-rows: repeat(v-bind('GAME_CONFIG.BOARD_ROWS'), 1fr);
  position: relative;
  background: #5a7a5a;
}

.board-row {
  display: grid;
  grid-template-columns: repeat(v-bind('GAME_CONFIG.BOARD_COLS'), 1fr);
}

.board-cell {
  border: 1px solid rgba(0,0,0,0.25);
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.board-cell.unlocked {
  background: rgba(255,255,255,0.88);
}

.board-cell.locked {
  background: rgba(80,120,80,0.7);
  cursor: pointer;
}

.board-cell.drag-over {
  background: rgba(100,220,100,0.5);
  border: 2px solid #4caf50;
}

.lock-icon {
  color: rgba(255,255,255,0.3);
  font-size: 1rem;
}

/* 单位格 */
.unit-tile {
  width: 88%;
  height: 88%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f5f0e0;
  border: 2px solid #ccc;
  border-radius: 3px;
  font-size: 1.1rem;
  font-weight: bold;
  color: #222;
  cursor: pointer;
  position: relative;
  transition: border-color 0.1s, transform 0.1s;
}
.unit-tile.attacking {
  border-color: #ff5722;
  transform: scale(1.08);
}
.unit-tile.utype-general {
  border-color: #c8960c;
  background: linear-gradient(135deg, #fff8e1, #ffecb3);
  color: #c8960c;
}
.unit-tile.utype-general_char {
  border-style: dashed;
  border-color: #9c6b00;
  color: #9c6b00;
}
.lv {
  position: absolute;
  top: 1px;
  right: 2px;
  font-size: 0.5rem;
  color: #666;
  font-weight: normal;
}

/* 敌军层 */
.enemy-layer {
  position: absolute;
  inset: 0;
  pointer-events: none;
  overflow: visible;
}

.enemy-unit {
  position: absolute;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  transform: translate(-50%, -50%);
  font-size: 0.9rem;
  font-weight: bold;
  background: rgba(255,255,255,0.85);
  border: 1.5px solid currentColor;
  border-radius: 3px;
  transition: left 0.08s linear, top 0.08s linear;
}

.enemy-unit.is-boss {
  width: 36px;
  height: 36px;
  font-size: 1.2rem;
  background: rgba(255,200,200,0.9);
}

.boss-hp-bar {
  position: absolute;
  bottom: -6px;
  left: 0; right: 0;
  height: 3px;
  background: #ddd;
  border-radius: 2px;
}
.boss-hp-fill {
  height: 100%;
  background: #e53935;
  border-radius: 2px;
}

/* 分割线 */
.divider {
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0,0,0,0.6);
  color: #888;
  font-size: 0.7rem;
  padding: 2px 0;
  flex-shrink: 0;
  min-height: 16px;
}
.divider-text { letter-spacing: 0.2em; }

/* 手牌区 */
.hand-area {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 8px;
  background: rgba(0,0,0,0.6);
  flex-shrink: 0;
}

.hand-cards {
  display: flex;
  flex: 1;
  gap: 4px;
}

.hand-card {
  flex: 1;
  aspect-ratio: 0.75;
  background: rgba(255,255,255,0.12);
  border: 1.5px solid rgba(255,255,255,0.25);
  border-radius: 5px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: grab;
  min-height: 44px;
  position: relative;
}
.hand-card.selected {
  border-color: #ffd700;
  background: rgba(255,215,0,0.15);
}
.hand-card:not(.empty):hover {
  border-color: rgba(255,255,255,0.6);
}
.card-inner {
  font-size: 1.2rem;
  font-weight: bold;
  position: relative;
}
.card-lv {
  position: absolute;
  top: -8px;
  right: -8px;
  font-size: 0.5rem;
  color: #aaa;
}

/* 征兵按钮 */
.recruit-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 6px 10px;
  background: linear-gradient(135deg, #6b3010, #3d1a04);
  border: 2px solid #c8960c;
  border-radius: 6px;
  color: white;
  cursor: pointer;
  flex-shrink: 0;
  min-width: 52px;
}
.recruit-btn.disabled { opacity: 0.45; cursor: not-allowed; }
.recruit-label { font-size: 0.9rem; font-weight: bold; }
.recruit-cost { font-size: 0.75rem; color: #ffd700; }

/* 粮食显示（悬浮右上） */
.food-bar {
  position: absolute;
  top: 32px;
  right: 6px;
  background: rgba(0,0,0,0.55);
  color: white;
  border-radius: 12px;
  padding: 2px 8px;
  font-size: 0.85rem;
  display: flex;
  align-items: center;
  gap: 3px;
  pointer-events: none;
}
.food-val { color: #ffd700; font-weight: bold; }

/* 信息弹窗 */
.info-popup {
  position: absolute;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}
.popup-box {
  background: #1a1a1a;
  border: 2px solid #c8960c;
  border-radius: 8px;
  padding: 12px;
  display: flex;
  gap: 10px;
  align-items: center;
  position: relative;
  min-width: 200px;
}
.popup-char {
  font-size: 2rem;
  font-weight: bold;
  background: #f5f0e0;
  border: 2px solid #c8960c;
  border-radius: 5px;
  width: 52px;
  height: 52px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.popup-detail { flex: 1; color: white; }
.popup-name { font-size: 0.95rem; color: #ffd700; font-weight: bold; }
.popup-stats { font-size: 0.75rem; color: #ddd; margin-top: 4px; }
.popup-close {
  position: absolute;
  top: 4px; right: 6px;
  background: none; border: none;
  color: #aaa; cursor: pointer; font-size: 0.9rem;
}
</style>
