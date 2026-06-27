import { gameStore, randomHandCard } from '../stores/gameStore.js'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES, BOSSES } from './config.js'

const ROWS = GAME_CONFIG.BOARD_ROWS  // 4
const COLS = GAME_CONFIG.BOARD_COLS  // 5

// 路径段长度（格子单位）
// 玩家路线: 左边↑ → 顶部→ → 右边↓
// AI路线:   右边↓ → 底部← → 左边↑
const SEG1 = ROWS  // 4
const SEG2 = COLS  // 5
const SEG3 = ROWS  // 4
const TOTAL = SEG1 + SEG2 + SEG3  // 13

// ─── CSS位置计算 ──────────────────────────────────────────
// 玩家区域：营在左下，蔣在右下
// 路径 CSS 锚点（百分比，相对于各自区域）
const PL = { xL: 7, xR: 93, yT: 5, yB: 85 }  // 玩家
const AI = { xL: 7, xR: 93, yT: 15, yB: 95 }  // AI

export function getPlayerEnemyStyle(progress) {
  let left, top
  if (progress < SEG1) {
    const t = progress / SEG1
    left = PL.xL
    top = PL.yB - (PL.yB - PL.yT) * t      // UP left
  } else if (progress < SEG1 + SEG2) {
    const t = (progress - SEG1) / SEG2
    left = PL.xL + (PL.xR - PL.xL) * t     // RIGHT top
    top = PL.yT
  } else {
    const t = (progress - SEG1 - SEG2) / SEG3
    left = PL.xR
    top = PL.yT + (PL.yB - PL.yT) * t      // DOWN right
  }
  return { left: left + '%', top: top + '%' }
}

export function getAIEnemyStyle(progress) {
  let left, top
  if (progress < SEG1) {
    const t = progress / SEG1
    left = AI.xR
    top = AI.yT + (AI.yB - AI.yT) * t      // DOWN right
  } else if (progress < SEG1 + SEG2) {
    const t = (progress - SEG1) / SEG2
    left = AI.xR - (AI.xR - AI.xL) * t     // LEFT bottom
    top = AI.yB
  } else {
    const t = (progress - SEG1 - SEG2) / SEG3
    left = AI.xL
    top = AI.yB - (AI.yB - AI.yT) * t      // UP left
  }
  return { left: left + '%', top: top + '%' }
}

// ─── 攻击范围计算 ──────────────────────────────────────────
// 玩家路线: SEG1=左边(gy降序), SEG2=顶部(gx升序), SEG3=右边(gy升序)
function getPlayerLane(progress) {
  if (progress < SEG1) {
    return { lane: 'left', pos: ROWS - 1 - progress }       // gy 从 3→0
  } else if (progress < SEG1 + SEG2) {
    return { lane: 'top', pos: progress - SEG1 }             // gx 从 0→4
  } else {
    return { lane: 'right', pos: progress - SEG1 - SEG2 }   // gy 从 0→3
  }
}

// AI路线: SEG1=右边(gy升序), SEG2=底部(gx降序), SEG3=左边(gy降序)
function getAILane(progress) {
  if (progress < SEG1) {
    return { lane: 'right', pos: progress }                        // gy 从 0→3
  } else if (progress < SEG1 + SEG2) {
    return { lane: 'bottom', pos: COLS - 1 - (progress - SEG1) }  // gx 从 4→0
  } else {
    return { lane: 'left', pos: ROWS - 1 - (progress - SEG1 - SEG2) } // gy 从 3→0
  }
}

function getUnitRange(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.range || 2
  return BASIC_UNITS[unit.key]?.range || 1
}

function getUnitAtk(unit) {
  const base = unit.type === 'general'
    ? GENERALS[unit.key]?.atk || 6
    : (BASIC_UNITS[unit.key]?.atk || 2)
  return base + (unit.level - 1) * 1.5
}

function getUnitAtkSpeed(unit) {
  return unit.type === 'general'
    ? GENERALS[unit.key]?.atkSpeed || 1.5
    : (BASIC_UNITS[unit.key]?.atkSpeed || 1.5)
}

function getAttackType(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.attackType || 'single'
  return BASIC_UNITS[unit.key]?.attackType || 'single'
}

function canPlayerUnitAttack(unit, enemy) {
  const info = getPlayerLane(enemy.pathProgress)
  const range = getUnitRange(unit)
  const isArea = getAttackType(unit) === 'area'
  const tolerance = isArea ? 1.5 : 0.6

  if (info.lane === 'left') {
    // 敌在左边, gx=-1, gy=info.pos. 单位需 col+1 <= range, row≈gy
    return (unit.col + 1) <= range && Math.abs(info.pos - unit.row) < tolerance
  } else if (info.lane === 'top') {
    // 敌在顶部, gy=-1, gx=info.pos. 单位需 row+1 <= range, col≈gx
    return (unit.row + 1) <= range && Math.abs(info.pos - unit.col) < tolerance
  } else {
    // 敌在右边, gx=COLS, gy=info.pos. 单位需 COLS-col <= range, row≈gy
    return (COLS - unit.col) <= range && Math.abs(info.pos - unit.row) < tolerance
  }
}

function canAIUnitAttack(unit, enemy) {
  const info = getAILane(enemy.pathProgress)
  const range = getUnitRange(unit)
  const isArea = getAttackType(unit) === 'area'
  const tolerance = isArea ? 1.5 : 0.6

  if (info.lane === 'right') {
    return (COLS - unit.col) <= range && Math.abs(info.pos - unit.row) < tolerance
  } else if (info.lane === 'bottom') {
    return (ROWS - unit.row) <= range && Math.abs(info.pos - unit.col) < tolerance
  } else {
    return (unit.col + 1) <= range && Math.abs(info.pos - unit.row) < tolerance
  }
}

// ─── 攻击处理 ──────────────────────────────────────────────
const attackCooldowns = new Map()

function processAttacks(board, enemies, side, now) {
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const unit = board[r][c].unit
      if (!unit || unit.stunned) continue

      const cooldown = 1000 / getUnitAtkSpeed(unit)
      const last = attackCooldowns.get(unit.id) || 0
      if (now - last < cooldown) continue

      const canAttack = side === 'player' ? canPlayerUnitAttack : canAIUnitAttack
      const targets = enemies.filter(e => !e.stunned && canAttack(unit, e))
      if (targets.length === 0) continue

      attackCooldowns.set(unit.id, now)
      const atk = getUnitAtk(unit)
      const type = getAttackType(unit)

      if (type === 'pierce' || type === 'area') {
        const dmg = type === 'area' ? atk * 0.7 : atk
        targets.forEach(t => gameStore.damageEnemy(side, t.id, dmg))
      } else {
        // single: 攻击进度最大的敌人（最接近蔣）
        const target = targets.reduce((a, b) => a.pathProgress > b.pathProgress ? a : b)
        gameStore.damageEnemy(side, target.id, atk)
      }

      unit.attacking = true
      setTimeout(() => { if (unit) unit.attacking = false }, 200)
    }
  }
}

// ─── 敌军移动 ──────────────────────────────────────────────
function moveEnemies(delta) {
  for (let i = gameStore.playerEnemies.length - 1; i >= 0; i--) {
    const e = gameStore.playerEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * delta * 0.002
    if (e.pathProgress >= TOTAL) {
      gameStore.playerEnemies.splice(i, 1)
      gameStore.damagePlayerJiang()
    }
  }
  for (let i = gameStore.aiEnemies.length - 1; i >= 0; i--) {
    const e = gameStore.aiEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * delta * 0.002
    if (e.pathProgress >= TOTAL) {
      gameStore.aiEnemies.splice(i, 1)
      gameStore.damageAIJiang()
    }
  }
}

// ─── 波次生成 ──────────────────────────────────────────────
function getWaveEnemies(wave) {
  const count = 3 + wave * 2
  const list = []
  for (let i = 0; i < count; i++) {
    const r = Math.random()
    let key
    if (wave <= 3) {
      key = r < 0.7 ? '匪' : r < 0.9 ? '赤' : '共'
    } else if (wave <= 8) {
      key = r < 0.4 ? '匪' : r < 0.65 ? '赤' : r < 0.85 ? '共' : '寇'
    } else {
      key = r < 0.25 ? '匪' : r < 0.5 ? '赤' : r < 0.75 ? '共' : '寇'
    }
    list.push({ key, delay: i * 1000 })
  }
  return list
}

let waveSpawnTimer = null

function startWave(wave) {
  const enemies = getWaveEnemies(wave)

  const boss = Object.values(BOSSES).find(b => b.wave === wave)
  if (boss) {
    gameStore.bossWarning = true
    setTimeout(() => { gameStore.bossWarning = false }, 3000)
  }

  let i = 0
  function spawnNext() {
    if (i >= enemies.length || gameStore.phase !== 'playing') return
    const e = enemies[i++]
    gameStore.spawnEnemy(e.key, 'player')
    gameStore.spawnEnemy(e.key, 'ai')
    waveSpawnTimer = setTimeout(spawnNext, e.delay || 1000)
  }
  spawnNext()
}

// ─── AI自动操作 ────────────────────────────────────────────
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

      // 优先填边缘格（靠近路线）
      const emptyCells = []
      for (let r = 0; r < ROWS; r++) {
        for (let c = 0; c < COLS; c++) {
          const cell = gameStore.aiBoard[r][c]
          if (cell.unlocked && !cell.unit) emptyCells.push([r, c])
        }
      }
      if (emptyCells.length === 0) break

      const edgeCells = emptyCells.filter(([r, c]) =>
        c === 0 || c === COLS - 1 || r === 0 || r === ROWS - 1
      )
      const pool = edgeCells.length > 0 ? edgeCells : emptyCells
      const [r, c] = pool[Math.floor(Math.random() * pool.length)]

      gameStore.aiBoard[r][c].unit = {
        ...card,
        id: Date.now() + Math.random(),
        level: card.level || 1,
        exp: 0, row: r, col: c,
        attacking: false, stunned: false,
      }
      gameStore.checkMerge(gameStore.aiBoard, r, c)
    }
  }

  aiTimer = setTimeout(aiTick, 3000 + Math.random() * 3000)
}

// ─── 主循环 ────────────────────────────────────────────────
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
  attackCooldowns.clear()
}
