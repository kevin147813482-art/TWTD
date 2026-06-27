import { reactive } from 'vue'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES } from '../game/config.js'

// 创建棋盘：含路线格(path)、锁定格(locked)、解锁格(unlocked)
function createBoard(isAI = false) {
  const board = []
  const { BOARD_ROWS, BOARD_COLS, INITIAL_UNLOCKED } = GAME_CONFIG

  for (let r = 0; r < BOARD_ROWS; r++) {
    board.push([])
    for (let c = 0; c < BOARD_COLS; c++) {
      const isLeftPath  = c === 0
      const isRightPath = c === BOARD_COLS - 1
      const isTopPath   = !isAI && r === 0
      const isBottomPath = isAI && r === BOARD_ROWS - 1
      const isPath = isLeftPath || isRightPath || isTopPath || isBottomPath

      if (isPath) {
        board[r].push({ kind: 'path', unit: null })
      } else {
        const unlocked = INITIAL_UNLOCKED.some(([ur, uc]) => ur === r && uc === c)
        board[r].push({ kind: unlocked ? 'unlocked' : 'locked', unit: null })
      }
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
    return { type: 'shovel', key: '鏟' }
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

  // 玩家
  playerBoard: createBoard(false),
  playerJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerFood: GAME_CONFIG.INITIAL_FOOD,
  playerRecruitTimes: 0,
  playerHand: Array(GAME_CONFIG.HAND_SIZE).fill(null),
  playerEnemies: [],
  playerScore: 0,

  // AI
  aiBoard: createBoard(true),
  aiJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiFood: GAME_CONFIG.INITIAL_FOOD,
  aiRecruitTimes: 0,
  aiEnemies: [],
  aiScore: 0,

  get playerRecruitCost() { return getRecruitCost(this.playerRecruitTimes) },
  get canPlayerRecruit() { return this.playerFood >= this.playerRecruitCost },

  startGame() {
    this.phase = 'playing'
    this.wave = 1
    this.bossWarning = false
    this.enemyIdCounter = 0
    this.playerBoard = createBoard(false)
    this.playerJiangHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.playerJiangMaxHp = GAME_CONFIG.JIANG_INITIAL_HP
    this.playerFood = GAME_CONFIG.INITIAL_FOOD
    this.playerRecruitTimes = 0
    this.playerHand = Array(GAME_CONFIG.HAND_SIZE).fill(null)
    this.playerEnemies = []
    this.playerScore = 0
    this.aiBoard = createBoard(true)
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
    if (cell.kind !== 'unlocked' || cell.unit) return false
    const card = this.playerHand[handIndex]
    if (!card || card.type === 'shovel') return false
    cell.unit = {
      ...card, id: Date.now() + Math.random(),
      level: card.level || 1, exp: 0,
      row, col, attacking: false, stunned: false,
    }
    this.playerHand[handIndex] = null
    this.checkMerge(this.playerBoard, row, col)
    return true
  },

  openCell(handIndex, row, col) {
    const cell = this.playerBoard[row][col]
    if (cell.kind !== 'locked') return false
    const card = this.playerHand[handIndex]
    if (!card || card.type !== 'shovel') return false
    cell.kind = 'unlocked'
    this.playerHand[handIndex] = null
    return true
  },

  checkMerge(board, row, col) {
    const cell = board[row][col]
    if (!cell.unit) return
    const dirs = [[-1,0],[1,0],[0,-1],[0,1]]
    for (const [dr,dc] of dirs) {
      const nr = row+dr, nc = col+dc
      if (nr<0||nr>=GAME_CONFIG.BOARD_ROWS||nc<0||nc>=GAME_CONFIG.BOARD_COLS) continue
      const nb = board[nr][nc]
      if (!nb.unit) continue
      if (cell.unit.type==='unit' && nb.unit.type==='unit' &&
          cell.unit.key===nb.unit.key && cell.unit.level===nb.unit.level &&
          cell.unit.level < (BASIC_UNITS[cell.unit.key]?.maxLevel||5)) {
        cell.unit = { ...cell.unit, level: cell.unit.level+1 }
        nb.unit = null; return
      }
      if (cell.unit.type==='general_char' && nb.unit.type==='general_char' &&
          cell.unit.generalKey===nb.unit.generalKey && cell.unit.char!==nb.unit.char) {
        const g = GENERALS[cell.unit.generalKey]
        cell.unit = { type:'general', key:cell.unit.generalKey, ...g,
          id:Date.now(), level:1, exp:0, row, col, attacking:false, stunned:false }
        nb.unit = null; return
      }
    }
  },

  damageEnemy(side, enemyId, dmg) {
    const list = side==='player' ? this.playerEnemies : this.aiEnemies
    const e = list.find(e=>e.id===enemyId)
    if (!e) return
    e.hp -= dmg
    if (e.hp <= 0) {
      const i = list.findIndex(e=>e.id===enemyId)
      if (i!==-1) list.splice(i,1)
      if (side==='player') {
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
    const list = side==='player' ? this.playerEnemies : this.aiEnemies
    list.push({
      id: ++this.enemyIdCounter,
      key, ...type, hp: type.hp, maxHp: type.hp,
      pathProgress: 0, stunned: false, isBoss: false,
    })
  },

  nextWave() { this.wave++ },
  victory() { this.phase = 'victory' },
})
