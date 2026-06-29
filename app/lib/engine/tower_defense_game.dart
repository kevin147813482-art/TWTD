// 遊戲引擎 — flame FlameGame
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../game/config.dart';
import '../state/models.dart';
import '../state/game_notifier.dart';

// ── 引擎私有 render state ──────────────────────────────
class _Enemy {
  final String id;
  final String key;
  double pathProgress;
  double hp;
  final double maxHp;
  final double speed;
  final bool isBoss;
  bool markedDead = false;
  // P0-2 技能：眩暈剩餘時間（ms），>0 時凍結移動
  double stunnedMs = 0.0;

  _Enemy({
    required this.id, required this.key,
    required this.pathProgress, required this.hp,
    required this.maxHp, required this.speed,
    required this.isBoss,
  });

  int get color => EnemyState.colors[key] ?? 0xFF555555;
}

class _Projectile {
  final String id;
  final String kind;
  final String side;
  final double sx, sy, ex, ey;
  final double durationMs;
  double elapsedMs = 0;

  _Projectile({
    required this.id, required this.kind, required this.side,
    required this.sx, required this.sy, required this.ex, required this.ey,
    required this.durationMs,
  });

  double get t => (elapsedMs / durationMs).clamp(0.0, 1.0);
  bool get done => elapsedMs >= durationMs;

  static const Map<String, String> _chars = {
    'slash': '✦', 'bullet': '·', 'shell': '●', 'arrow': '→', 'skill': '★',
  };
  String get char => _chars[kind] ?? '·';
  bool get isSkill => kind == 'skill';
}

// ── 引擎 ──────────────────────────────────────────────
class TowerDefenseGame extends FlameGame {
  final GameNotifier notifier;

  TowerDefenseGame({required this.notifier});

  // render state（不走 Riverpod，60fps 更新）
  final List<_Enemy> _playerEnemies = [];
  final List<_Enemy> _aiEnemies     = [];
  final List<_Projectile> _projectiles = [];

  // 蔣行走進度（prep 動畫，純引擎狀態）
  double _playerJiangProgress = 0;
  double _aiJiangProgress     = 0;
  bool _prepDone = false;

  // 攻擊冷卻
  final Map<String, double> _cooldowns = {};
  // 技能：每個武將的攻擊次數計數，每3次觸發技能
  final Map<String, int> _skillCharges = {};
  // 武將擊殺累積（key = generalKey，達閾值升級）
  final Map<String, int> _generalKills = {};
  // 打瞌睡動畫計時（累積ms，用於閃爍 z）
  double _sleepAnimMs = 0;

  // 波次計時
  double _waveTimerMs   = 0;
  int _spawnedThisWave  = 0;
  bool _wavePending     = false;

  // AI 計時 + 手牌（引擎內部，不顯示在 UI）
  double _aiTimerMs = 0;
  List<HandCard?> _aiHand = List.filled(kHandSize, null);
  bool get _aiHasCards => _aiHand.any((c) => c != null);
  final _rng = Random();
  int _idCounter = 0;
  String _uid(String p) => '${p}_${++_idCounter}';

  // 佈局
  double _cellSize    = 44;
  double _boardOffsetX = 0;
  double _aiBoardY    = 0;
  double _playerBoardY = 0;

  static const double _topBarH  = 58;
  static const double _dividerH = 22;
  static const double _bottomH  = 200;

  // ── 延後執行 notifier 狀態變更（避免 build 期修改 provider） ──
  void _postFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) => fn());
  }

  // ── FlameGame lifecycle ──────────────────────────────

  @override
  Color backgroundColor() => const Color(0xFF1e1e1e);

  @override
  Future<void> onLoad() async {
    _updateLayout();
    overlays.add('topBar');
    overlays.add('handArea');
    // 武將升級回調：引擎通知 notifier 更新字牌等級
    notifier.onGeneralLevelUp = (generalKey, newLevel) {
      notifier.generalLevelUp(generalKey, newLevel);
    };
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    _updateLayout();
  }

  void _updateLayout() {
    final availH = size.y - _topBarH - _dividerH - _bottomH;
    final cellByW = size.x / kCols;
    final cellByH = availH / (kRows * 2);
    _cellSize = min(cellByW, cellByH);

    final boardW = _cellSize * kCols;
    _boardOffsetX = (size.x - boardW) / 2;
    _aiBoardY     = _topBarH;
    _playerBoardY = _topBarH + kRows * _cellSize + _dividerH;
  }

  // ── Update ──────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);
    final phase = notifier.state.phase;
    if (phase == GamePhase.prep) {
      _updatePrep(dt);
      _aiTick(dt * 1000);
      return;
    }
    if (phase == GamePhase.paused || phase != GamePhase.playing) return;

    final dtMs = dt * 1000;
    _moveEnemies(dtMs);
    _processAttacks(dtMs);
    _updateProjectiles(dtMs);
    _waveScheduler(dtMs);
    _aiTick(dtMs);
    _sleepAnimMs += dtMs;
  }

  // 準備階段：蔣從营走到蔣位置
  void _updatePrep(double dt) {
    if (_prepDone) return;
    const speed = 1.5; // 15步 / 1.5 = 10秒，對齊 Vue PREP_DURATION=10000ms
    _playerJiangProgress = min(
        _playerJiangProgress + speed * dt, kPlayerPath.length - 1.0);
    _aiJiangProgress = min(
        _aiJiangProgress + speed * dt, kAiPath.length - 1.0);

    if (_playerJiangProgress >= kPlayerPath.length - 1 &&
        _aiJiangProgress >= kAiPath.length - 1) {
      _prepDone = true;
      _postFrame(() {
        notifier.setPhase(GamePhase.playing);
        _spawnWave();
      });
    }
  }

  // ── 敵軍移動 ────────────────────────────────────────

  void _moveEnemies(double dtMs) {
    // 反推自截圖：匪兵(speed=1.0)穿越15格路徑≈21秒 → 0.714格/秒 → 0.000714
    const speedScale = 0.00072;
    for (final e in _playerEnemies) {
      if (e.markedDead) continue;
      // P0-2 眩暈：倒計時，凍結移動
      if (e.stunnedMs > 0) { e.stunnedMs -= dtMs; continue; }
      e.pathProgress += e.speed * dtMs * speedScale;
      if (e.pathProgress >= kPlayerPath.length - 1) {
        e.markedDead = true;
        _postFrame(() => notifier.onPlayerJiangHit());
      }
    }
    for (final e in _aiEnemies) {
      if (e.markedDead) continue;
      if (e.stunnedMs > 0) { e.stunnedMs -= dtMs; continue; }
      e.pathProgress += e.speed * dtMs * speedScale;
      if (e.pathProgress >= kAiPath.length - 1) {
        e.markedDead = true;
        _postFrame(() => notifier.onAiJiangHit());
      }
    }
    _playerEnemies.removeWhere((e) => e.markedDead);
    _aiEnemies.removeWhere((e) => e.markedDead);
  }

  // ── 攻擊判定 ────────────────────────────────────────

  void _processAttacks(double dtMs) {
    final s = notifier.state;
    _processSideAttacks(s.playerBoard, _playerEnemies, 'player', dtMs,
        isAiPath: false, onKill: () => notifier.onPlayerEnemyKilled());
    _processSideAttacks(s.aiBoard, _aiEnemies, 'ai', dtMs,
        isAiPath: true, onKill: () => notifier.onAiEnemyKilled());
  }

  // 若 unit 是某武將配對的「主字」（chars[0]），返回 GeneralDef，否則 null
  GeneralDef? _getActivatedGeneral(Unit unit, int r, int c, List<List<Cell>> board) {
    if (unit.type != 'general_char') return null;
    final gKey = unit.generalKey;
    if (gKey == null) return null;
    final gDef = kGenerals[gKey];
    if (gDef == null) return null;
    final myChar = unit.charStr ?? unit.key;
    if (myChar != gDef.chars[0]) return null; // 不是主字

    // 右邊鄰格是次字？
    if (c + 1 < kCols) {
      final right = board[r][c + 1].unit;
      if (right?.type == 'general_char' && right?.generalKey == gKey &&
          (right?.charStr ?? right?.key) == gDef.chars[1]) return gDef;
    }
    // 下方鄰格是次字？
    if (r + 1 < kRows) {
      final below = board[r + 1][c].unit;
      if (below?.type == 'general_char' && below?.generalKey == gKey &&
          (below?.charStr ?? below?.key) == gDef.chars[1]) return gDef;
    }
    return null;
  }

  // 是否為某武將配對的「次字」（chars[1]，主字在左/上方）
  bool _isGeneralSecondary(Unit unit, int r, int c, List<List<Cell>> board) {
    if (unit.type != 'general_char') return false;
    final gKey = unit.generalKey;
    if (gKey == null) return false;
    final gDef = kGenerals[gKey];
    if (gDef == null) return false;
    final myChar = unit.charStr ?? unit.key;
    if (myChar != gDef.chars[1]) return false;

    if (c > 0) {
      final left = board[r][c - 1].unit;
      if (left?.type == 'general_char' && left?.generalKey == gKey &&
          (left?.charStr ?? left?.key) == gDef.chars[0]) return true;
    }
    if (r > 0) {
      final above = board[r - 1][c].unit;
      if (above?.type == 'general_char' && above?.generalKey == gKey &&
          (above?.charStr ?? above?.key) == gDef.chars[0]) return true;
    }
    return false;
  }

  void _processSideAttacks(
    List<List<Cell>> board,
    List<_Enemy> enemies,
    String side,
    double dtMs, {
    required bool isAiPath,
    required VoidCallback onKill,
  }) {
    final path = isAiPath ? kAiPath : kPlayerPath;

    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final unit = board[r][c].unit;
        if (unit == null) continue;

        // ── 武將字牌：solo 或次字不攻擊；主字且配對才攻擊 ──
        if (unit.type == 'general_char') {
          final gDef = _getActivatedGeneral(unit, r, c, board);
          if (gDef == null) continue; // 未激活（solo 或次字）

          final gKey = unit.generalKey!;
          final level = unit.level;
          final atk      = gDef.atk + (level - 1) * 1.5;
          final atkSpeed = gDef.atkSpeed;
          final range    = gDef.range;
          final attackType = gDef.attackType;
          final cdKey = '${side}_gen_${r}_$c';

          _cooldowns.putIfAbsent(cdKey, () => 9999);
          _cooldowns[cdKey] = _cooldowns[cdKey]! + dtMs;
          if (_cooldowns[cdKey]! < 1000 / atkSpeed) continue;

          final targets = <_Enemy>[];
          for (final e in enemies) {
            if (e.markedDead) continue;
            final pathCell = getPathCell(e.pathProgress, path);
            if (cellDist(r, c, pathCell[0], pathCell[1]) <= range) targets.add(e);
          }
          if (targets.isEmpty) continue;
          targets.sort((a, b) => b.pathProgress.compareTo(a.pathProgress));
          _cooldowns[cdKey] = 0;

          // 武將擊殺 onKill 包含升級追蹤
          void onGeneralKill() {
            onKill();
            if (level >= 5) return;
            final kills = (_generalKills[gKey] ?? 0) + 1;
            final needed = level * 5;
            if (kills >= needed) {
              _generalKills[gKey] = 0;
              _postFrame(() => notifier.generalLevelUp(gKey, level + 1));
            } else {
              _generalKills[gKey] = kills;
            }
          }

          // 技能計數
          _skillCharges[cdKey] = (_skillCharges[cdKey] ?? 0) + 1;
          if (_skillCharges[cdKey]! % 3 == 0) {
            _fireGeneralSkillFromDef(
                gDef, atk, range, attackType,
                targets, enemies, side, r, c, path, onGeneralKill);
            continue;
          }

          // 普攻
          switch (attackType) {
            case 'single':
              _dealDamage(targets[0], atk, onGeneralKill);
              _spawnProjectile(side, 'bullet', r, c, targets[0].pathProgress, path);
            case 'pierce':
              for (final t in targets) _dealDamage(t, atk, onGeneralKill);
              if (targets.isNotEmpty) _spawnProjectile(side, 'arrow', r, c, targets[0].pathProgress, path);
            case 'area':
              for (int ti = 0; ti < targets.length; ti++) {
                _dealDamage(targets[ti], ti == 0 ? atk : atk * 0.5, onGeneralKill);
              }
              if (targets.isNotEmpty) _spawnProjectile(side, 'shell', r, c, targets[0].pathProgress, path);
          }
          continue;
        }

        // ── 一般單位 ──
        final cdKey = unit.id;
        _cooldowns.putIfAbsent(cdKey, () => 9999);
        _cooldowns[cdKey] = _cooldowns[cdKey]! + dtMs;

        final cooldownMs = 1000 / unit.atkSpeed;
        if (_cooldowns[cdKey]! < cooldownMs) continue;

        final targets = <_Enemy>[];
        for (final e in enemies) {
          if (e.markedDead) continue;
          final pathCell = getPathCell(e.pathProgress, path);
          if (cellDist(r, c, pathCell[0], pathCell[1]) <= unit.range) {
            targets.add(e);
          }
        }
        if (targets.isEmpty) continue;

        targets.sort((a, b) => b.pathProgress.compareTo(a.pathProgress));
        _cooldowns[cdKey] = 0;

        switch (unit.attackType) {
          case 'single':
            _dealDamage(targets[0], unit.atk, onKill);
            _spawnProjectile(side, 'bullet', r, c, targets[0].pathProgress, path);
          case 'pierce':
            for (final t in targets) _dealDamage(t, unit.atk, onKill);
            if (targets.isNotEmpty) {
              _spawnProjectile(side, 'arrow', r, c, targets[0].pathProgress, path);
            }
          case 'area':
            for (int ti = 0; ti < targets.length; ti++) {
              _dealDamage(targets[ti], ti == 0 ? unit.atk : unit.atk * 0.5, onKill);
            }
            if (targets.isNotEmpty) {
              _spawnProjectile(side, 'shell', r, c, targets[0].pathProgress, path);
            }
        }
      }
    }
  }

  void _dealDamage(_Enemy e, double dmg, VoidCallback onKill) {
    e.hp -= dmg;
    if (e.hp <= 0 && !e.markedDead) {
      e.markedDead = true;
      _postFrame(onKill);
    }
  }

  // 武將技能：按 attackType 分三種效果
  // pierce(謀略/鋼甲)：全場貫穿 1.5× | area(突擊/鐵拳)：範圍眩暈1.5s | single(天爐/守備)：3× 爆傷
  void _fireGeneralSkillFromDef(
    GeneralDef gDef, double atk, double range, String attackType,
    List<_Enemy> targets, List<_Enemy> enemies,
    String side, int r, int c, List<List<int>> path, VoidCallback onKill,
  ) {
    final targetCell = targets.isNotEmpty
        ? getPathCell(targets[0].pathProgress, path)
        : path[path.length ~/ 2];

    switch (attackType) {
      case 'pierce':
        for (final e in enemies) {
          if (!e.markedDead) _dealDamage(e, atk * 1.5, onKill);
        }
        _spawnSkillProjectile(side, r, c, path[path.length ~/ 2], path);
      case 'area':
        for (final e in enemies) {
          if (e.markedDead) continue;
          final ec = getPathCell(e.pathProgress, path);
          if (cellDist(r, c, ec[0], ec[1]) <= range * 2) e.stunnedMs = 1500;
        }
        _spawnSkillProjectile(side, r, c, targetCell, path);
      case 'single':
      default:
        if (targets.isNotEmpty) {
          _dealDamage(targets[0], atk * 3, onKill);
          _spawnSkillProjectile(side, r, c,
              getPathCell(targets[0].pathProgress, path), path);
        }
    }
  }

  void _spawnSkillProjectile(
      String side, int ur, int uc, List<int> targetCell, List<List<int>> path) {
    final sourceIsAiBoard = side == 'ai';
    final src = _cellCenter(ur, uc, isAiBoard: sourceIsAiBoard);
    final dst = _cellCenter(targetCell[0], targetCell[1], isAiBoard: sourceIsAiBoard);
    _projectiles.add(_Projectile(
      id: _uid('sk'), kind: 'skill', side: side,
      sx: src.dx, sy: src.dy, ex: dst.dx, ey: dst.dy,
      durationMs: 500,
    ));
  }

  // ── 投射物 ──────────────────────────────────────────

  void _spawnProjectile(String side, String kind, int ur, int uc,
      double targetProgress, List<List<int>> path) {
    final durationMs = ProjectileState.durations[kind] ?? 300;
    final targetCell = getPathCell(targetProgress, path);

    final sourceIsAiBoard = side == 'ai';
    final sourcePos = _cellCenter(ur, uc, isAiBoard: sourceIsAiBoard);
    final targetPos = _cellCenter(
        targetCell[0], targetCell[1], isAiBoard: sourceIsAiBoard);

    _projectiles.add(_Projectile(
      id: _uid('p'), kind: kind, side: side,
      sx: sourcePos.dx, sy: sourcePos.dy,
      ex: targetPos.dx, ey: targetPos.dy,
      durationMs: durationMs,
    ));
  }

  void _updateProjectiles(double dtMs) {
    for (final p in _projectiles) p.elapsedMs += dtMs;
    _projectiles.removeWhere((p) => p.done);
  }

  // ── 波次生成 ────────────────────────────────────────

  void _waveScheduler(double dtMs) {
    if (_wavePending) return;
    _waveTimerMs += dtMs;
    if (_waveTimerMs >= kWaveIntervalMs) {
      _waveTimerMs = 0;
      _spawnWave();
    }
  }

  void _spawnWave() {
    final wave = notifier.state.wave;
    final count = getWaveEnemyCount(wave);
    final hpMult = getWaveHpMult(wave);

    BossDef? boss;
    for (final b in kBosses.values) {
      if (b.wave == wave) { boss = b; break; }
    }

    if (boss != null) {
      _postFrame(() => notifier.setBossWarning(true));
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (notifier.state.phase != GamePhase.playing) return;
        _spawnEnemy(_playerEnemies, boss!.key,
            boss.hp * hpMult, boss.speed, isBoss: true);
        _spawnEnemy(_aiEnemies, boss.key,
            boss.hp * hpMult, boss.speed, isBoss: true);
        notifier.setBossWarning(false);
        notifier.nextWave();
      });
      return;
    }

    _spawnedThisWave = 0;
    _wavePending = true;
    _scheduleSpawnLoop(count, hpMult);
  }

  void _scheduleSpawnLoop(int total, double hpMult) {
    if (_spawnedThisWave >= total) {
      _wavePending = false;
      notifier.nextWave();
      return;
    }
    final delay = _spawnedThisWave == 0 ? 0 : 1200; // 對齊 Vue delay: i * 1200
    Future.delayed(Duration(milliseconds: delay), () {
      if (notifier.state.phase != GamePhase.playing) return;
      final key = _randomEnemy();
      final def = kEnemyTypes[key]!;
      _spawnEnemy(_playerEnemies, key, def.hp * hpMult, def.speed);
      _spawnEnemy(_aiEnemies,     key, def.hp * hpMult, def.speed);
      _spawnedThisWave++;
      _scheduleSpawnLoop(total, hpMult);
    });
  }

  void _spawnEnemy(List<_Enemy> list, String key, double hp, double speed,
      {bool isBoss = false}) {
    list.add(_Enemy(
      id: _uid(isBoss ? 'boss' : 'e'),
      key: key, pathProgress: 0,
      hp: hp, maxHp: hp,
      speed: speed, isBoss: isBoss,
    ));
  }

  // 對齊 Vue getWaveEnemies 的波次動態分配
  String _randomEnemy() {
    final wave = notifier.state.wave;
    final r = _rng.nextDouble();
    if (wave <= 3)      return r < 0.80 ? '匪' : r < 0.95 ? '赤' : '共';
    if (wave <= 5)      return r < 0.50 ? '匪' : r < 0.75 ? '赤' : r < 0.90 ? '共' : '寇';
    if (wave <= 8)      return r < 0.30 ? '匪' : r < 0.55 ? '赤' : r < 0.80 ? '共' : '寇';
    return               r < 0.15 ? '匪' : r < 0.40 ? '赤' : r < 0.70 ? '共' : '寇';
  }

  // ── AI 行為 ──────────────────────────────────────────

  // 是否有空格可以放牌
  bool _aiHasVacant(GameUiState s) {
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final cell = s.aiBoard[r][c];
        if (cell.kind == CellKind.unlocked && cell.unit == null) return true;
      }
    }
    return false;
  }

  // 嘗試手牌合并（同種同級基礎兵升一級），成功返回 true
  bool _aiTryMergeHand() {
    for (int i = 0; i < kHandSize; i++) {
      final ci = _aiHand[i];
      if (ci == null || ci.type == 'general_char' || ci.type == 'shovel') continue;
      for (int j = i + 1; j < kHandSize; j++) {
        final cj = _aiHand[j];
        if (cj == null) continue;
        if (ci.type == cj.type && ci.key == cj.key && ci.level == cj.level &&
            ci.level < (kBasicUnits[ci.key]?.maxLevel ?? 5)) {
          _aiHand[i] = ci.copyWith(level: ci.level + 1);
          _aiHand[j] = null;
          return true;
        }
      }
    }
    return false;
  }

  void _aiTick(double dtMs) {
    _aiTimerMs += dtMs;
    // 操作間隔隨波次縮短（wave1=1.5~2.5s, wave10+=0.8~1.5s）
    final wave = notifier.state.wave;
    final minMs = max(800.0, 1500.0 - wave * 50.0);
    final maxMs = max(1500.0, 2500.0 - wave * 100.0);
    final interval = minMs + _rng.nextDouble() * (maxMs - minMs);
    if (_aiTimerMs < interval) return;
    _aiTimerMs = 0;

    _postFrame(() {
      final s = notifier.state;
      final cost = getRecruitCost(s.aiRecruitTimes);

      // Step 1: 手牌升級（合并同種同級）
      if (_aiTryMergeHand()) return;

      // Step 2: 有空格且有手牌 → 放一張（含武將配對優先邏輯）
      if (_aiHasCards && _aiHasVacant(s)) {
        _aiDeployOneCard();
        return;
      }

      // Step 3: 棋盤相鄰合并升級
      if (notifier.aiMergeUnits()) return;

      // Step 4: 上面都做不了 → 招募（清空舊手牌換新牌），需糧食夠
      if (s.aiFood >= cost) {
        notifier.aiRecruit();
        _aiFillHand(); // 新5張牌覆蓋舊手牌（含未出完的牌也丟棄）
      }
      // 糧食不夠 → 等待，靠擊殺積累
    });
  }

  // 填 AI 手牌（概率完全對齊玩家，含鏟子 8%；AI 拿到鏟子會解鎖格子）
  void _aiFillHand() {
    final wave = notifier.state.wave;
    final generalChance = min(0.15 + wave * 0.01, 0.20);
    const shovelChance = 0.08;
    final basicKeys = kBasicUnits.keys.toList();
    final gKeys = kGenerals.keys.toList();
    _aiHand = List.generate(kHandSize, (_) {
      final r = _rng.nextDouble();
      if (r < generalChance) {
        final gKey = gKeys[_rng.nextInt(gKeys.length)];
        final g = kGenerals[gKey]!;
        final char = g.chars[_rng.nextInt(g.chars.length)];
        return HandCard(type: 'general_char', key: char, generalKey: gKey, charStr: char);
      } else if (r < generalChance + shovelChance) {
        return const HandCard(type: 'shovel', key: '鏟');
      } else {
        return HandCard(type: 'unit', key: basicKeys[_rng.nextInt(basicKeys.length)]);
      }
    });
  }

  // 從手牌放一張（有智能優先級；手牌合并由 _aiTick Step1 已處理）
  void _aiDeployOneCard() {
    final s = notifier.state;

    // 選出最高優先度的牌
    // 優先：武將字 chars[0]（好讓下輪 chars[1] 配對）
    int? pickIdx;

    // 找手牌裡配對可激活的武將字（手牌有兩個相同 generalKey → 優先出 chars[0]）
    for (int i = 0; i < kHandSize; i++) {
      final ci = _aiHand[i];
      if (ci == null || ci.type != 'general_char') continue;
      final gDef = kGenerals[ci.generalKey ?? ''];
      if (gDef == null) continue;
      if (ci.charStr != gDef.chars[0]) continue; // 只找主字
      for (int j = 0; j < kHandSize; j++) {
        if (i == j) continue;
        final cj = _aiHand[j];
        if (cj?.type == 'general_char' && cj?.generalKey == ci.generalKey &&
            cj?.charStr == gDef.chars[1]) {
          pickIdx = i; // 有配對，優先主字
          break;
        }
      }
      if (pickIdx != null) break;
    }

    // 次優先：棋盤上已有某 generalKey 主字 → 優先出手牌裡對應次字
    if (pickIdx == null) {
      for (int r = 0; r < kRows; r++) {
        for (int c = 0; c < kCols; c++) {
          final unit = s.aiBoard[r][c].unit;
          if (unit?.type != 'general_char') continue;
          final gDef = kGenerals[unit?.generalKey ?? ''];
          if (gDef == null) continue;
          if ((unit?.charStr ?? unit?.key) != gDef.chars[0]) continue;
          // 棋盤有主字 → 找手牌次字
          for (int i = 0; i < kHandSize; i++) {
            final ci = _aiHand[i];
            if (ci?.type == 'general_char' && ci?.generalKey == unit?.generalKey &&
                ci?.charStr == gDef.chars[1]) {
              pickIdx = i;
              break;
            }
          }
          if (pickIdx != null) break;
        }
        if (pickIdx != null) break;
      }
    }

    // 其餘：第一張非空牌
    pickIdx ??= _aiHand.indexWhere((c) => c != null);
    if (pickIdx == -1) return;

    final card = _aiHand[pickIdx]!;

    // 3. 鏟子：解鎖格子
    if (card.type == 'shovel') {
      notifier.aiUnlockCell();
      _aiHand[pickIdx] = null;
      return;
    }

    // 4. 找部署格
    final vacant = <List<int>>[];
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final cell = s.aiBoard[r][c];
        if (cell.kind == CellKind.unlocked && cell.unit == null) {
          vacant.add([r, c]);
        }
      }
    }
    if (vacant.isEmpty) return; // 棋盤滿由 _aiTick 上層處理

    List<int> bestPos;

    if (card.type == 'general_char') {
      final gKey = card.generalKey ?? '';
      final gDef = kGenerals[gKey];
      final isSecond = gDef != null && card.charStr == gDef.chars[1];

      // 若放次字，找棋盤主字旁邊的空格
      if (isSecond) {
        List<int>? adj;
        outer:
        for (int r = 0; r < kRows; r++) {
          for (int c = 0; c < kCols; c++) {
            final u = s.aiBoard[r][c].unit;
            if (u?.type != 'general_char' || u?.generalKey != gKey) continue;
            if ((u?.charStr ?? u?.key) != gDef.chars[0]) continue;
            // 優先右邊，其次下方
            for (final d in [[0,1],[1,0],[0,-1],[-1,0]]) {
              final nr = r + d[0]; final nc = c + d[1];
              if (nr < 0 || nr >= kRows || nc < 0 || nc >= kCols) continue;
              if (s.aiBoard[nr][nc].kind == CellKind.unlocked &&
                  s.aiBoard[nr][nc].unit == null) {
                adj = [nr, nc];
                break outer;
              }
            }
          }
        }
        bestPos = adj ?? vacant[_rng.nextInt(vacant.length)];
      } else {
        // 主字：靠近路線的格
        final near = vacant.where((p) =>
            p[1] == kCols - 2 || p[0] == kRows - 2 || p[1] == 1).toList();
        bestPos = (near.isNotEmpty ? near : vacant)[_rng.nextInt(
            (near.isNotEmpty ? near : vacant).length)];
      }
    } else {
      // 普通兵：靠近路線的格優先
      // 早期波次（wave<=3）有 40% 概率隨機放（模仿新手玩家不總是最優）
      // 後期波次降到 0%，全部策略性放置
      final wave = notifier.state.wave;
      final randomChance = max(0.0, 0.40 - wave * 0.06);
      if (_rng.nextDouble() < randomChance) {
        bestPos = vacant[_rng.nextInt(vacant.length)];
      } else {
        final near = vacant.where((p) =>
            p[1] == kCols - 2 || p[0] == kRows - 2 || p[1] == 1).toList();
        bestPos = (near.isNotEmpty ? near : vacant)[_rng.nextInt(
            (near.isNotEmpty ? near : vacant).length)];
      }
    }

    notifier.aiDeployUnit(
      card.key, bestPos[0], bestPos[1],
      level: card.level,
      type: card.type,
      generalKey: card.generalKey,
      charStr: card.charStr,
    );
    _aiHand[pickIdx] = null;
  }

  // ── Render ──────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final s = notifier.state;
    final inPrep = s.phase == GamePhase.prep;

    _renderBoard(canvas, s.aiBoard,
        isAi: true,
        jiangProgress: inPrep ? _aiJiangProgress : kAiPath.length.toDouble(),
        jiangHp: s.aiJiangHp, jiangMaxHp: s.aiJiangMaxHp,
        danger: s.aiDanger);
    _renderBoard(canvas, s.playerBoard,
        isAi: false,
        jiangProgress: inPrep ? _playerJiangProgress : kPlayerPath.length.toDouble(),
        jiangHp: s.playerJiangHp, jiangMaxHp: s.playerJiangMaxHp,
        danger: s.playerDanger);
    _renderDivider(canvas);
    _renderEnemies(canvas, _aiEnemies,     isAiPath: true);
    _renderEnemies(canvas, _playerEnemies, isAiPath: false);
    _renderProjectiles(canvas);
  }

  // ── Render helpers ───────────────────────────────────

  void _renderBoard(Canvas canvas, List<List<Cell>> board, {
    required bool isAi,
    required double jiangProgress,
    required int jiangHp,
    required int jiangMaxHp,
    bool danger = false,
  }) {
    final boardY   = isAi ? _aiBoardY : _playerBoardY;
    final path     = isAi ? kAiPath   : kPlayerPath;
    final isWalking = jiangProgress < path.length - 1;

    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final cell = board[r][c];
        final rect = _cellRect(r, c, boardY);

        final bgColor = switch (cell.kind) {
          CellKind.path     => 0xFF8b7355,
          CellKind.unlocked => 0xFF2a3a2a,
          CellKind.locked   => 0xFF1a1a2a,
        };
        canvas.drawRect(rect, Paint()..color = Color(bgColor));
        canvas.drawRect(rect,
          Paint()
            ..color = const Color(0x1AFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );

        if (cell.kind == CellKind.locked) {
          // 鎖定格顯示 + 號提示
          _drawChar(canvas, '+', rect,
              color: const Color(0x33FFFFFF), fontSize: _cellSize * 0.35);
        } else {
          _drawSpecialCellLabel(canvas, r, c, path, rect,
              jiangHp: jiangHp, jiangMaxHp: jiangMaxHp, hideJiang: isWalking);
          if (cell.unit != null) {
            // 武將字牌：計算激活狀態
            GeneralDef? activatedAs;
            bool isSecondary = false;
            if (cell.unit!.type == 'general_char') {
              activatedAs = _getActivatedGeneral(cell.unit!, r, c, board);
              if (activatedAs == null) {
                isSecondary = _isGeneralSecondary(cell.unit!, r, c, board);
              }
            }
            _drawUnit(canvas, cell.unit!, rect,
                activatedAs: activatedAs, isSecondaryOfPair: isSecondary);
          }
        }
      }
    }

    // 武將激活配對：繪製跨雙格的金色外框（顯示整體感）
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final unit = board[r][c].unit;
        if (unit == null) continue;
        final gDef = _getActivatedGeneral(unit, r, c, board);
        if (gDef == null) continue;
        Rect? secRect;
        if (c + 1 < kCols) {
          final ru = board[r][c + 1].unit;
          if (ru != null && _isGeneralSecondary(ru, r, c + 1, board)) {
            secRect = _cellRect(r, c + 1, boardY);
          }
        }
        if (secRect == null && r + 1 < kRows) {
          final ru = board[r + 1][c].unit;
          if (ru != null && _isGeneralSecondary(ru, r + 1, c, board)) {
            secRect = _cellRect(r + 1, c, boardY);
          }
        }
        if (secRect == null) continue;
        final spanRect = _cellRect(r, c, boardY).expandToInclude(secRect).deflate(2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(spanRect, const Radius.circular(4)),
          Paint()
            ..color = const Color(0xFFFFD700)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
      }
    }

    // prep 動畫：蔣沿路線平滑行走（getPathPos 插值）
    if (isWalking) {
      final pos = getPathPos(jiangProgress, path);
      final rect = _cellRectF(pos.row, pos.col, boardY);
      _drawHearts(canvas, rect, jiangHp, jiangMaxHp);
      _drawChar(canvas, '蔣', rect,
          color: const Color(0xFFFFD700), fontSize: _cellSize * 0.45,
          offsetY: _cellSize * 0.08);
    }

    // 危險警告：右側顯示「危」
    if (danger) {
      final oy = boardY + (kRows / 2 - 0.6) * _cellSize;
      final rect = Rect.fromLTWH(
        _boardOffsetX + (kCols - 1) * _cellSize,
        oy, _cellSize, _cellSize * 1.2,
      );
      _drawChar(canvas, '危', rect,
          color: const Color(0xCCFF1744), fontSize: _cellSize * 0.6);
    }
  }

  void _drawSpecialCellLabel(Canvas canvas, int r, int c,
      List<List<int>> path, Rect rect,
      {required int jiangHp, required int jiangMaxHp, bool hideJiang = false}) {
    final isYing  = path.first[0] == r && path.first[1] == c;
    final isJiang = path.last[0]  == r && path.last[1]  == c;
    if (isYing) {
      _drawChar(canvas, '☁营', rect,
          color: const Color(0x88FFFFFF), fontSize: _cellSize * 0.28);
    } else if (isJiang && !hideJiang) {
      _drawHearts(canvas, rect, jiangHp, jiangMaxHp);
      _drawChar(canvas, '蔣', rect,
          color: const Color(0xFFFFD700), fontSize: _cellSize * 0.45,
          offsetY: _cellSize * 0.08);
    }
  }

  void _drawUnit(Canvas canvas, Unit unit, Rect rect, {
    GeneralDef? activatedAs,    // 非null = 此格是激活配對的主字
    bool isSecondaryOfPair = false, // 此格是激活配對的次字
  }) {
    final inset = rect.deflate(_cellSize * 0.06);
    final isActivatedGeneral = activatedAs != null || isSecondaryOfPair;
    final isSoloChar = unit.type == 'general_char' && !isActivatedGeneral;

    // 卡牌底色（general_char 統一深棕，不隨激活狀態改變地板色）
    final bg = unit.type == 'general_char'
        ? const Color(0xFF3a2a00)
        : const Color(0xFFF0ECE0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(2)),
      Paint()..color = bg,
    );

    // 邊框：激活 = 金色粗框；solo = 暗灰；其他 = 普通
    final Color borderColor;
    final double borderWidth;
    if (isActivatedGeneral) {
      borderColor = const Color(0xFFFFD700);
      borderWidth = 2.5;
    } else if (isSoloChar) {
      borderColor = const Color(0xFF555544);
      borderWidth = 1.0;
    } else {
      borderColor = const Color(0xFFBBBBBB);
      borderWidth = 1.5;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(2)),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // 等級角標（右上，>1 才顯示，激活武將用金色）
    if (unit.level > 1) {
      final lv = _cellSize * 0.18;
      _drawChar(canvas, '${unit.level}',
        Rect.fromLTRB(inset.right - lv, inset.top, inset.right, inset.top + lv),
        color: isActivatedGeneral
            ? const Color(0xFFFFD700)
            : const Color(0xFF888888),
        fontSize: _cellSize * 0.15);
    }

    // 主字（solo 字牌稍微暗淡）
    final textColor = isActivatedGeneral
        ? const Color(0xFFFFD700)
        : isSoloChar
            ? const Color(0xAA998855)
            : const Color(0xFF111111);
    _drawChar(canvas, unit.displayChar, rect,
        color: textColor, fontSize: _cellSize * 0.4);

    // 打瞌睡 z：solo 字牌閃爍顯示，每 700ms 切換
    if (isSoloChar && (_sleepAnimMs ~/ 700) % 2 == 0) {
      final zRect = Rect.fromLTRB(
        inset.right - _cellSize * 0.28, inset.top,
        inset.right, inset.top + _cellSize * 0.28,
      );
      _drawChar(canvas, 'z', zRect,
          color: const Color(0x88AAAAFF), fontSize: _cellSize * 0.2);
    }
  }

  void _renderDivider(Canvas canvas) {
    final y = _aiBoardY + kRows * _cellSize;
    final rect = Rect.fromLTWH(_boardOffsetX, y, kCols * _cellSize, _dividerH);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF111111));
    _drawChar(canvas, '── 對決 ──', rect,
        color: const Color(0x88FFFFFF), fontSize: 11);
  }

  void _renderEnemies(Canvas canvas, List<_Enemy> enemies,
      {required bool isAiPath}) {
    final path   = isAiPath ? kAiPath : kPlayerPath;
    final boardY = isAiPath ? _aiBoardY : _playerBoardY;

    for (final e in enemies) {
      if (e.markedDead) continue;

      // 插值平滑位置
      final pos = getPathPos(e.pathProgress, path);
      final cx = _boardOffsetX + (pos.col + 0.5) * _cellSize;
      final cy = boardY + (pos.row + 0.5) * _cellSize;
      final sz = _cellSize * (e.isBoss ? 0.75 : 0.6);
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: sz, height: sz);

      // 敵軍卡牌底
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = e.isBoss
            ? const Color(0xFFFFCCCC)
            : const Color(0xFFEEEEEE));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = Color(e.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

      // 血量條（在卡牌上方）
      final hpRatio = (e.hp / e.maxHp).clamp(0.0, 1.0);
      final barTop = cy - sz / 2 - 5;
      canvas.drawRect(
        Rect.fromLTWH(cx - sz / 2, barTop, sz, 3),
        Paint()..color = const Color(0x44000000));
      canvas.drawRect(
        Rect.fromLTWH(cx - sz / 2, barTop, sz * hpRatio, 3),
        Paint()..color = const Color(0xCCFF3333));

      _drawChar(canvas, e.key, rect,
          color: Color(e.color),
          fontSize: _cellSize * (e.isBoss ? 0.5 : 0.38));
    }
  }

  void _renderProjectiles(Canvas canvas) {
    for (final p in _projectiles) {
      final x = p.sx + (p.ex - p.sx) * p.t;
      final y = p.sy + (p.ey - p.sy) * p.t;
      // 技能彈藥：★ 更大更金
      final sz   = p.isSkill ? _cellSize * 0.38 : _cellSize * 0.25;
      final fs   = p.isSkill ? _cellSize * 0.32 : _cellSize * 0.22;
      final color = p.isSkill
          ? const Color(0xFFFFD700)
          : const Color(0xFFFFE082);
      final rect = Rect.fromCenter(center: Offset(x, y), width: sz, height: sz);
      _drawChar(canvas, p.char, rect, color: color, fontSize: fs);
    }
  }

  // ── Canvas 工具 ──────────────────────────────────────

  Rect _cellRect(int row, int col, double boardY) => Rect.fromLTWH(
    _boardOffsetX + col * _cellSize,
    boardY + row * _cellSize,
    _cellSize, _cellSize,
  );

  Rect _cellRectF(double row, double col, double boardY) => Rect.fromLTWH(
    _boardOffsetX + col * _cellSize,
    boardY + row * _cellSize,
    _cellSize, _cellSize,
  );

  Offset _cellCenter(int row, int col, {required bool isAiBoard}) {
    final boardY = isAiBoard ? _aiBoardY : _playerBoardY;
    return _cellRect(row, col, boardY).center;
  }

  // 蔣 HP 心形（排列在格子頂部）
  void _drawHearts(Canvas canvas, Rect cellRect, int hp, int maxHp) {
    final sz  = min(_cellSize * 0.17, 11.0);
    const gap = 1.5;
    final totalW = maxHp * sz + (maxHp - 1) * gap;
    var x = cellRect.center.dx - totalW / 2;
    final y = cellRect.top + 2;
    for (int i = 0; i < maxHp; i++) {
      _drawChar(canvas, '♥',
        Rect.fromLTWH(x, y, sz, sz),
        color: i < hp
            ? const Color(0xFFE53935)
            : const Color(0x44FFFFFF),
        fontSize: sz * 0.9);
      x += sz + gap;
    }
  }

  void _drawChar(Canvas canvas, String text, Rect rect, {
    required Color color, required double fontSize, double offsetY = 0,
  }) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(
          color: color, fontSize: fontSize, fontWeight: FontWeight.bold))
      ..addText(text);
    final para = pb.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(para,
        Offset(rect.left, rect.top + (rect.height - para.height) / 2 + offsetY));
  }

  // ── 公開給 UI 的接口 ─────────────────────────────────

  double get cellSize      => _cellSize;
  double get boardOffsetX  => _boardOffsetX;
  double get aiBoardY      => _aiBoardY;
  double get playerBoardY  => _playerBoardY;

  ({int row, int col, bool isAi})? hitTest(Offset pos) {
    for (final isAi in [true, false]) {
      final boardY = isAi ? _aiBoardY : _playerBoardY;
      if (pos.dy < boardY || pos.dy >= boardY + kRows * _cellSize) continue;
      final col = ((pos.dx - _boardOffsetX) / _cellSize).floor();
      final row = ((pos.dy - boardY) / _cellSize).floor();
      if (col < 0 || col >= kCols || row < 0 || row >= kRows) continue;
      return (row: row, col: col, isAi: isAi);
    }
    return null;
  }
}
