import { reactive } from 'vue'
import { GAME_CONFIG, BASIC_UNITS, GENERALS, ENEMY_TYPES } from '../game/config.js'

// 根据路线定义哪些格子是path（路线格）
function isPathCell(r, c, isAI) {
  const ROWS = GAME_CONFIG.BOARD_ROWS
  const COLS = GAME_CONFIG.BOARD_COLS
  if (isAI) {
    // AI路线: 右列 + 底行 + 左列
    return c === COLS - 1 || r === ROWS - 1 || c === 0
  } else {
    // 玩家路线: 左列 + 顶行 + 右列
    return c === 0 || r === 0 || c === COLS - 1
  }
}

function createBoard(isAI = false) {
  const board = []
  const { BOARD_ROWS, BOARD_COLS, INITIAL_UNLOCKED, AI_INITIAL_UNLOCKED } = GAME_CONFIG
  const unlockList = isAI ? AI_INITIAL_UNLOCKED : INITIAL_UNLOCKED
  for (let r = 0; r < BOARD_ROWS; r++) {
    board.push([])
    for (let c = 0; c < BOARD_COLS; c++) {
      if (isPathCell(r, c, isAI)) {
        board[r].push({ kind: 'path', unit: null })
      } else {
        const unlocked = unlockList.some(([ur, uc]) => ur === r && uc === c)
        board[r].push({ kind: unlocked ? 'unlocked' : 'locked', unit: null })
      }
    }
  }
  return board
}

export function randomHandCard(wave) {
  const generalChance = 0.15
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

function getRecruitCost(times) {
  return GAME_CONFIG.RECRUIT_BASE_COST + times * GAME_CONFIG.RECRUIT_COST_INCREMENT
}

// 路线第一格=营，最后一格=蔣
export const PLAYER_YING_CELL  = GAME_CONFIG.PLAYER_PATH[0]                              // [4,0]
export const PLAYER_JIANG_CELL = GAME_CONFIG.PLAYER_PATH[GAME_CONFIG.PLAYER_PATH.length - 1] // [4,7]
export const AI_YING_CELL      = GAME_CONFIG.AI_PATH[0]                                  // [0,7]
export const AI_JIANG_CELL     = GAME_CONFIG.AI_PATH[GAME_CONFIG.AI_PATH.length - 1]     // [0,0]

export const gameStore = reactive({
  phase: 'home',  // home | prep | playing | victory | defeat
  wave: 1,
  bossWarning: false,
  enemyIdCounter: 0,
  projectiles: [],
  playerJiangProgress: 0,  // 准备阶段蔣沿路线行走进度
  aiJiangProgress: 0,
  playerDanger: false,
  aiDanger: false,

  playerBoard: createBoard(false),
  playerJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  playerFood: GAME_CONFIG.INITIAL_FOOD,
  playerRecruitTimes: 0,
  playerHand: Array(GAME_CONFIG.HAND_SIZE).fill(null),
  playerEnemies: [],
  playerScore: 0,

  aiBoard: createBoard(true),
  aiJiangHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiJiangMaxHp: GAME_CONFIG.JIANG_INITIAL_HP,
  aiFood: GAME_CONFIG.INITIAL_FOOD,
  aiRecruitTimes: 0,
  aiEnemies: [],
  aiScore: 0,

  get playerRecruitCost() { return getRecruitCost(this.playerRecruitTimes) },
  get canPlayerRecruit()  { return this.playerFood >= this.playerRecruitCost },

  startGame() {
    this.phase = 'prep'
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
    this.playerJiangProgress = 0
    this.aiJiangProgress = 0
    this.playerDanger = false
    this.aiDanger = false
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
    if (cell.kind !== 'unlocked') return false
    const card = this.playerHand[handIndex]
    if (!card || card.type === 'shovel') return false
    if (cell.unit) {
      // 手牌拖到已有单位上：尝试合并
      const b = cell.unit
      const maxLv = BASIC_UNITS[card.key]?.maxLevel || 5
      if (card.type === b.type && card.key === b.key &&
          (card.level || 1) === b.level && b.level < maxLv) {
        cell.unit = { ...b, level: b.level + 1 }
        this.playerHand[handIndex] = null
        return true
      }
      return false
    }
    cell.unit = {
      ...card, id: Date.now() + Math.random(),
      level: card.level || 1, row, col, attacking: false, stunned: false,
    }
    this.playerHand[handIndex] = null
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
    for (const [dr,dc] of [[-1,0],[1,0],[0,-1],[0,1]]) {
      const nr=row+dr, nc=col+dc
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
          id:Date.now(), level:1, row, col, attacking:false, stunned:false }
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
        this.playerFood = Math.min(this.playerFood+GAME_CONFIG.FOOD_PER_KILL, 99)
        this.playerScore++
      } else { this.aiScore++ }
    }
  },

  damagePlayerJiang() {
    this.playerFood = Math.min(this.playerFood+GAME_CONFIG.FOOD_ON_HIT, 99)
    this.playerJiangHp--
    if (this.playerJiangHp <= 0) this.phase = 'defeat'
  },

  damageAIJiang() {
    this.aiFood = Math.min(this.aiFood+GAME_CONFIG.FOOD_ON_HIT, 99)
    this.aiJiangHp--
    if (this.aiJiangHp <= 0) this.phase = 'victory'
  },

  spawnEnemy(key, side) {
    const type = ENEMY_TYPES[key]
    if (!type) return
    // 每波 ×1.25 血量缩放
    const waveMult = Math.pow(1.25, this.wave - 1)
    const hp = Math.round(type.hp * waveMult)
    const list = side==='player' ? this.playerEnemies : this.aiEnemies
    list.push({
      id: ++this.enemyIdCounter,
      key, ...type, hp, maxHp: hp,
      pathProgress: 0, stunned: false, isBoss: false,
    })
  },

  spawnProjectile(sx, sy, ex, ey, kind, side) {
    const id = ++this.enemyIdCounter + Math.random()
    this.projectiles.push({ id, sx, sy, ex, ey, kind, side })
    setTimeout(() => {
      const i = this.projectiles.findIndex(p => p.id === id)
      if (i !== -1) this.projectiles.splice(i, 1)
    }, 380)
  },

  moveOrMergeUnit(fromR, fromC, toR, toC) {
    const fromCell = this.playerBoard[fromR][fromC]
    const toCell   = this.playerBoard[toR][toC]
    if (!fromCell.unit) return
    if (toCell.kind !== 'unlocked') return
    if (!toCell.unit) {
      // 移动到空格
      toCell.unit = { ...fromCell.unit, row: toR, col: toC }
      fromCell.unit = null
    } else {
      // 合并：同兵种同等级
      const a = fromCell.unit, b = toCell.unit
      const maxLv = BASIC_UNITS[a.key]?.maxLevel || 5
      if (a.type === b.type && a.key === b.key && a.level === b.level && a.level < maxLv) {
        toCell.unit = { ...b, level: b.level + 1 }
        fromCell.unit = null
      } else {
        // 无法合成：互换位置
        const tmp = { ...fromCell.unit, row: toR, col: toC }
        fromCell.unit = { ...toCell.unit, row: fromR, col: fromC }
        toCell.unit = tmp
      }
    }
  },

  returnUnitToHand(r, c, slotIndex) {
    const cell = this.playerBoard[r][c]
    if (!cell.unit) return
    const unit = cell.unit
    // 转回卡牌格式
    const card = unit.type === 'general'
      ? { type: 'general', key: unit.key, level: unit.level }
      : unit.type === 'general_char'
        ? { type: 'general_char', key: unit.key, generalKey: unit.generalKey, char: unit.char }
        : { type: 'unit', key: unit.key, level: unit.level }
    this.playerHand[slotIndex] = card
    cell.unit = null
  },

  nextWave() { this.wave++ },
  victory()  { this.phase = 'victory' },
})
