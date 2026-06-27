import { gameStore, randomHandCard } from '../stores/gameStore.js'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES, BOSSES } from './config.js'

const ROWS = GAME_CONFIG.BOARD_ROWS   // 5
const COLS = GAME_CONFIG.BOARD_COLS   // 7
const PLAYER_PATH = GAME_CONFIG.PLAYER_PATH  // 15 cells
const AI_PATH = GAME_CONFIG.AI_PATH          // 15 cells
const PATH_LEN = PLAYER_PATH.length          // 15

// ─── 敌军位置（格坐标，支持插值） ─────────────────────────────
function getPathPos(progress, path) {
  const maxIdx = path.length - 1
  const idx = Math.min(Math.floor(progress), maxIdx)
  const frac = progress - idx
  const [r0, c0] = path[idx]
  if (idx >= maxIdx) return { row: r0, col: c0 }
  const [r1, c1] = path[idx + 1]
  return { row: r0 + (r1 - r0) * frac, col: c0 + (c1 - c0) * frac }
}

// 转为格子中心的 CSS 百分比（相对于 grid-area 容器）
export function getEnemyStyle(progress, isAI) {
  const path = isAI ? AI_PATH : PLAYER_PATH
  const { row, col } = getPathPos(progress, path)
  return {
    left: `${(col + 0.5) / COLS * 100}%`,
    top:  `${(row + 0.5) / ROWS * 100}%`,
  }
}

// ─── 攻击判定 ────────────────────────────────────────────────
function getUnitRange(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.range || 2
  return BASIC_UNITS[unit.key]?.range || 1
}

function getUnitAtk(unit) {
  const base = unit.type === 'general'
    ? (GENERALS[unit.key]?.atk || 6)
    : (BASIC_UNITS[unit.key]?.atk || 2)
  return base + (unit.level - 1) * 1.5
}

function getUnitAtkSpeed(unit) {
  return unit.type === 'general'
    ? (GENERALS[unit.key]?.atkSpeed || 1.5)
    : (BASIC_UNITS[unit.key]?.atkSpeed || 1.5)
}

function getAttackType(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.attackType || 'single'
  return BASIC_UNITS[unit.key]?.attackType || 'single'
}

// unit 能否攻击到 enemy（根据路线格位置 vs 单位格位置）
function canAttack(unit, enemy, isAI) {
  const path = isAI ? AI_PATH : PLAYER_PATH
  const idx = Math.min(Math.floor(enemy.pathProgress), path.length - 1)
  const [eRow, eCol] = path[idx]
  const range = getUnitRange(unit)
  const isArea = getAttackType(unit) === 'area'
  const tol = isArea ? 1.5 : 0.6   // 同行/列容差

  // 左列路线（eCol === 0）
  if (eCol === 0) {
    return unit.col <= range && Math.abs(eRow - unit.row) < tol
  }
  // 右列路线（eCol === COLS-1）
  if (eCol === COLS - 1) {
    return (COLS - 1 - unit.col) <= range && Math.abs(eRow - unit.row) < tol
  }
  // 玩家顶行路线（eRow === 0）
  if (!isAI && eRow === 0) {
    return unit.row <= range && Math.abs(eCol - unit.col) < tol
  }
  // AI底行路线（eRow === ROWS-1）
  if (isAI && eRow === ROWS - 1) {
    return (ROWS - 1 - unit.row) <= range && Math.abs(eCol - unit.col) < tol
  }
  return false
}

// ─── 处理攻击 ────────────────────────────────────────────────
const cooldowns = new Map()

function processAttacks(board, enemies, side, now) {
  const isAI = side === 'ai'
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const unit = board[r][c].unit
      if (!unit || unit.stunned) continue

      const cd = 1000 / getUnitAtkSpeed(unit)
      const last = cooldowns.get(unit.id) || 0
      if (now - last < cd) continue

      const targets = enemies.filter(e => !e.stunned && canAttack(unit, e, isAI))
      if (targets.length === 0) continue

      cooldowns.set(unit.id, now)
      const atk = getUnitAtk(unit)
      const type = getAttackType(unit)

      if (type === 'pierce') {
        targets.forEach(t => gameStore.damageEnemy(side, t.id, atk))
      } else if (type === 'area') {
        targets.forEach(t => gameStore.damageEnemy(side, t.id, atk * 0.7))
      } else {
        const t = targets.reduce((a, b) => a.pathProgress > b.pathProgress ? a : b)
        gameStore.damageEnemy(side, t.id, atk)
      }

      unit.attacking = true
      setTimeout(() => { if (unit) unit.attacking = false }, 200)
    }
  }
}

// ─── 敌军移动 ────────────────────────────────────────────────
function moveEnemies(delta) {
  const speed = delta * 0.0015   // 速度系数

  for (let i = gameStore.playerEnemies.length - 1; i >= 0; i--) {
    const e = gameStore.playerEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * speed
    if (e.pathProgress >= PATH_LEN) {
      gameStore.playerEnemies.splice(i, 1)
      gameStore.damagePlayerJiang()
    }
  }

  for (let i = gameStore.aiEnemies.length - 1; i >= 0; i--) {
    const e = gameStore.aiEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * speed
    if (e.pathProgress >= PATH_LEN) {
      gameStore.aiEnemies.splice(i, 1)
      gameStore.damageAIJiang()
    }
  }
}

// ─── 波次 ────────────────────────────────────────────────────
function getWaveEnemies(wave) {
  const count = 3 + wave * 2
  return Array.from({ length: count }, (_, i) => {
    const r = Math.random()
    let key
    if (wave <= 3)      key = r < 0.7 ? '匪' : r < 0.9 ? '赤' : '共'
    else if (wave <= 8) key = r < 0.4 ? '匪' : r < 0.65 ? '赤' : r < 0.85 ? '共' : '寇'
    else                key = r < 0.25 ? '匪' : r < 0.5 ? '赤' : r < 0.75 ? '共' : '寇'
    return { key, delay: i * 1000 }
  })
}

let waveSpawnTimer = null

function startWave(wave) {
  const list = getWaveEnemies(wave)
  const boss = Object.values(BOSSES).find(b => b.wave === wave)
  if (boss) {
    gameStore.bossWarning = true
    setTimeout(() => { gameStore.bossWarning = false }, 3000)
  }
  let i = 0
  function spawnNext() {
    if (i >= list.length || gameStore.phase !== 'playing') return
    const e = list[i++]
    gameStore.spawnEnemy(e.key, 'player')
    gameStore.spawnEnemy(e.key, 'ai')
    waveSpawnTimer = setTimeout(spawnNext, e.delay || 1000)
  }
  spawnNext()
}

// ─── AI 自动操作 ─────────────────────────────────────────────
let aiTimer = null

function aiTick() {
  if (gameStore.phase !== 'playing') return

  const cost = GAME_CONFIG.RECRUIT_BASE_COST + gameStore.aiRecruitTimes * GAME_CONFIG.RECRUIT_COST_INCREMENT
  if (gameStore.aiFood >= cost) {
    gameStore.aiFood -= cost
    gameStore.aiRecruitTimes++
    const hand = Array.from({ length: GAME_CONFIG.HAND_SIZE }, () => randomHandCard(gameStore.wave))

    for (const card of hand) {
      if (!card || card.type === 'shovel') continue
      const empties = []
      for (let r = 0; r < ROWS; r++) {
        for (let c = 0; c < COLS; c++) {
          if (gameStore.aiBoard[r][c].kind === 'unlocked' && !gameStore.aiBoard[r][c].unit)
            empties.push([r, c])
        }
      }
      if (!empties.length) break
      // 优先边缘格（靠近路线）
      const edges = empties.filter(([r,c]) => c===1 || c===COLS-2 || r===ROWS-2)
      const pool = edges.length ? edges : empties
      const [r, c] = pool[Math.floor(Math.random() * pool.length)]
      gameStore.aiBoard[r][c].unit = {
        ...card, id: Date.now() + Math.random(),
        level: card.level || 1, exp: 0,
        row: r, col: c, attacking: false, stunned: false,
      }
      gameStore.checkMerge(gameStore.aiBoard, r, c)
    }
  }
  aiTimer = setTimeout(aiTick, 3500 + Math.random() * 3000)
}

// ─── 主循环 ──────────────────────────────────────────────────
let gameLoop = null
let waveScheduler = null
let lastTick = 0

function tick(now) {
  if (gameStore.phase !== 'playing') return
  const delta = Math.min(now - lastTick, 100)
  lastTick = now
  moveEnemies(delta)
  const t = performance.now()
  processAttacks(gameStore.playerBoard, gameStore.playerEnemies, 'player', t)
  processAttacks(gameStore.aiBoard, gameStore.aiEnemies, 'ai', t)
  gameLoop = requestAnimationFrame(tick)
}

export function startEngine() {
  lastTick = performance.now()
  gameLoop = requestAnimationFrame(tick)
  startWave(gameStore.wave)
  function scheduleNext() {
    waveScheduler = setTimeout(() => {
      if (gameStore.phase !== 'playing') return
      if (gameStore.wave >= 30) { gameStore.victory(); return }
      gameStore.nextWave()
      startWave(gameStore.wave)
      scheduleNext()
    }, GAME_CONFIG.WAVE_INTERVAL)
  }
  scheduleNext()
  aiTimer = setTimeout(aiTick, 2000)
}

export function stopEngine() {
  if (gameLoop) cancelAnimationFrame(gameLoop)
  if (waveScheduler) clearTimeout(waveScheduler)
  if (waveSpawnTimer) clearTimeout(waveSpawnTimer)
  if (aiTimer) clearTimeout(aiTimer)
  cooldowns.clear()
}
