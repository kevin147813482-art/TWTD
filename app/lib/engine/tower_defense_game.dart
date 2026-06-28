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
    'slash': '✦', 'bullet': '·', 'shell': '●', 'arrow': '→',
  };
  String get char => _chars[kind] ?? '·';
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

  // 波次計時
  double _waveTimerMs   = 0;
  int _spawnedThisWave  = 0;
  bool _wavePending     = false;

  // AI 計時
  double _aiTimerMs = 0;
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
  }

  // 準備階段：蔣從营走到蔣位置
  void _updatePrep(double dt) {
    if (_prepDone) return;
    const speed = 2.5;
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
    const speedScale = 0.0008;
    for (final e in _playerEnemies) {
      if (e.markedDead) continue;
      e.pathProgress += e.speed * dtMs * speedScale;
      if (e.pathProgress >= kPlayerPath.length - 1) {
        e.markedDead = true;
        _postFrame(() => notifier.onPlayerJiangHit());
      }
    }
    for (final e in _aiEnemies) {
      if (e.markedDead) continue;
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
            _spawnProjectile(side, 'bullet', r, c,
                targets[0].pathProgress, path);
            break;
          case 'pierce':
            for (final t in targets) _dealDamage(t, unit.atk, onKill);
            if (targets.isNotEmpty) {
              _spawnProjectile(side, 'arrow', r, c,
                  targets[0].pathProgress, path);
            }
            break;
          case 'area':
            for (final t in targets) _dealDamage(t, unit.atk, onKill);
            if (targets.isNotEmpty) {
              _spawnProjectile(side, 'shell', r, c,
                  targets[0].pathProgress, path);
            }
            break;
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
    final delay = _spawnedThisWave == 0 ? 0 : 600;
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

  String _randomEnemy() {
    final entries = kEnemyTypes.entries.toList();
    final total = entries.fold(0, (sum, e) => sum + e.value.weight);
    int r = _rng.nextInt(total);
    for (final e in entries) {
      r -= e.value.weight;
      if (r < 0) return e.key;
    }
    return entries.last.key;
  }

  // ── AI 行為 ──────────────────────────────────────────

  void _aiTick(double dtMs) {
    _aiTimerMs += dtMs;
    final interval = 800 + _rng.nextDouble() * 1200;
    if (_aiTimerMs < interval) return;
    _aiTimerMs = 0;

    final s = notifier.state;
    final cost = getRecruitCost(s.aiRecruitTimes);
    if (s.aiFood >= cost) {
      _postFrame(() {
        notifier.aiRecruit();
        _aiDeploy();
      });
    }
  }

  void _aiDeploy() {
    final s = notifier.state;
    final vacant = <List<int>>[];
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final cell = s.aiBoard[r][c];
        if (cell.kind == CellKind.unlocked && cell.unit == null) {
          vacant.add([r, c]);
        }
      }
    }
    if (vacant.isEmpty) return;
    final pos  = vacant[_rng.nextInt(vacant.length)];
    final keys = kBasicUnits.keys.toList();
    notifier.aiDeployUnit(keys[_rng.nextInt(keys.length)], pos[0], pos[1]);
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
          if (cell.unit != null) _drawUnit(canvas, cell.unit!, rect);
        }
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

  void _drawUnit(Canvas canvas, Unit unit, Rect rect) {
    final inset = rect.deflate(_cellSize * 0.06);

    // 卡牌底色
    final bg = (unit.type == 'general' || unit.type == 'general_char')
        ? const Color(0xFF3a2a00)
        : const Color(0xFFF0ECE0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(2)),
      Paint()..color = bg,
    );

    // 卡牌邊框（攻擊時橘色）
    final borderColor = unit.attacking
        ? const Color(0xFFFF5722)
        : (unit.type == 'general' || unit.type == 'general_char')
            ? const Color(0xFFFFD700)
            : const Color(0xFFBBBBBB);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(2)),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 等級角標（右上，>1 才顯示）
    if (unit.level > 1) {
      final lv = _cellSize * 0.18;
      _drawChar(canvas, '${unit.level}',
        Rect.fromLTRB(inset.right - lv, inset.top, inset.right, inset.top + lv),
        color: const Color(0xFF888888), fontSize: _cellSize * 0.15);
    }

    // 主字
    final textColor = (unit.type == 'general' || unit.type == 'general_char')
        ? const Color(0xFFFFD700) : const Color(0xFF111111);
    _drawChar(canvas, unit.displayChar, rect,
        color: textColor, fontSize: _cellSize * 0.4);
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
        Paint()..color = Color.fromARGB(200,
            (255 * (1 - hpRatio)).toInt(), (200 * hpRatio).toInt(), 50));

      _drawChar(canvas, e.key, rect,
          color: Color(e.color),
          fontSize: _cellSize * (e.isBoss ? 0.5 : 0.38));
    }
  }

  void _renderProjectiles(Canvas canvas) {
    for (final p in _projectiles) {
      final x = p.sx + (p.ex - p.sx) * p.t;
      final y = p.sy + (p.ey - p.sy) * p.t;
      final rect = Rect.fromCenter(
          center: Offset(x, y),
          width: _cellSize * 0.25, height: _cellSize * 0.25);
      _drawChar(canvas, p.char, rect,
          color: const Color(0xFFFFE082), fontSize: _cellSize * 0.22);
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
