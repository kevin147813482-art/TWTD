import { gameStore } from '../stores/gameStore.js'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES, BOSSES, MAPS } from './config.js'

let gameLoop = null
let waveTimer = null
let lastTick = 0

// 每波敌军配置
function getWaveEnemies(wave) {
  const count = 3 + wave * 2
  const rows = GAME_CONFIG.BOARD_ROWS
  const enemies = []
  for (let i = 0; i < count; i++) {
    const keys = Object.keys(ENEMY_TYPES)
    // 随波次提高强敌比例
    let key
    const r = Math.random()
    if (wave <= 3) {
      key = r < 0.7 ? '匪' : r < 0.9 ? '赤' : '共'
    } else if (wave <= 8) {
      key = r < 0.4 ? '匪' : r < 0.65 ? '赤' : r < 0.85 ? '共' : '寇'
    } else {
      key = r < 0.25 ? '匪' : r < 0.5 ? '赤' : r < 0.75 ? '共' : '寇'
    }
    enemies.push({ key, row: Math.floor(Math.random() * rows), delay: i * 1200 })
  }
  return enemies
}

// 获取单位攻击力
function getUnitAtk(unit) {
  const base = unit.type === 'general'
    ? GENERALS[unit.key]?.atk || 6
    : (BASIC_UNITS[unit.key]?.atk || 2)
  return base + (unit.level - 1) * 1.5
}

// 获取单位攻速
function getUnitAtkSpeed(unit) {
  return unit.type === 'general'
    ? GENERALS[unit.key]?.atkSpeed || 1.5
    : (BASIC_UNITS[unit.key]?.atkSpeed || 1.5)
}

// 攻击冷却计时
const attackCooldowns = new Map()

function unitAttack(unit, now) {
  if (unit.stunned) return
  const speed = getUnitAtkSpeed(unit)
  const cooldown = 1000 / speed
  const lastAttack = attackCooldowns.get(unit.id) || 0
  if (now - lastAttack < cooldown) return

  const unitConfig = unit.type === 'general' ? GENERALS[unit.key] : BASIC_UNITS[unit.key]
  const attackType = unitConfig?.attackType || 'single'
  const range = unitConfig?.range || 1
  const atk = getUnitAtk(unit)

  // 找目标：同行或范围内的敌军
  const targets = gameStore.enemies.filter(e => {
    if (e.stunned) return false
    const rowDiff = Math.abs(e.row - unit.row)
    const colDiff = unit.col - e.x // 敌军从右向左
    if (attackType === 'pierce') return rowDiff === 0 && colDiff >= 0 && colDiff <= range + 1
    if (attackType === 'area') return rowDiff <= 1 && colDiff >= 0 && colDiff <= range
    return rowDiff === 0 && colDiff >= 0 && colDiff <= range
  })

  if (targets.length === 0) return
  attackCooldowns.set(unit.id, now)

  if (attackType === 'single' || attackType === 'pierce') {
    // 贯穿打所有同行目标
    const lineTargets = attackType === 'pierce' ? targets : [targets[0]]
    lineTargets.forEach(t => gameStore.damageEnemy(t.id, atk))
  } else if (attackType === 'area') {
    targets.forEach(t => gameStore.damageEnemy(t.id, atk * 0.7))
  }

  unit.attacking = true
  setTimeout(() => { unit.attacking = false }, 200)
}

// 敌军移动
function moveEnemies(delta) {
  for (const enemy of gameStore.enemies) {
    if (enemy.stunned) continue
    enemy.x -= enemy.speed * delta * 0.003

    // 到达蔣的位置
    if (enemy.x <= -0.5) {
      gameStore.removeEnemy(enemy.id)
      gameStore.damageJiang()
    }
  }
}

// 波次管理
let waveEnemyQueue = []
let waveSpawnTimer = null
let waveInProgress = false

function startWave(wave) {
  waveInProgress = true
  const enemies = getWaveEnemies(wave)

  // 检查BOSS
  const boss = Object.values(BOSSES).find(b => b.wave === wave)
  if (boss) {
    gameStore.bossWarning = true
    setTimeout(() => {
      gameStore.bossWarning = false
      spawnBoss(boss)
    }, 3000)
  }

  let i = 0
  function spawnNext() {
    if (i >= enemies.length) {
      waveInProgress = false
      return
    }
    const e = enemies[i++]
    gameStore.spawnEnemy(e.key, e.row)
    waveSpawnTimer = setTimeout(spawnNext, e.delay || 1200)
  }
  spawnNext()
}

function spawnBoss(boss) {
  gameStore.enemies.push({
    id: ++gameStore.enemyIdCounter,
    key: boss.key,
    name: boss.key,
    hp: boss.hp,
    maxHp: boss.hp,
    speed: boss.speed,
    atk: 1,
    x: GAME_CONFIG.BOARD_COLS,
    row: Math.floor(GAME_CONFIG.BOARD_ROWS / 2),
    stunned: false,
    isBoss: true,
    skill: boss.skill,
  })
}

// 主游戏循环
function tick(now) {
  if (gameStore.phase !== 'playing') return
  const delta = now - lastTick
  lastTick = now

  // 移动敌军
  moveEnemies(delta)

  // 单位攻击
  for (let r = 0; r < GAME_CONFIG.BOARD_ROWS; r++) {
    for (let c = 0; c < GAME_CONFIG.BOARD_COLS; c++) {
      const cell = gameStore.board[r][c]
      if (cell.unit) unitAttack(cell.unit, now)
    }
  }

  gameLoop = requestAnimationFrame(tick)
}

// 波次调度
let waveScheduler = null

export function startEngine() {
  lastTick = performance.now()
  gameLoop = requestAnimationFrame(tick)

  // 第一波立即开始
  startWave(gameStore.wave)

  // 后续波次
  function scheduleNextWave() {
    waveScheduler = setTimeout(() => {
      if (gameStore.phase !== 'playing') return
      if (gameStore.wave >= 30) {
        gameStore.victory()
        return
      }
      gameStore.nextWave()
      startWave(gameStore.wave)
      scheduleNextWave()
    }, GAME_CONFIG.WAVE_INTERVAL)
  }
  scheduleNextWave()
}

export function stopEngine() {
  if (gameLoop) cancelAnimationFrame(gameLoop)
  if (waveScheduler) clearTimeout(waveScheduler)
  if (waveSpawnTimer) clearTimeout(waveSpawnTimer)
  attackCooldowns.clear()
}
