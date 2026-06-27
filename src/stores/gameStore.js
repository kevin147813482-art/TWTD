import { reactive } from 'vue'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES } from '../game/config.js'

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

function randomHandCard(wave) {
  const generalChance = Math.min(0.05 + wave * 0.01, 0.25)
  const shovelChance = 0.08
  const r = Math.random()
  if (r < generalChance) {
    const generals = Object.values(GENERALS)
    const g = generals[Math.floor(Math.random() * generals.length)]
    const char = g.chars[Math.floor(Math.random() * g.chars.length)]
    return { type: 'general_char', key: char, generalKey: g.key, char }
  } else if (r < generalChance + shovelChance) {
    return { type: 'shovel', key: '鏟', display: '鏟' }
  } else {
    const units = Object.keys(BASIC_UNITS)
    const key = units[Math.floor(Math.random() * units.length)]
    return { type: 'unit', key, level: 1 }
  }
}

export { randomHandCard }

function getRecruitCost(times) {
  return GAME_CONFIG.RECRUIT_BASE_COST + times * GAME_CONFIG.RECRUIT_COST_INCREMENT
}

export const gameStore = reactive({
  phase: 'home',
  wave: 1,
  bossWarning: false,
  enemyIdCounter: 0,

  // 玩家状态
  playerBoard: createBoard(),
  playerJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerFood: GAME_CONFIG.INITIAL_FOOD,
  playerRecruitTimes: 0,
  playerHand: Array(GAME_CONFIG.HAND_SIZE).fill(null),
  playerEnemies: [],
  playerScore: 0,

  // AI状态
  aiBoard: createBoard(),
  aiJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiFood: GAME_CONFIG.INITIAL_FOOD,
  aiRecruitTimes: 0,
  aiEnemies: [],
  aiScore: 0,

  get playerRecruitCost() {
    return getRecruitCost(this.playerRecruitTimes)
  },
  get canPlayerRecruit() {
    return this.playerFood >= this.playerRecruitCost
  },

  startGame() {
    this.phase = 'playing'
    this.wave = 1
    this.bossWarning = false
    this.enemyIdCounter = 0

    this.playerBoard = createBoard()
    this.playerJiangHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.playerJiangMaxHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.playerFood = GAME_CONFIG.INITIAL_FOOD
    this.playerRecruitTimes = 0
    this.playerHand = Array(GAME_CONFIG.HAND_SIZE).fill(null)
    this.playerEnemies = []
    this.playerScore = 0

    this.aiBoard = createBoard()
    this.aiJiangHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.aiJiangMaxHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.aiFood = GAME_CONFIG.INITIAL_FOOD
    this.aiRecruitTimes = 0
    this.aiEnemies = []
    this.aiScore = 0
  },

  playerRecruit() {
    if (!this.canPlayerRecruit) return
    this.playerFood -= this.playerRecruitCost
    this.playerRecruitTimes++
    for (let i = 0; i < GAME_CONFIG.HAND_SIZE; i++) {
      this.playerHand[i] = randomHandCard(this.wave)
    }
  },

  deployUnit(handIndex, row, col) {
    const cell = this.playerBoard[row][col]
    if (!cell.unlocked || cell.unit) return false
    const card = this.playerHand[handIndex]
    if (!card || card.type === 'shovel') return false
    cell.unit = {
      ...card,
      id: Date.now() + Math.random(),
      level: card.level || 1,
      exp: 0, row, col,
      attacking: false, stunned: false,
    }
    this.playerHand[handIndex] = null
    this.checkMerge(this.playerBoard, row, col)
    return true
  },

  openCell(handIndex, row, col) {
    const cell = this.playerBoard[row][col]
    if (cell.unlocked) return false
    const card = this.playerHand[handIndex]
    if (!card || card.type !== 'shovel') return false
    cell.unlocked = true
    this.playerHand[handIndex] = null
    return true
  },

  checkMerge(board, row, col) {
    const cell = board[row][col]
    if (!cell.unit) return
    const directions = [[-1,0],[1,0],[0,-1],[0,1]]
    for (const [dr, dc] of directions) {
      const nr = row + dr, nc = col + dc
      if (nr < 0 || nr >= GAME_CONFIG.BOARD_ROWS || nc < 0 || nc >= GAME_CONFIG.BOARD_COLS) continue
      const neighbor = board[nr][nc]
      if (!neighbor.unit) continue
      if (
        cell.unit.type === 'unit' && neighbor.unit.type === 'unit' &&
        cell.unit.key === neighbor.unit.key && cell.unit.level === neighbor.unit.level &&
        cell.unit.level < (BASIC_UNITS[cell.unit.key]?.maxLevel || 5)
      ) {
        cell.unit = { ...cell.unit, level: cell.unit.level + 1 }
        neighbor.unit = null
        return
      }
      if (cell.unit.type === 'general_char' && neighbor.unit.type === 'general_char' &&
          cell.unit.generalKey === neighbor.unit.generalKey && cell.unit.char !== neighbor.unit.char) {
        const general = GENERALS[cell.unit.generalKey]
        cell.unit = {
          type: 'general', key: cell.unit.generalKey, ...general,
          id: Date.now(), level: 1, exp: 0, row, col, attacking: false, stunned: false,
        }
        neighbor.unit = null
        return
      }
    }
  },

  damageEnemy(side, enemyId, dmg) {
    const enemies = side === 'player' ? this.playerEnemies : this.aiEnemies
    const enemy = enemies.find(e => e.id === enemyId)
    if (!enemy) return
    enemy.hp -= dmg
    if (enemy.hp <= 0) {
      const idx = enemies.findIndex(e => e.id === enemyId)
      if (idx !== -1) enemies.splice(idx, 1)
      if (side === 'player') {
        this.playerFood = Math.min(this.playerFood + GAME_CONFIG.FOOD_PER_KILL, 99)
        this.playerScore++
      } else {
        this.aiScore++
      }
    }
  },

  damagePlayerJiang() {
    this.playerFood = Math.min(this.playerFood + GAME_CONFIG.FOOD_ON_HIT, 99)
    this.playerJiangHp--
    if (this.playerJiangHp <= 0) this.phase = 'defeat'
  },

  damageAIJiang() {
    this.aiFood = Math.min(this.aiFood + GAME_CONFIG.FOOD_ON_HIT, 99)
    this.aiJiangHp--
    if (this.aiJiangHp <= 0) this.phase = 'victory'
  },

  spawnEnemy(key, side) {
    const type = ENEMY_TYPES[key]
    if (!type) return
    const enemies = side === 'player' ? this.playerEnemies : this.aiEnemies
    enemies.push({
      id: ++this.enemyIdCounter,
      key, ...type,
      hp: type.hp, maxHp: type.hp,
      pathProgress: 0,
      stunned: false,
      isBoss: false,
    })
  },

  nextWave() { this.wave++ },
  victory() { this.phase = 'victory' },
})
