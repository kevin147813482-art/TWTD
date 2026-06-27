<template>
  <div class="game-board">
    <!-- 顶部信息栏 -->
    <div class="top-bar">
      <div class="food-display">
        <span class="food-icon">🍞</span>
        <span>{{ store.food }}</span>
      </div>
      <div class="wave-display">第{{ store.wave }}波</div>
      <div class="score-display">
        <span>擊殺: {{ store.score }}</span>
      </div>
    </div>

    <!-- BOSS警告 -->
    <div v-if="store.bossWarning" class="boss-warning">
      ⚠️ 警告 ⚠️ 敵軍首領來襲！⚠️ 警告 ⚠️
    </div>

    <!-- 战场区域 -->
    <div class="battlefield">
      <!-- 蔣（左侧） -->
      <div class="jiang-side">
        <div class="jiang-hp">
          <span v-for="i in store.jiangMaxHp" :key="i"
            :class="['hp-heart', i <= store.jiangHp ? 'alive' : 'dead']">❤</span>
        </div>
        <div class="jiang-char" :class="{ damaged: jiangDamaged }">蔣</div>
      </div>

      <!-- 棋盘格子 -->
      <div class="board-grid">
        <div
          v-for="(row, ri) in store.board"
          :key="ri"
          class="board-row"
        >
          <div
            v-for="(cell, ci) in row"
            :key="ci"
            class="board-cell"
            :class="{
              unlocked: cell.unlocked,
              locked: !cell.unlocked,
              'has-unit': cell.unit,
              'drag-over': dragOver === `${ri}-${ci}`
            }"
            @dragover.prevent="dragOver = `${ri}-${ci}`"
            @dragleave="dragOver = null"
            @drop="onDrop(ri, ci)"
            @click="onCellClick(ri, ci)"
          >
            <div v-if="cell.unit" class="unit-tile"
              :class="[`unit-type-${cell.unit.type}`, { attacking: cell.unit.attacking, stunned: cell.unit.stunned }]"
              :style="getUnitStyle(cell.unit)"
              @click.stop="showUnitInfo(cell.unit)"
            >
              <div class="unit-char">{{ getUnitDisplay(cell.unit) }}</div>
              <div v-if="cell.unit.level > 1" class="unit-level">{{ cell.unit.level }}</div>
            </div>
            <div v-else-if="!cell.unlocked" class="lock-icon">+</div>
          </div>
        </div>

        <!-- 敌军层 -->
        <div class="enemy-layer">
          <div
            v-for="enemy in store.enemies"
            :key="enemy.id"
            class="enemy-unit"
            :class="{ 'is-boss': enemy.isBoss }"
            :style="getEnemyStyle(enemy)"
          >
            <div class="enemy-char">{{ enemy.key }}</div>
            <div v-if="enemy.isBoss" class="enemy-hp-bar">
              <div class="enemy-hp-fill" :style="{ width: (enemy.hp / enemy.maxHp * 100) + '%' }"></div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 手牌区 -->
    <div class="hand-area">
      <div class="camp-label">營</div>
      <div class="hand-cards">
        <div
          v-for="(card, i) in store.hand"
          :key="i"
          class="hand-card"
          :class="{ empty: !card, dragging: draggingIndex === i }"
          draggable="true"
          @dragstart="onDragStart(i)"
          @dragend="onDragEnd"
          @click="onCardClick(i)"
        >
          <div v-if="card" class="card-content">
            <div class="card-char" :style="getCardStyle(card)">{{ card.key }}</div>
            <div v-if="card.level" class="card-level">{{ card.level }}</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 征兵按钮 -->
    <button
      class="recruit-btn"
      :class="{ disabled: !store.canRecruit }"
      @click="recruit"
    >
      <div class="recruit-label">征兵</div>
      <div class="recruit-cost">
        <span class="food-icon">🍞</span>{{ store.recruitCost }}
      </div>
    </button>

    <!-- 单位信息弹窗 -->
    <div v-if="selectedUnit" class="unit-popup" @click="selectedUnit = null">
      <div class="popup-content" @click.stop>
        <div class="popup-char" :style="getUnitStyle(selectedUnit)">{{ getUnitDisplay(selectedUnit) }}</div>
        <div class="popup-info">
          <div class="popup-name">{{ getUnitFullName(selectedUnit) }}</div>
          <div class="popup-stats">
            <span>攻擊: {{ getUnitAtk(selectedUnit).toFixed(1) }}</span>
            <span>攻速: {{ getUnitSpeed(selectedUnit).toFixed(2) }}</span>
          </div>
          <div class="popup-level">等級 {{ selectedUnit.level }}/{{ getMaxLevel(selectedUnit) }}</div>
        </div>
        <button class="popup-close" @click="selectedUnit = null">✕</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { gameStore as store } from '../stores/gameStore.js'
import { BASIC_UNITS, GENERALS, GAME_CONFIG } from '../game/config.js'

const draggingIndex = ref(null)
const dragOver = ref(null)
const selectedUnit = ref(null)
const jiangDamaged = ref(false)
const selectedCardIndex = ref(null)

function onDragStart(i) {
  draggingIndex.value = i
}

function onDragEnd() {
  draggingIndex.value = null
  dragOver.value = null
}

function onDrop(row, col) {
  dragOver.value = null
  if (draggingIndex.value === null) return
  const card = store.hand[draggingIndex.value]
  if (!card) return

  if (card.type === 'shovel') {
    store.useShovelItem(row, col) || (() => {
      // 用手牌铲子
      const cell = store.board[row][col]
      if (!cell.unlocked) {
        cell.unlocked = true
        store.hand[draggingIndex.value] = null
      }
    })()
  } else {
    store.deployUnit(draggingIndex.value, row, col)
  }
  draggingIndex.value = null
}

function onCardClick(i) {
  selectedCardIndex.value = selectedCardIndex.value === i ? null : i
}

function onCellClick(row, col) {
  if (selectedCardIndex.value === null) return
  const card = store.hand[selectedCardIndex.value]
  if (!card) return

  if (card.type === 'shovel') {
    const cell = store.board[row][col]
    if (!cell.unlocked) {
      cell.unlocked = true
      store.hand[selectedCardIndex.value] = null
    }
  } else {
    store.deployUnit(selectedCardIndex.value, row, col)
  }
  selectedCardIndex.value = null
}

function recruit() {
  store.recruit()
}

function showUnitInfo(unit) {
  selectedUnit.value = unit
}

function getUnitDisplay(unit) {
  if (unit.type === 'general') return unit.key
  if (unit.type === 'general_char') return unit.char
  return unit.key
}

function getUnitFullName(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.fullName || unit.key
  if (unit.type === 'general_char') return `${unit.char}（武將字）`
  return BASIC_UNITS[unit.key]?.name || unit.key
}

function getUnitAtk(unit) {
  const base = unit.type === 'general'
    ? GENERALS[unit.key]?.atk || 6
    : (BASIC_UNITS[unit.key]?.atk || 2)
  return base + (unit.level - 1) * 1.5
}

function getUnitSpeed(unit) {
  return unit.type === 'general'
    ? GENERALS[unit.key]?.atkSpeed || 1.5
    : (BASIC_UNITS[unit.key]?.atkSpeed || 1.5)
}

function getMaxLevel(unit) {
  if (unit.type === 'general') return 3
  return BASIC_UNITS[unit.key]?.maxLevel || 5
}

function getUnitStyle(unit) {
  if (unit.type === 'general') return { color: '#c8960c', fontWeight: 'bold' }
  if (unit.type === 'general_char') return { color: '#9c6b00', fontStyle: 'italic' }
  return { color: '#222' }
}

function getCardStyle(card) {
  if (card.type === 'general' || card.type === 'general_char') return { color: '#c8960c', fontWeight: 'bold' }
  if (card.type === 'shovel') return { color: '#8b4513' }
  return { color: '#222' }
}

function getEnemyStyle(enemy) {
  const cellW = 100 / GAME_CONFIG.BOARD_COLS
  const cellH = 100 / GAME_CONFIG.BOARD_ROWS
  return {
    left: `${enemy.x * cellW}%`,
    top: `${enemy.row * cellH}%`,
    width: `${cellW}%`,
    height: `${cellH}%`,
    color: enemy.isBoss ? '#b71c1c' : ENEMY_COLOR[enemy.key] || '#333',
    fontSize: enemy.isBoss ? '1.6rem' : '1.1rem',
  }
}

const ENEMY_COLOR = {
  匪: '#444',
  共: '#1a237e',
  赤: '#c62828',
  寇: '#4e342e',
}
</script>

<style scoped>
.game-board {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #8b7355;
  position: relative;
  overflow: hidden;
}

.top-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 12px;
  background: rgba(0,0,0,0.6);
  color: white;
  font-size: 0.9rem;
}

.food-display {
  display: flex;
  align-items: center;
  gap: 4px;
  background: rgba(255,255,255,0.1);
  padding: 2px 8px;
  border-radius: 12px;
}

.wave-display {
  font-size: 1.1rem;
  font-weight: bold;
  color: #ffd700;
}

.boss-warning {
  background: repeating-linear-gradient(45deg, #f9a825, #f9a825 10px, #212121 10px, #212121 20px);
  color: #fff;
  font-weight: bold;
  text-align: center;
  padding: 6px;
  font-size: 0.85rem;
  animation: pulse 0.5s infinite alternate;
}

@keyframes pulse {
  from { opacity: 0.8; }
  to { opacity: 1; }
}

.battlefield {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.jiang-side {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4px;
  background: rgba(0,0,0,0.2);
  min-width: 48px;
}

.jiang-hp {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 4px;
}

.hp-heart {
  font-size: 1rem;
}
.hp-heart.alive { color: #e53935; }
.hp-heart.dead { color: #555; }

.jiang-char {
  font-size: 2rem;
  font-weight: bold;
  color: #ffd700;
  text-shadow: 0 0 8px rgba(255,215,0,0.6);
  transition: transform 0.1s;
}
.jiang-char.damaged {
  transform: scale(1.3);
  color: #ff5722;
}

.board-grid {
  flex: 1;
  display: grid;
  grid-template-rows: repeat(v-bind('GAME_CONFIG.BOARD_ROWS'), 1fr);
  position: relative;
}

.board-row {
  display: grid;
  grid-template-columns: repeat(v-bind('GAME_CONFIG.BOARD_COLS'), 1fr);
}

.board-cell {
  border: 1px solid rgba(0,0,0,0.2);
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 60px;
}

.board-cell.unlocked {
  background: rgba(255,255,255,0.85);
}

.board-cell.locked {
  background: rgba(100,80,60,0.6);
  cursor: pointer;
}

.board-cell.drag-over {
  background: rgba(100,200,100,0.4);
  border: 2px solid #4caf50;
}

.lock-icon {
  color: rgba(255,255,255,0.4);
  font-size: 1.2rem;
}

.unit-tile {
  width: 90%;
  height: 90%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: #f5f0e0;
  border: 2px solid #ccc;
  border-radius: 4px;
  cursor: pointer;
  position: relative;
  transition: transform 0.1s;
}

.unit-tile.attacking {
  transform: scale(1.1);
  border-color: #ff5722;
}

.unit-tile.stunned {
  opacity: 0.5;
}

.unit-type-general {
  border-color: #c8960c;
  background: linear-gradient(135deg, #fff8e1, #ffecb3);
  box-shadow: 0 0 6px rgba(200,150,12,0.4);
}

.unit-type-general_char {
  border-color: #9c6b00;
  border-style: dashed;
  background: #fff8e1;
}

.unit-char {
  font-size: 1.3rem;
  font-weight: bold;
  line-height: 1;
}

.unit-level {
  position: absolute;
  top: 1px;
  right: 3px;
  font-size: 0.6rem;
  color: #666;
}

/* 敌军层 */
.enemy-layer {
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.enemy-unit {
  position: absolute;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  transition: left 0.1s linear;
}

.enemy-char {
  font-size: 1.1rem;
  font-weight: bold;
  background: rgba(255,255,255,0.8);
  border: 1.5px solid currentColor;
  border-radius: 3px;
  width: 80%;
  height: 70%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.enemy-unit.is-boss .enemy-char {
  font-size: 1.6rem;
  border-width: 2.5px;
  background: rgba(255,200,200,0.9);
}

.enemy-hp-bar {
  width: 80%;
  height: 4px;
  background: #ddd;
  border-radius: 2px;
  margin-top: 2px;
}

.enemy-hp-fill {
  height: 100%;
  background: #e53935;
  border-radius: 2px;
  transition: width 0.2s;
}

/* 手牌区 */
.hand-area {
  display: flex;
  align-items: center;
  background: rgba(0,0,0,0.5);
  padding: 6px 8px;
  gap: 6px;
}

.camp-label {
  color: #ffd700;
  font-size: 1rem;
  font-weight: bold;
  min-width: 24px;
}

.hand-cards {
  display: flex;
  flex: 1;
  gap: 4px;
}

.hand-card {
  flex: 1;
  aspect-ratio: 1;
  background: rgba(255,255,255,0.15);
  border: 1.5px solid rgba(255,255,255,0.3);
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: grab;
  min-height: 48px;
}

.hand-card:not(.empty):hover {
  background: rgba(255,255,255,0.25);
  border-color: #ffd700;
}

.hand-card.dragging {
  opacity: 0.5;
}

.card-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  position: relative;
  width: 100%;
  height: 100%;
  justify-content: center;
}

.card-char {
  font-size: 1.3rem;
  font-weight: bold;
}

.card-level {
  position: absolute;
  top: 2px;
  right: 4px;
  font-size: 0.6rem;
  color: rgba(255,255,255,0.7);
}

/* 征兵按钮 */
.recruit-btn {
  margin: 6px auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 8px 40px;
  background: linear-gradient(135deg, #8b4513, #5c2d0a);
  border: 2px solid #c8960c;
  border-radius: 8px;
  color: white;
  cursor: pointer;
  width: 60%;
}

.recruit-btn.disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.recruit-label {
  font-size: 1.1rem;
  font-weight: bold;
  letter-spacing: 0.1em;
}

.recruit-cost {
  font-size: 0.85rem;
  color: #ffd700;
  display: flex;
  align-items: center;
  gap: 2px;
}

/* 单位弹窗 */
.unit-popup {
  position: absolute;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.popup-content {
  background: #1a1a1a;
  border: 2px solid #c8960c;
  border-radius: 10px;
  padding: 16px;
  display: flex;
  gap: 12px;
  align-items: center;
  max-width: 280px;
  position: relative;
}

.popup-char {
  font-size: 2.5rem;
  font-weight: bold;
  background: #f5f0e0;
  border: 2px solid #c8960c;
  border-radius: 6px;
  width: 60px;
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.popup-info {
  flex: 1;
  color: white;
}

.popup-name {
  font-size: 1rem;
  font-weight: bold;
  color: #ffd700;
  margin-bottom: 4px;
}

.popup-stats {
  display: flex;
  gap: 8px;
  font-size: 0.8rem;
  color: #ddd;
}

.popup-level {
  font-size: 0.75rem;
  color: #aaa;
  margin-top: 4px;
}

.popup-close {
  position: absolute;
  top: 6px;
  right: 8px;
  background: none;
  border: none;
  color: #aaa;
  cursor: pointer;
  font-size: 1rem;
}
</style>
