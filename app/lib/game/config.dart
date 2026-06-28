// 遊戲核心配置 — 從 ../src/game/config.js 移植
// 修改遊戲規則時，兩端同步更新

import 'dart:math';

// ── 棋盤常數 ────────────────────────────────────────
const int kRows = 5;
const int kCols = 8;
const int kHandSize = 5;
const int kInitialFood = 20;
const int kFoodPerKill = 1;
const int kFoodOnHit = 10;
const int kJiangInitialHp = 3;
const int kRecruitBaseCost = 10;
const int kRecruitCostIncrement = 2;
const int kWaveIntervalMs = 10000;

// ── 路線（[row, col] 順序：從营到蔣） ───────────────
const List<List<int>> kPlayerPath = [
  [4,0],[3,0],[2,0],[1,0],[0,0],
  [0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[0,7],
  [1,7],[2,7],[3,7],[4,7],
];
const List<List<int>> kAiPath = [
  [0,7],[1,7],[2,7],[3,7],[4,7],
  [4,6],[4,5],[4,4],[4,3],[4,2],[4,1],[4,0],
  [3,0],[2,0],[1,0],[0,0],
];

// 特殊格位置
const List<int> kPlayerYingCell  = [4, 0];
const List<int> kPlayerJiangCell = [4, 7];
const List<int> kAiYingCell      = [0, 7];
const List<int> kAiJiangCell     = [0, 0];

// 初始解鎖格
const List<List<int>> kInitialUnlocked = [
  [1,1],[1,2],[1,3],[2,1],[2,2],[2,3],
];
const List<List<int>> kAiInitialUnlocked = [
  [2,4],[2,5],[2,6],[3,4],[3,5],[3,6],
];

// ── 兵種配置 ─────────────────────────────────────────
class UnitDef {
  final String key;
  final String name;
  final String attackType; // 'single' | 'pierce' | 'area'
  final double atk;
  final double atkSpeed;   // 每秒攻擊次數
  final int range;         // 格子數
  final int maxLevel;
  const UnitDef({
    required this.key, required this.name, required this.attackType,
    required this.atk, required this.atkSpeed, required this.range,
    this.maxLevel = 5,
  });
}

const Map<String, UnitDef> kBasicUnits = {
  '步': UnitDef(key:'步', name:'步兵',   attackType:'single', atk:3.0, atkSpeed:1.25, range:1),
  '炮': UnitDef(key:'炮', name:'炮兵',   attackType:'pierce', atk:2.0, atkSpeed:1.25, range:3),
  '槍': UnitDef(key:'槍', name:'機槍手', attackType:'single', atk:2.0, atkSpeed:1.25, range:2),
  '坦': UnitDef(key:'坦', name:'坦克',   attackType:'area',   atk:2.0, atkSpeed:1.25, range:1),
};

class GeneralDef {
  final String key;
  final String fullName;
  final List<String> chars;
  final double atk;
  final double atkSpeed;
  final String attackType;
  final int range;
  final String skill;
  const GeneralDef({
    required this.key, required this.fullName, required this.chars,
    required this.atk, required this.atkSpeed, required this.attackType,
    required this.range, required this.skill,
  });
}

const Map<String, GeneralDef> kGenerals = {
  '立人': GeneralDef(key:'立人', fullName:'孫立人', chars:['立','人'], atk:8, atkSpeed:2.0, attackType:'area',   range:2, skill:'鐵拳'),
  '崇禧': GeneralDef(key:'崇禧', fullName:'白崇禧', chars:['崇','禧'], atk:7, atkSpeed:1.5, attackType:'pierce', range:3, skill:'謀略'),
  '薛岳': GeneralDef(key:'薛岳', fullName:'薛岳',   chars:['薛','岳'], atk:9, atkSpeed:1.75,attackType:'single', range:2, skill:'天爐'),
  '靈甫': GeneralDef(key:'靈甫', fullName:'張靈甫', chars:['靈','甫'], atk:8, atkSpeed:2.0, attackType:'area',   range:2, skill:'突擊'),
  '宗南': GeneralDef(key:'宗南', fullName:'胡宗南', chars:['宗','南'], atk:6, atkSpeed:1.5, attackType:'single', range:2, skill:'守備'),
  '耀湘': GeneralDef(key:'耀湘', fullName:'廖耀湘', chars:['耀','湘'], atk:7, atkSpeed:1.75,attackType:'pierce', range:3, skill:'鋼甲'),
};

class EnemyDef {
  final String key;
  final String name;
  final double hp;
  final double speed;
  final double atk;
  final int weight;
  const EnemyDef({
    required this.key, required this.name, required this.hp,
    required this.speed, required this.atk, required this.weight,
  });
}

const Map<String, EnemyDef> kEnemyTypes = {
  '匪': EnemyDef(key:'匪', name:'普通共匪', hp:9,  speed:1.0, atk:1, weight:40),
  '共': EnemyDef(key:'共', name:'精英共軍', hp:25, speed:1.3, atk:1, weight:25),
  '赤': EnemyDef(key:'赤', name:'赤衛隊',   hp:6,  speed:1.8, atk:1, weight:25),
  '寇': EnemyDef(key:'寇', name:'重裝共寇', hp:50, speed:0.5, atk:1, weight:10),
};

class BossDef {
  final String key;
  final int wave;
  final double hp;
  final double speed;
  final String skill;
  const BossDef({
    required this.key, required this.wave, required this.hp,
    required this.speed, required this.skill,
  });
}

const Map<String, BossDef> kBosses = {
  '朱德': BossDef(key:'朱德', wave:6,  hp:500,   speed:0.8, skill:'封鎖'),
  '林彪': BossDef(key:'林彪', wave:12, hp:1500,  speed:1.0, skill:'摧魂'),
  '德懷': BossDef(key:'德懷', wave:18, hp:3000,  speed:0.9, skill:'召魂'),
  '恩來': BossDef(key:'恩來', wave:24, hp:6000,  speed:1.1, skill:'滲透'),
  '澤東': BossDef(key:'澤東', wave:30, hp:50000, speed:0.7, skill:'人海'),
};

class MapDef {
  final String id;
  final String name;
  final int bgColor; // 0xFFrrggbb
  const MapDef({required this.id, required this.name, required this.bgColor});
}

const List<MapDef> kMaps = [
  MapDef(id:'songhu',   name:'淞滬', bgColor:0xFF8b7355),
  MapDef(id:'xubing',   name:'徐蚌', bgColor:0xFF6b8c42),
  MapDef(id:'liaoshen', name:'遼瀋', bgColor:0xFF78909c),
  MapDef(id:'pingjin',  name:'平津', bgColor:0xFFa1887f),
  MapDef(id:'dujiang',  name:'渡江', bgColor:0xFF4fc3f7),
];

// ── 工具函數 ─────────────────────────────────────────
int getRecruitCost(int times) => kRecruitBaseCost + times * kRecruitCostIncrement;

int getWaveEnemyCount(int wave) => min(2 + wave, 20); // wave1→3, wave2→4, 對齊Vue: 3+(wave-1)

double getWaveHpMult(int wave) {
  if (wave <= 1) return 1.0;
  double mult = 1.0;
  for (int i = 1; i < wave; i++) mult *= 1.25;
  return mult;
}

// 路線進度 → 格子座標
List<int> getPathCell(double progress, List<List<int>> path) {
  final idx = progress.floor().clamp(0, path.length - 1);
  return path[idx];
}

// 兩格距離（Chebyshev，與原 engine.js 一致）
int cellDist(int r1, int c1, int r2, int c2) {
  return max((r1 - r2).abs(), (c1 - c2).abs());
}

// 隨機手牌
final _rng = Random();
String randomEnemyKey() {
  final entries = kEnemyTypes.entries.toList();
  final totalWeight = entries.fold(0, (sum, e) => sum + e.value.weight);
  int r = _rng.nextInt(totalWeight);
  for (final e in entries) {
    r -= e.value.weight;
    if (r < 0) return e.key;
  }
  return entries.last.key;
}
