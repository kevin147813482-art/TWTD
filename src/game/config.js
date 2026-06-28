// 游戏核心配置
export const GAME_CONFIG = {
  // 棋盘：8列 × 5行 = 40格/区
  // 玩家区路线：左列↑ → 顶行→ → 右列↓，营在[4,0]，蔣在[4,7]
  // AI区路线：右列↓ → 底行← → 左列↑，营在[0,7]，蔣在[0,0]
  BOARD_ROWS: 5,
  BOARD_COLS: 8,

  // 玩家初始解锁6格（靠近顶行路线，行1-2，列1-3）
  INITIAL_UNLOCKED: [
    [1,1],[1,2],[1,3],
    [2,1],[2,2],[2,3],
  ],
  // AI初始解锁6格（玩家180°旋转：靠近底行路线，行2-3，列4-6）
  AI_INITIAL_UNLOCKED: [
    [2,4],[2,5],[2,6],
    [3,4],[3,5],[3,6],
  ],

  // 玩家路线（按顺序：从营到蔣）
  // 营=[4,0]，左列↑，顶行→，右列↓，蔣=[4,7]
  PLAYER_PATH: [
    [4,0],[3,0],[2,0],[1,0],[0,0],          // 左列向上
    [0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[0,7], // 顶行向右
    [1,7],[2,7],[3,7],[4,7],                // 右列向下
  ],

  // AI路线（水平镜像：营右上，蔣左上）
  // 营=[0,7]，右列↓，底行←，左列↑，蔣=[0,0]
  AI_PATH: [
    [0,7],[1,7],[2,7],[3,7],[4,7],          // 右列向下
    [4,6],[4,5],[4,4],[4,3],[4,2],[4,1],[4,0], // 底行向左
    [3,0],[2,0],[1,0],[0,0],                // 左列向上
  ],

  // 阿斗（蔣）
  JIANG_INITIAL_HP: 3,

  // 粮食
  INITIAL_FOOD: 20,
  FOOD_PER_KILL: 1,
  FOOD_ON_HIT: 10,
  RECRUIT_BASE_COST: 10,
  RECRUIT_COST_INCREMENT: 2,

  // 手牌
  HAND_SIZE: 5,

  // 波次
  WAVE_INTERVAL: 10000,
}

// 基础兵种
export const BASIC_UNITS = {
  步: {
    key: '步', name: '步兵',
    attackType: 'single', atk: 3.0, atkSpeed: 1.25, range: 1, maxLevel: 5,
  },
  炮: {
    key: '炮', name: '炮兵',
    attackType: 'pierce', atk: 2.0, atkSpeed: 1.25, range: 3, maxLevel: 5,
  },
  槍: {
    key: '槍', name: '機槍手',
    attackType: 'single', atk: 2.0, atkSpeed: 1.25, range: 2, maxLevel: 5,
  },
  坦: {
    key: '坦', name: '坦克',
    attackType: 'area', atk: 2.0, atkSpeed: 1.25, range: 1, maxLevel: 5,
  },
}

// 武将配置
export const GENERALS = {
  立人: { key:'立人', fullName:'孫立人', chars:['立','人'], atk:8, atkSpeed:2.0, attackType:'area',   range:2, skill:'鐵拳', },
  崇禧: { key:'崇禧', fullName:'白崇禧', chars:['崇','禧'], atk:7, atkSpeed:1.5, attackType:'pierce', range:3, skill:'謀略', },
  薛岳: { key:'薛岳', fullName:'薛岳',   chars:['薛','岳'], atk:9, atkSpeed:1.75,attackType:'single', range:2, skill:'天爐', },
  靈甫: { key:'靈甫', fullName:'張靈甫', chars:['靈','甫'], atk:8, atkSpeed:2.0, attackType:'area',   range:2, skill:'突擊', },
  宗南: { key:'宗南', fullName:'胡宗南', chars:['宗','南'], atk:6, atkSpeed:1.5, attackType:'single', range:2, skill:'守備', },
  耀湘: { key:'耀湘', fullName:'廖耀湘', chars:['耀','湘'], atk:7, atkSpeed:1.75,attackType:'pierce', range:3, skill:'鋼甲', },
}

// 敌军小兵
export const ENEMY_TYPES = {
  匪: { key:'匪', name:'普通共匪', hp:9,  speed:1.0, atk:1, weight:40 },
  共: { key:'共', name:'精英共軍', hp:25, speed:1.3, atk:1, weight:25 },
  赤: { key:'赤', name:'赤衛隊',   hp:6,  speed:1.8, atk:1, weight:25 },
  寇: { key:'寇', name:'重裝共寇', hp:50, speed:0.5, atk:1, weight:10 },
}

// BOSS配置
export const BOSSES = {
  朱德: { key:'朱德', wave:6,  hp:500,   speed:0.8, skill:'封鎖' },
  林彪: { key:'林彪', wave:12, hp:1500,  speed:1.0, skill:'摧魂' },
  德懷: { key:'德懷', wave:18, hp:3000,  speed:0.9, skill:'召魂' },
  恩來: { key:'恩來', wave:24, hp:6000,  speed:1.1, skill:'滲透' },
  澤東: { key:'澤東', wave:30, hp:50000, speed:0.7, skill:'人海' },
}

// 地图
export const MAPS = [
  { id:'songhu',   name:'淞滬', bgColor:'#8b7355' },
  { id:'xubing',   name:'徐蚌', bgColor:'#6b8c42' },
  { id:'liaoshen', name:'遼瀋', bgColor:'#78909c' },
  { id:'pingjin',  name:'平津', bgColor:'#a1887f' },
  { id:'dujiang',  name:'渡江', bgColor:'#4fc3f7' },
]
