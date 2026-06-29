// 遊戲數據模型 — 所有狀態的數據類型定義
import 'package:flutter/foundation.dart';
import '../game/config.dart';

// ── 枚舉 ─────────────────────────────────────────────
enum GamePhase { home, prep, playing, paused, victory, defeat }
enum CellKind  { path, unlocked, locked }

// ── 手牌 ─────────────────────────────────────────────
@immutable
class HandCard {
  final String type;       // 'unit' | 'general' | 'general_char' | 'shovel'
  final String key;        // '步' | '立人' | '鏟' …
  final int level;
  final String? generalKey; // general_char 的武將key
  final String? charStr;    // general_char 顯示字

  const HandCard({
    required this.type,
    required this.key,
    this.level = 1,
    this.generalKey,
    this.charStr,
  });

  HandCard copyWith({int? level}) =>
      HandCard(type: type, key: key, level: level ?? this.level,
               generalKey: generalKey, charStr: charStr);

  @override
  bool operator ==(Object other) =>
      other is HandCard && type == other.type && key == other.key && level == other.level;

  @override
  int get hashCode => Object.hash(type, key, level);
}

// ── 等級成長係數（對齊 Vue LEVEL_FACTORS）────────────
const List<double> _kLevelFactors = [1.0, 1.5, 2.1, 2.73, 3.276];
double _levelFactor(int level) =>
    _kLevelFactors[(level - 1).clamp(0, _kLevelFactors.length - 1)];

// ── 棋盤單位 ──────────────────────────────────────────
@immutable
class Unit {
  final String id;
  final String type;       // 'unit' | 'general' | 'general_char'
  final String key;
  final int level;
  final int row;
  final int col;
  final bool attacking;
  final bool stunned;
  final String? generalKey;
  final String? charStr;   // general_char 顯示字

  const Unit({
    required this.id,
    required this.type,
    required this.key,
    this.level = 1,
    required this.row,
    required this.col,
    this.attacking = false,
    this.stunned = false,
    this.generalKey,
    this.charStr,
  });

  Unit copyWith({
    int? level, int? row, int? col,
    bool? attacking, bool? stunned,
  }) => Unit(
    id: id, type: type, key: key,
    level: level ?? this.level,
    row: row ?? this.row,
    col: col ?? this.col,
    attacking: attacking ?? this.attacking,
    stunned: stunned ?? this.stunned,
    generalKey: generalKey, charStr: charStr,
  );

  // 退回手牌
  HandCard toHandCard() {
    if (type == 'general_char') {
      return HandCard(type: 'general_char', key: key,
                      generalKey: generalKey, charStr: charStr);
    }
    return HandCard(
      type: type == 'general' ? 'general' : 'unit',
      key: key, level: level,
    );
  }

  // 顯示文字
  String get displayChar {
    if (type == 'general_char') return charStr ?? key[0];
    return key;
  }

  // 攻擊屬性（對齊 Vue getUnitAtk / getUnitAtkSpeed + LEVEL_FACTORS）
  double get atk {
    if (kGenerals.containsKey(key))   return kGenerals[key]!.atk + (level - 1) * 1.5;
    if (kBasicUnits.containsKey(key)) return kBasicUnits[key]!.atk * _levelFactor(level);
    return _levelFactor(level);
  }
  double get atkSpeed {
    if (kGenerals.containsKey(key))   return kGenerals[key]!.atkSpeed; // 武將不隨等級加速
    if (kBasicUnits.containsKey(key)) return kBasicUnits[key]!.atkSpeed * _levelFactor(level);
    return 1.0;
  }
  String get attackType {
    if (kBasicUnits.containsKey(key)) return kBasicUnits[key]!.attackType;
    if (kGenerals.containsKey(key))   return kGenerals[key]!.attackType;
    return 'single';
  }
  double get range {
    if (kBasicUnits.containsKey(key)) return kBasicUnits[key]!.range;
    if (kGenerals.containsKey(key))   return kGenerals[key]!.range;
    return 1.0;
  }
  int get maxLevel {
    if (kBasicUnits.containsKey(key)) return kBasicUnits[key]!.maxLevel;
    return 5;
  }
}

// ── 道具槽牌（已插入道具槽的道具）────────────────────
@immutable
class ItemCard {
  final String key;      // '農' …
  final String slotType; // 'passive' | 'active'
  const ItemCard({required this.key, required this.slotType});
}

// ── 棋盤格子 ──────────────────────────────────────────
@immutable
class Cell {
  final CellKind kind;
  final Unit? unit;
  const Cell({required this.kind, this.unit});

  Cell copyWith({CellKind? kind, Unit? unit, bool clearUnit = false}) => Cell(
    kind: kind ?? this.kind,
    unit: clearUnit ? null : (unit ?? this.unit),
  );
}

// ── 敵軍（render state，由引擎維護，不放 Riverpod 以避免 60fps setState） ──
class EnemyState {
  final String id;
  final String key;
  double pathProgress;
  double hp;
  final double maxHp;
  final double speed;
  final bool isBoss;

  EnemyState({
    required this.id, required this.key,
    required this.pathProgress, required this.hp,
    required this.maxHp, required this.speed,
    required this.isBoss,
  });

  // 顯示顏色
  static const Map<String, int> colors = {
    '匪': 0xFF555555,
    '共': 0xFF1a237e,
    '赤': 0xFFc62828,
    '寇': 0xFF4e342e,
    '朱德': 0xFFb71c1c,
    '林彪': 0xFF880e4f,
    '德懷': 0xFF4a148c,
    '恩來': 0xFF1a237e,
    '澤東': 0xFFbf360c,
  };
  int get color => colors[key] ?? 0xFF555555;
}

// ── 投射物（render state，由引擎維護） ───────────────
class ProjectileState {
  final String id;
  final String kind;   // 'slash' | 'bullet' | 'shell' | 'arrow'
  final String side;   // 'player' | 'ai'
  final double sx, sy, ex, ey;
  final double spawnMs;
  final double durationMs;
  double elapsedMs = 0;

  ProjectileState({
    required this.id, required this.kind, required this.side,
    required this.sx, required this.sy, required this.ex, required this.ey,
    required this.spawnMs, required this.durationMs,
  });

  double get progress => (elapsedMs / durationMs).clamp(0.0, 1.0);
  bool get done => elapsedMs >= durationMs;

  static const Map<String, String> chars = {
    'slash': '✦', 'bullet': '·', 'shell': '●', 'arrow': '→',
  };
  String get char => chars[kind] ?? '·';

  static const Map<String, double> durations = {
    'slash': 250, 'bullet': 300, 'shell': 350, 'arrow': 280,
  };
}

// ── UI 狀態（Riverpod 管理，只更新 UI 相關部分） ────────
@immutable
class GameUiState {
  final GamePhase phase;
  final String mapName;
  final int wave;
  final bool bossWarning;

  // 玩家 UI 相關
  final int playerFood;
  final int playerRecruitTimes;
  final int playerRecruitVersion;
  final List<HandCard?> playerHand;
  final List<ItemCard?> playerItemSlots; // [0-1]=主動槽, [2-7]=被動槽
  final List<List<Cell>> playerBoard;
  final int playerJiangHp;
  final int playerJiangMaxHp;
  final int playerScore;
  final bool playerDanger;
  // AI UI 相關
  final int aiFood;
  final int aiRecruitTimes;
  final List<List<Cell>> aiBoard;
  final int aiJiangHp;
  final int aiJiangMaxHp;
  final bool aiDanger;

  const GameUiState({
    this.phase = GamePhase.home,
    this.mapName = '立人與中正',
    this.wave = 1,
    this.bossWarning = false,
    this.playerFood = kInitialFood,
    this.playerRecruitTimes = 0,
    this.playerRecruitVersion = 0,
    required this.playerHand,
    this.playerItemSlots = const [null,null,null,null,null,null,null,null],
    required this.playerBoard,
    this.playerJiangHp = kJiangInitialHp,
    this.playerJiangMaxHp = kJiangInitialHp,
    this.playerScore = 0,
    this.playerDanger = false,
    this.aiFood = kInitialFood,
    this.aiRecruitTimes = 0,
    required this.aiBoard,
    this.aiJiangHp = kJiangInitialHp,
    this.aiJiangMaxHp = kJiangInitialHp,
    this.aiDanger = false,
  });

  int get playerRecruitCost => getRecruitCost(playerRecruitTimes);
  bool get canPlayerRecruit => playerFood >= playerRecruitCost;

  GameUiState copyWith({
    GamePhase? phase, String? mapName, int? wave, bool? bossWarning,
    int? playerFood, int? playerRecruitTimes, int? playerRecruitVersion,
    List<HandCard?>? playerHand, List<ItemCard?>? playerItemSlots,
    List<List<Cell>>? playerBoard,
    int? playerJiangHp, int? playerJiangMaxHp, int? playerScore,
    bool? playerDanger,
    int? aiFood, int? aiRecruitTimes, List<List<Cell>>? aiBoard,
    int? aiJiangHp, int? aiJiangMaxHp, bool? aiDanger,
  }) {
    return GameUiState(
      phase: phase ?? this.phase,
      mapName: mapName ?? this.mapName,
      wave: wave ?? this.wave,
      bossWarning: bossWarning ?? this.bossWarning,
      playerFood: playerFood ?? this.playerFood,
      playerRecruitTimes: playerRecruitTimes ?? this.playerRecruitTimes,
      playerRecruitVersion: playerRecruitVersion ?? this.playerRecruitVersion,
      playerHand: playerHand ?? this.playerHand,
      playerItemSlots: playerItemSlots ?? this.playerItemSlots,
      playerBoard: playerBoard ?? this.playerBoard,
      playerJiangHp: playerJiangHp ?? this.playerJiangHp,
      playerJiangMaxHp: playerJiangMaxHp ?? this.playerJiangMaxHp,
      playerScore: playerScore ?? this.playerScore,
      playerDanger: playerDanger ?? this.playerDanger,
      aiFood: aiFood ?? this.aiFood,
      aiRecruitTimes: aiRecruitTimes ?? this.aiRecruitTimes,
      aiBoard: aiBoard ?? this.aiBoard,
      aiJiangHp: aiJiangHp ?? this.aiJiangHp,
      aiJiangMaxHp: aiJiangMaxHp ?? this.aiJiangMaxHp,
      aiDanger: aiDanger ?? this.aiDanger,
    );
  }
}

// ── 棋盤工廠 ──────────────────────────────────────────
List<List<Cell>> createBoard(bool isAi) {
  final pathSet = <String>{};
  final path = isAi ? kAiPath : kPlayerPath;
  for (final p in path) pathSet.add('${p[0]},${p[1]}');

  final unlocked = isAi ? kAiInitialUnlocked : kInitialUnlocked;
  final unlockedSet = <String>{};
  for (final p in unlocked) unlockedSet.add('${p[0]},${p[1]}');

  return List.generate(kRows, (r) =>
    List.generate(kCols, (c) {
      final key = '$r,$c';
      if (pathSet.contains(key))    return const Cell(kind: CellKind.path);
      if (unlockedSet.contains(key)) return const Cell(kind: CellKind.unlocked);
      return const Cell(kind: CellKind.locked);
    }),
  );
}
