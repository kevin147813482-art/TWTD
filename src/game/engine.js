import { gameStore, randomHandCard } from '../stores/gameStore.js'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES, BOSSES } from './config.js'

const ROWS = GAME_CONFIG.BOARD_ROWS   // 5
const COLS = GAME_CONFIG.BOARD_COLS   // 8
const PLAYER_PATH = GAME_CONFIG.PLAYER_PATH   // 16 cells
const AI_PATH     = GAME_CONFIG.AI_PATH       // 16 cells
const PATH_LEN    = PLAYER_PATH.length        // 16

// ─── 敌军位置（插值） ─────────────────────────────────────────
function getPathPos(progress, path) {
  const max = path.length - 1
  const idx = Math.min(Math.floor(progress), max)
  const frac = progress - idx
  const [r0, c0] = path[idx]
  if (idx >= max) return { row: r0, col: c0 }
  const [r1, c1] = path[idx + 1]
  return { row: r0 + (r1-r0)*frac, col: c0 + (c1-c0)*frac }
}

// CSS位置（相对于 grid-wrap 容器）
export function getEnemyStyle(progress, isAI) {
  const path = isAI ? AI_PATH : PLAYER_PATH
  const { row, col } = getPathPos(progress, path)
  return {
    left: `${(col + 0.5) / COLS * 100}%`,
    top:  `${(row + 0.5) / ROWS * 100}%`,
  }
}

// ─── 塔攻击判定 ───────────────────────────────────────────────
// 防御塔在地块格上，攻击相邻路线格上的敌军
// 判断：敌军所在路线格 vs 塔的位置，距离是否在射程内

function getUnitRange(unit) {
  if (unit.type === 'general') return GENERALS[unit.key]?.range || 2
  return BASIC_UNITS[unit.key]?.range || 1
}
function getUnitAtk(unit) {
  const base = unit.type==='general' ? (GENERALS[unit.key]?.atk||6) : (BASIC_UNITS[unit.key]?.atk||2)
  return base + (unit.level-1)*1.5
}
function getUnitAtkSpeed(unit) {
  return unit.type==='general' ? (GENERALS[unit.key]?.atkSpeed||1.5) : (BASIC_UNITS[unit.key]?.atkSpeed||1.5)
}
function getAttackType(unit) {
  if (unit.type==='general') return GENERALS[unit.key]?.attackType||'single'
  return BASIC_UNITS[unit.key]?.attackType||'single'
}

function canAttack(unit, enemy, isAI) {
  const path = isAI ? AI_PATH : PLAYER_PATH
  const idx = Math.min(Math.floor(enemy.pathProgress), path.length-1)
  const [eRow, eCol] = path[idx]
  const range = getUnitRange(unit)
  const isArea = getAttackType(unit) === 'area'
  const tol = isArea ? 1.5 : 0.6

  // 路线列（左列col=0 或 右列col=COLS-1）
  if (eCol === 0) {
    // 敌在左列，塔需要 col <= range（水平距离），且同行
    return unit.col <= range && Math.abs(eRow - unit.row) < tol
  }
  if (eCol === COLS - 1) {
    return (COLS-1-unit.col) <= range && Math.abs(eRow - unit.row) < tol
  }
  // 路线行（两区都是顶行row=0，水平镜像）
  if (eRow === 0) {
    return unit.row <= range && Math.abs(eCol - unit.col) < tol
  }
  return false
}

// ─── 处理攻击 ─────────────────────────────────────────────────
const cooldowns = new Map()

function processAttacks(board, enemies, side, now) {
  const isAI = side === 'ai'
  for (let r=0; r<ROWS; r++) {
    for (let c=0; c<COLS; c++) {
      const cell = board[r][c]
      if (cell.kind === 'path' || !cell.unit || cell.unit.stunned) continue
      const unit = cell.unit

      const cd = 1000 / getUnitAtkSpeed(unit)
      const last = cooldowns.get(unit.id) || 0
      if (now - last < cd) continue

      const targets = enemies.filter(e => !e.stunned && canAttack(unit, e, isAI))
      if (!targets.length) continue

      cooldowns.set(unit.id, now)
      const atk = getUnitAtk(unit)
      const type = getAttackType(unit)

      if (type === 'pierce') {
        targets.forEach(t => gameStore.damageEnemy(side, t.id, atk))
      } else if (type === 'area') {
        targets.forEach(t => gameStore.damageEnemy(side, t.id, atk*0.7))
      } else {
        // single：打进度最大的（最靠近蔣的）
        const t = targets.reduce((a,b) => a.pathProgress>b.pathProgress ? a : b)
        gameStore.damageEnemy(side, t.id, atk)
      }

      unit.attacking = true
      setTimeout(() => { if (unit) unit.attacking = false }, 200)
    }
  }
}

// ─── 敌军移动 ─────────────────────────────────────────────────
function moveEnemies(delta) {
  const spd = delta * 0.0015

  for (let i=gameStore.playerEnemies.length-1; i>=0; i--) {
    const e = gameStore.playerEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * spd
    if (e.pathProgress >= PATH_LEN) {
      gameStore.playerEnemies.splice(i,1)
      gameStore.damagePlayerJiang()
    }
  }

  for (let i=gameStore.aiEnemies.length-1; i>=0; i--) {
    const e = gameStore.aiEnemies[i]
    if (e.stunned) continue
    e.pathProgress += e.speed * spd
    if (e.pathProgress >= PATH_LEN) {
      gameStore.aiEnemies.splice(i,1)
      gameStore.damageAIJiang()
    }
  }
}

// ─── 波次 ─────────────────────────────────────────────────────
function getWaveEnemies(wave) {
  const count = 3 + wave * 2
  return Array.from({ length: count }, (_, i) => {
    const r = Math.random()
    let key
    if (wave<=3)      key = r<0.7?'匪':r<0.9?'赤':'共'
    else if (wave<=8) key = r<0.4?'匪':r<0.65?'赤':r<0.85?'共':'寇'
    else              key = r<0.25?'匪':r<0.5?'赤':r<0.75?'共':'寇'
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
  function next() {
    if (i >= list.length || gameStore.phase !== 'playing') return
    const e = list[i++]
    gameStore.spawnEnemy(e.key, 'player')
    gameStore.spawnEnemy(e.key, 'ai')
    waveSpawnTimer = setTimeout(next, e.delay || 1000)
  }
  next()
}

// ─── AI自动操作 ───────────────────────────────────────────────
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
      for (let r=0; r<ROWS; r++) {
        for (let c=0; c<COLS; c++) {
          const cell = gameStore.aiBoard[r][c]
          if (cell.kind === 'unlocked' && !cell.unit) empties.push([r,c])
        }
      }
      if (!empties.length) break
      // 优先靠近路线的格子（提高攻击覆盖）
      const near = empties.filter(([r,c]) => c===1||c===COLS-2||r===1||r===ROWS-2)
      const pool = near.length ? near : empties
      const [r,c] = pool[Math.floor(Math.random()*pool.length)]
      gameStore.aiBoard[r][c].unit = {
        ...card, id: Date.now()+Math.random(),
        level: card.level||1, row:r, col:c, attacking:false, stunned:false,
      }
      gameStore.checkMerge(gameStore.aiBoard, r, c)
    }
  }
  aiTimer = setTimeout(aiTick, 3500 + Math.random()*3000)
}

// ─── 主循环 ───────────────────────────────────────────────────
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
