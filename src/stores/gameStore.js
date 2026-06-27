import { reactive } from 'vue'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES, BOSSES } from '../game/config.js'

function createBoard() {
  const board = []
  for (let r = 0; r < GAME_CONFIG.BOARD_ROWS; r++) {
    board.push([])
    for (let c = 0; c < GAME_CONFIG.BOARD_COLS; c++) {
      const unlocked = GAME_CONFIG.INITIAL_UNLOCKED.some(([ur, uc]) => ur === r && uc === c)
      board[r].push({ unit: null, unlocked })
    }
  }
  return board
}

function randomEnemyKey(wave) {
  const types = Object.values(ENEMY_TYPES)
  const totalWeight = types.reduce((s, t) => s + t.weight, 0)
  let r = Math.random() * totalWeight
  for (const t of types) {
    r -= t.weight
    if (r <= 0) return t.key
  }
  return '匪'
}

function getRecruitCost(times) {
  return GAME_CONFIG.RECRUIT_BASE_COST + times * GAME_CONFIG.RECRUIT_COST_INCREMENT
}

function randomHandCard(wave) {
  // 武将单字出现概率随波次增加
  const generalChance = Math.min(0.05 + wave * 0.01, 0.25)
  const shovleChance = 0.08

  const r = Math.random()
  if (r < generalChance) {
    // 随机一个武将的一个字
    const generals = Object.values(GENERALS)
    const g = generals[Math.floor(Math.random() * generals.length)]
    const char = g.chars[Math.floor(Math.random() * g.chars.length)]
    return { type: 'general_char', key: char, generalKey: g.key, char }
  } else if (r < generalChance + shovleChance) {
    return { type: 'shovel', key: '鏟', display: '鏟' }
  } else {
    const units = Object.keys(BASIC_UNITS)
    const key = units[Math.floor(Math.random() * units.length)]
    return { type: 'unit', key, level: 1 }
  }
}

export const gameStore = reactive({
  // 状态
  phase: 'home', // home | playing | paused | victory | defeat
  wave: 1,
  food: GAME_CONFIG.INITIAL_FOOD,
  recruitTimes: 0,
  jiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  jiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  shovels: 0,
  score: 0,
  currentMap: 0,

  // 棋盘
  board: createBoard(),

  // 手牌
  hand: Array(GAME_CONFIG.HAND_SIZE).fill(null),

  // 敌军
  enemies: [],
  enemyIdCounter: 0,

  // BOSS
  currentBoss: null,
  bossWarning: false,

  // 计算属性
  get recruitCost() {
    return getRecruitCost(this.recruitTimes)
  },

  get canRecruit() {
    return this.food >= this.recruitCost
  },

  // 开始游戏
  startGame() {
    this.phase = 'playing'
    this.wave = 1
    this.food = GAME_CONFIG.INITIAL_FOOD
    this.recruitTimes = 0
    this.jiangHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.jiangMaxHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.shovels = 0
    this.score = 0
    this.board = createBoard()
    this.hand = Array(GAME_CONFIG.HAND_SIZE).fill(null)
    this.enemies = []
    this.currentBoss = null
    this.bossWarning = false
  },

  // 征兵（刷新手牌）
  recruit() {
    if (!this.canRecruit) return
    this.food -= this.recruitCost
    this.recruitTimes++
    for (let i = 0; i < GAME_CONFIG.HAND_SIZE; i++) {
      this.hand[i] = randomHandCard(this.wave)
    }
  },

  // 部署单位到棋盘
  deployUnit(handIndex, row, col) {
    const cell = this.board[row][col]
    if (!cell.unlocked || cell.unit) return false
    const card = this.hand[handIndex]
    if (!card) return false

    if (card.type === 'shovel') {
      // 铲子不能放到有单位的格子，用于开地
      return false
    }

    cell.unit = {
      ...card,
      id: Date.now() + Math.random(),
      level: card.level || 1,
      exp: 0,
      row,
      col,
      attacking: false,
      stunned: false,
    }
    this.hand[handIndex] = null

    // 检查合成
    this.checkMerge(row, col)
    return true
  },

  // 使用铲子开地
  useShovel(handIndex, row, col) {
    const cell = this.board[row][col]
    if (cell.unlocked) return false
    const card = this.hand[handIndex]
    if (!card || card.type !== 'shovel') return false
    if (this.shovels <= 0 && card.type === 'shovel') {
      cell.unlocked = true
      this.hand[handIndex] = null
      return true
    }
    return false
  },

  // 铲子道具开地
  useShovelItem(row, col) {
    if (this.shovels <= 0) return false
    const cell = this.board[row][col]
    if (cell.unlocked) return false
    cell.unlocked = true
    this.shovels--
    return true
  },

  // 检查合成
  checkMerge(row, col) {
    const cell = this.board[row][col]
    if (!cell.unit) return

    const directions = [[-1,0],[1,0],[0,-1],[0,1]]
    for (const [dr, dc] of directions) {
      const nr = row + dr
      const nc = col + dc
      if (nr < 0 || nr >= GAME_CONFIG.BOARD_ROWS || nc < 0 || nc >= GAME_CONFIG.BOARD_COLS) continue
      const neighbor = this.board[nr][nc]
      if (!neighbor.unit) continue

      // 基础兵合成升级
      if (
        cell.unit.type === 'unit' &&
        neighbor.unit.type === 'unit' &&
        cell.unit.key === neighbor.unit.key &&
        cell.unit.level === neighbor.unit.level &&
        cell.unit.level < BASIC_UNITS[cell.unit.key]?.maxLevel
      ) {
        cell.unit = { ...cell.unit, level: cell.unit.level + 1, exp: 0 }
        neighbor.unit = null
        return
      }

      // 武将字合成
      if (cell.unit.type === 'general_char' && neighbor.unit.type === 'general_char') {
        const g1 = cell.unit.generalKey
        const g2 = neighbor.unit.generalKey
        if (g1 === g2 && cell.unit.char !== neighbor.unit.char) {
          const general = GENERALS[g1]
          cell.unit = {
            type: 'general',
            key: g1,
            ...general,
            id: Date.now(),
            level: 1,
            exp: 0,
            row,
            col,
            attacking: false,
            stunned: false,
          }
          neighbor.unit = null
          return
        }
      }
    }
  },

  // 敌军受伤
  damageEnemy(enemyId, dmg) {
    const enemy = this.enemies.find(e => e.id === enemyId)
    if (!enemy) return
    enemy.hp -= dmg
    if (enemy.hp <= 0) {
      this.removeEnemy(enemyId)
      this.food = Math.min(this.food + GAME_CONFIG.FOOD_PER_KILL, 99)
      this.score++
    }
  },

  // 移除敌军
  removeEnemy(enemyId) {
    const idx = this.enemies.findIndex(e => e.id === enemyId)
    if (idx !== -1) this.enemies.splice(idx, 1)
  },

  // 蔣受伤
  damageJiang() {
    this.food = Math.min(this.food + GAME_CONFIG.FOOD_ON_HIT, 99)
    this.jiangHp--
    if (this.jiangHp <= 0) {
      this.phase = 'defeat'
    }
  },

  // 增加蔣血量
  addJiangHp(amount) {
    this.jiangMaxHp += amount
    this.jiangHp += amount
  },

  // 生成敌军
  spawnEnemy(key, row) {
    const type = ENEMY_TYPES[key]
    if (!type) return
    this.enemies.push({
      id: ++this.enemyIdCounter,
      key,
      ...type,
      hp: type.hp,
      maxHp: type.hp,
      x: GAME_CONFIG.BOARD_COLS,
      row,
      stunned: false,
    })
  },

  nextWave() {
    this.wave++
  },

  victory() {
    this.phase = 'victory'
  },
})
