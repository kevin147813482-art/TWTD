// 游戏核心配置
export const GAME_CONFIG = {
  // 棋盘
  BOARD_COLS: 5,
  BOARD_ROWS: 4,
  INITIAL_UNLOCKED: [
    // 初始解锁6个格子：左右两列（紧邻左右路线）
    [0, 0], [1, 0], [2, 0],
    [0, 4], [1, 4], [2, 4],
  ],

  // 阿斗（蔣）
  JIANG_INITIAL_HP: 3,

  // 粮食
  INITIAL_FOOD: 10,
  FOOD_PER_KILL: 1,
  FOOD_ON_HIT: 10,
  RECRUIT_BASE_COST: 10,
  RECRUIT_COST_INCREMENT: 2,

  // 手牌
  HAND_SIZE: 5,

  // 波次
  WAVE_INTERVAL: 8000, // ms
}

// 基础兵种
export const BASIC_UNITS = {
  步: {
    key: '步',
    name: '步兵',
    type: 'melee',
    attackType: 'single',
    atk: 3,
    atkSpeed: 1.75,
    range: 1,
    maxLevel: 5,
    color: '#333',
  },
  炮: {
    key: '炮',
    name: '炮兵',
    type: 'range',
    attackType: 'pierce',
    atk: 2,
    atkSpeed: 1.25,
    range: 3,
    maxLevel: 5,
    color: '#333',
  },
  槍: {
    key: '槍',
    name: '機槍手',
    type: 'range',
    attackType: 'single',
    atk: 2,
    atkSpeed: 2.0,
    range: 2,
    maxLevel: 5,
    color: '#333',
  },
  坦: {
    key: '坦',
    name: '坦克',
    type: 'melee',
    attackType: 'area',
    atk: 2,
    atkSpeed: 1.25,
    range: 1,
    maxLevel: 5,
    color: '#333',
  },
}

// 武将配置（需要两字拼合）
export const GENERALS = {
  立人: {
    key: '立人',
    fullName: '孫立人',
    chars: ['立', '人'],
    atk: 8,
    atkSpeed: 2.0,
    attackType: 'area',
    skill: '鐵拳',
    color: '#c8960c',
  },
  崇禧: {
    key: '崇禧',
    fullName: '白崇禧',
    chars: ['崇', '禧'],
    atk: 7,
    atkSpeed: 1.5,
    attackType: 'pierce',
    skill: '謀略',
    color: '#c8960c',
  },
  薛岳: {
    key: '薛岳',
    fullName: '薛岳',
    chars: ['薛', '岳'],
    atk: 9,
    atkSpeed: 1.75,
    attackType: 'single',
    skill: '天爐',
    color: '#c8960c',
  },
  靈甫: {
    key: '靈甫',
    fullName: '張靈甫',
    chars: ['靈', '甫'],
    atk: 8,
    atkSpeed: 2.0,
    attackType: 'area',
    skill: '突擊',
    color: '#c8960c',
  },
  宗南: {
    key: '宗南',
    fullName: '胡宗南',
    chars: ['宗', '南'],
    atk: 6,
    atkSpeed: 1.5,
    attackType: 'single',
    skill: '守備',
    color: '#c8960c',
  },
  耀湘: {
    key: '耀湘',
    fullName: '廖耀湘',
    chars: ['耀', '湘'],
    atk: 7,
    atkSpeed: 1.75,
    attackType: 'pierce',
    skill: '鋼甲',
    color: '#c8960c',
  },
}

// 敌军小兵配置
export const ENEMY_TYPES = {
  匪: {
    key: '匪',
    name: '普通共匪',
    hp: 10,
    speed: 1.0,
    atk: 1,
    color: '#555',
    weight: 40, // 出现权重
  },
  共: {
    key: '共',
    name: '精英共軍',
    hp: 25,
    speed: 1.3,
    atk: 1,
    color: '#1a237e',
    weight: 25,
  },
  赤: {
    key: '赤',
    name: '赤衛隊',
    hp: 6,
    speed: 1.8,
    atk: 1,
    color: '#c62828',
    weight: 25,
  },
  寇: {
    key: '寇',
    name: '重裝共寇',
    hp: 50,
    speed: 0.5,
    atk: 1,
    color: '#4e342e',
    weight: 10,
  },
}

// BOSS配置
export const BOSSES = {
  朱德: {
    key: '朱德',
    wave: 6,
    hp: 500,
    speed: 0.8,
    skill: '封鎖',
    skillDesc: '將空白地塊轉為不可用',
    color: '#b71c1c',
  },
  林彪: {
    key: '林彪',
    wave: 12,
    hp: 1500,
    speed: 1.0,
    skill: '摧魂',
    skillDesc: '使我方小兵暫時停止攻擊',
    color: '#b71c1c',
  },
  德懷: {
    key: '德懷',
    wave: 18,
    hp: 3000,
    speed: 0.9,
    skill: '召魂',
    skillDesc: '復活已消滅的敵兵',
    color: '#b71c1c',
  },
  恩來: {
    key: '恩來',
    wave: 24,
    hp: 6000,
    speed: 1.1,
    skill: '滲透',
    skillDesc: '使敵兵繞過防線直衝蔣',
    color: '#b71c1c',
  },
  澤東: {
    key: '澤東',
    wave: 30,
    hp: 50000,
    speed: 0.7,
    skill: '人海',
    skillDesc: '大量增援敵兵湧入',
    color: '#b71c1c',
  },
}

// 地图配置
export const MAPS = [
  { id: 'songhu', name: '淞滬', theme: 'urban', bgColor: '#8b7355' },
  { id: 'xubing', name: '徐蚌', theme: 'plains', bgColor: '#6b8c42' },
  { id: 'liaoshen', name: '遼瀋', theme: 'north', bgColor: '#78909c' },
  { id: 'pingjin', name: '平津', theme: 'city', bgColor: '#a1887f' },
  { id: 'dujiang', name: '渡江', theme: 'river', bgColor: '#4fc3f7' },
]
