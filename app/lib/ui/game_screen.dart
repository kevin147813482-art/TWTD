// 遊戲主畫面：flame canvas + Flutter overlay（topBar / handArea）
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../state/models.dart';
import '../game/config.dart';
import '../engine/tower_defense_game.dart';
import 'widgets/top_bar.dart';
import 'widgets/hand_cards.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final TowerDefenseGame _game;

  // 拖放狀態（手牌→棋盤）
  int? _draggingHandIndex;
  HandCard? _draggingCard;
  Offset? _dragPos;
  ({int row, int col})? _hoverCell;

  // 棋盤 tap-select：選中的格子
  ({int row, int col})? _selectedBoardCell;

  // 單位詳情彈窗
  Unit? _infoUnit;

  @override
  void initState() {
    super.initState();
    _game = TowerDefenseGame(
      notifier: ref.read(gameNotifierProvider.notifier),
    );
  }

  @override
  void dispose() {
    _game.onRemove();
    super.dispose();
  }

  void _handleCardDragStart(int handIndex, HandCard card) {
    setState(() {
      _draggingHandIndex = handIndex;
      _draggingCard = card;
      _infoUnit = null;
    });
  }

  // 估算手牌中第 index 張卡的螢幕中心位置
  Offset _estimateCardPos(int index, Size screenSize) {
    // 5張卡置中排列，每張佔 64px（58px寬 + 左右各3px padding）
    final x = screenSize.width / 2 - 128 + index * 64;
    // 底部手牌區 ~200px，行動列~50px，間距4px，牌高100px，底部padding8px
    // 牌中心 y ≈ screenHeight - 8 - 50 = screenHeight - 58
    final y = screenSize.height - 58;
    return Offset(x, y);
  }

  void _clearDrag() {
    setState(() {
      _draggingHandIndex = null;
      _draggingCard = null;
      _dragPos = null;
      _hoverCell = null;
    });
  }

  void _clearBoardSelection() {
    setState(() => _selectedBoardCell = null);
  }

  // 根據螢幕座標找手牌槽索引（找不到返回 null）
  int? _findHandSlot(Offset pos, Size sz) {
    // 5張卡置中，每張 64px（58px + 各3px padding × 2）
    final startX = sz.width / 2 - 128.0;
    for (int i = 0; i < kHandSize; i++) {
      final cx = startX + i * 64;
      if (pos.dx >= cx - 32 && pos.dx < cx + 32) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gameNotifierProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Flame 遊戲畫布（含手牌拖放目標） ──
          DragTarget<int>(
            onWillAcceptWithDetails: (_) => true,
            onMove: (details) {
              final hit = _game.hitTest(details.offset);
              setState(() {
                _dragPos = details.offset;
                _hoverCell = (hit != null && !hit.isAi)
                    ? (row: hit.row, col: hit.col) : null;
              });
            },
            onLeave: (_) {
              setState(() {
                _dragPos = null;
                _hoverCell = null;
              });
            },
            onAcceptWithDetails: (details) {
              final sz = MediaQuery.of(context).size;
              // 落點在手牌區（螢幕底部 180px）→ 嘗試手牌合成
              if (details.offset.dy > sz.height - 180) {
                final toIndex = _findHandSlot(details.offset, sz);
                if (toIndex != null && toIndex != details.data) {
                  ref.read(gameNotifierProvider.notifier)
                      .mergeHandCards(details.data, toIndex);
                }
                _clearDrag();
                return;
              }
              final hit = _game.hitTest(details.offset);
              if (hit == null || hit.isAi) { _clearDrag(); return; }
              ref.read(gameNotifierProvider.notifier)
                  .deployUnit(details.data, hit.row, hit.col);
              _clearDrag();
            },
            builder: (ctx, candidateData, rejectedData) => GestureDetector(
              onTapUp: (d) => _handleTap(d.localPosition),
              child: GameWidget(
                game: _game,
                overlayBuilderMap: {
                  'topBar':   (_, __) => const TopBarOverlay(),
                  'handArea': (_, __) => HandAreaOverlay(
                    onDragStart: _handleCardDragStart,
                    onShovelTap:
                        ref.read(gameNotifierProvider.notifier).addShovelToHand,
                  ),
                },
                initialActiveOverlays: const ['topBar', 'handArea'],
              ),
            ),
          ),

          // ── 拖放視覺疊加：虛線 + 攻擊範圍圓圈 + 鏟子高亮 ──
          // 拖放虛線 + 選中高亮 overlay（始終渲染，各自按需顯示）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DragOverlayPainter(
                  game: _game,
                  cardSourcePos: _draggingHandIndex != null
                      ? _estimateCardPos(_draggingHandIndex!,
                          MediaQuery.of(context).size)
                      : null,
                  hoverCell: _hoverCell,
                  card: _draggingCard,
                  board: s.playerBoard,
                  selectedCell: _selectedBoardCell,
                ),
              ),
            ),
          ),

          // ── 單位詳情彈窗 ──
          if (_infoUnit != null)
            _UnitInfoPopup(
              unit: _infoUnit!,
              onClose: () => setState(() => _infoUnit = null),
            ),

          // ── 勝負畫面 ──
          if (s.phase == GamePhase.victory || s.phase == GamePhase.defeat)
            _ResultOverlay(phase: s.phase, score: s.playerScore),
        ],
      ),
    );
  }

  void _handleTap(Offset pos) {
    // 清除詳情彈窗
    if (_infoUnit != null) {
      setState(() => _infoUnit = null);
      return;
    }
    // 若手持拖拽中，嘗試部署
    if (_draggingHandIndex != null) {
      final hit = _game.hitTest(pos);
      if (hit != null && !hit.isAi) {
        ref.read(gameNotifierProvider.notifier)
            .deployUnit(_draggingHandIndex!, hit.row, hit.col);
      }
      _clearDrag();
      return;
    }

    final hit = _game.hitTest(pos);

    // 已有選中格子：第二次點擊決定目標
    if (_selectedBoardCell != null) {
      final sel = _selectedBoardCell!;
      if (hit != null && !hit.isAi) {
        if (hit.row == sel.row && hit.col == sel.col) {
          // 點擊同格 → 取消選中，顯示詳情
          final s = ref.read(gameNotifierProvider);
          final cell = s.playerBoard[sel.row][sel.col];
          setState(() {
            _selectedBoardCell = null;
            _infoUnit = cell.unit;
          });
        } else {
          // 點擊其他格 → 移動/交換
          ref.read(gameNotifierProvider.notifier)
              .moveOrMergeUnit(sel.row, sel.col, hit.row, hit.col);
          _clearBoardSelection();
        }
      } else {
        _clearBoardSelection();
      }
      return;
    }

    // 點擊有單位的格子 → 選中（顯示青色外框）
    if (hit != null && !hit.isAi) {
      final s = ref.read(gameNotifierProvider);
      final cell = s.playerBoard[hit.row][hit.col];
      if (cell.unit != null && cell.kind == CellKind.unlocked) {
        setState(() => _selectedBoardCell = (row: hit.row, col: hit.col));
      }
    }
  }
}

// ── 拖放虛線 + 範圍圓圈 CustomPainter ───────────────────
class _DragOverlayPainter extends CustomPainter {
  final TowerDefenseGame game;
  final Offset? cardSourcePos;
  final ({int row, int col})? hoverCell;
  final ({int row, int col})? selectedCell;
  final HandCard? card;
  final List<List<Cell>> board;

  _DragOverlayPainter({
    required this.game,
    required this.cardSourcePos,
    required this.hoverCell,
    required this.card,
    required this.board,
    this.selectedCell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = game.cellSize;
    final bx = game.boardOffsetX;
    final by = game.playerBoardY;

    // 棋盤選中格：青色外框 + 淡藍填充
    if (selectedCell != null) {
      final sr = Rect.fromLTWH(
          bx + selectedCell!.col * cs, by + selectedCell!.row * cs, cs, cs);
      canvas.drawRect(sr,
          Paint()..color = const Color(0x3300E5FF));
      canvas.drawRect(sr,
          Paint()
            ..color = const Color(0xCC00E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }

    // 鏟子拖動：鎖定格橘色高亮
    if (card?.type == 'shovel') {
      final shovelPaint = Paint()
        ..color = const Color(0x55FF9800)
        ..style = PaintingStyle.fill;
      final shovelBorder = Paint()
        ..color = const Color(0xAAFF9800)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (int r = 0; r < kRows; r++) {
        for (int c = 0; c < kCols; c++) {
          if (board[r][c].kind != CellKind.locked) continue;
          final rect = Rect.fromLTWH(bx + c * cs, by + r * cs, cs, cs);
          canvas.drawRect(rect, shovelPaint);
          canvas.drawRect(rect, shovelBorder);
        }
      }
    }

    if (hoverCell == null) return;

    final cx = bx + (hoverCell!.col + 0.5) * cs;
    final cy = by + (hoverCell!.row + 0.5) * cs;
    final cellCenter = Offset(cx, cy);

    // 懸停格黃色邊框
    final hoverRect = Rect.fromLTWH(
      bx + hoverCell!.col * cs, by + hoverCell!.row * cs, cs, cs);
    canvas.drawRect(hoverRect, Paint()
      ..color = const Color(0xBFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // 攻擊範圍圓圈
    final range = _cardRange();
    if (range > 0.0) {
      final radius = (range + 0.5) * cs;
      canvas.drawCircle(cellCenter, radius,
        Paint()
          ..color = const Color(0x1EFFFFFF)
          ..style = PaintingStyle.fill);
      canvas.drawCircle(cellCenter, radius,
        Paint()
          ..color = const Color(0x7FFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    }

    // 虛線（從手牌原始位置到懸停格中心）
    if (cardSourcePos != null) {
      _drawDashedLine(canvas, cardSourcePos!, cellCenter,
        Paint()
          ..color = const Color(0xBFFFD700)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        6, 4);
    }
  }

  double _cardRange() {
    if (card == null) return 1.0;
    if (card!.type == 'shovel') return 0.0;
    if (kBasicUnits.containsKey(card!.key)) return kBasicUnits[card!.key]!.range;
    if (kGenerals.containsKey(card!.key))   return kGenerals[card!.key]!.range;
    return 1.0;
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end,
      Paint paint, double dashLen, double gapLen) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var d = 0.0;
    var dash = true;
    while (d < dist) {
      final seg = min(dash ? dashLen : gapLen, dist - d);
      if (dash) {
        canvas.drawLine(
          Offset(start.dx + ux * d,       start.dy + uy * d),
          Offset(start.dx + ux * (d + seg), start.dy + uy * (d + seg)),
          paint,
        );
      }
      d += seg;
      dash = !dash;
    }
  }

  @override
  bool shouldRepaint(_DragOverlayPainter old) =>
      cardSourcePos != old.cardSourcePos || hoverCell != old.hoverCell ||
      card != old.card || selectedCell != old.selectedCell;
}

// ── 單位詳情彈窗 ──────────────────────────────────────
class _UnitInfoPopup extends StatelessWidget {
  final Unit unit;
  final VoidCallback onClose;
  const _UnitInfoPopup({required this.unit, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final name = kBasicUnits[unit.key]?.name ??
                 kGenerals[unit.key]?.fullName ?? unit.key;
    final atk  = unit.atk;
    final spd  = unit.atkSpeed;
    final rng  = unit.range;
    final type = switch (unit.attackType) {
      'pierce' => '穿刺',
      'area'   => '範圍',
      _        => '單體',
    };

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xEE1a1a1a),
              border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                  style: TextStyle(
                    color: (unit.type == 'general' || unit.type == 'general_char')
                        ? const Color(0xFFFFD700) : Colors.white,
                    fontSize: 18, fontWeight: FontWeight.bold,
                  )),
                const SizedBox(height: 4),
                if (unit.level > 1)
                  Text('Lv.${unit.level}',
                    style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 13)),
                const Divider(color: Color(0x44FFD700)),
                _Row('攻擊力', '${atk.toStringAsFixed(1)} (${type})'),
                _Row('攻速',   '${spd.toStringAsFixed(2)}/s'),
                _Row('射程', '${rng % 1 == 0 ? rng.toInt() : rng} 格'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onClose,
                  child: const Text('關閉',
                    style: TextStyle(color: Color(0xAAFFFFFF))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 13)),
        Text(value,  style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

// ── 勝負畫面 ────────────────────────────────────────────
class _ResultOverlay extends ConsumerWidget {
  final GamePhase phase;
  final int score;
  const _ResultOverlay({required this.phase, required this.score});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVictory = phase == GamePhase.victory;
    return GestureDetector(
      onTap: () {
        ref.read(gameNotifierProvider.notifier).startGame();
        Navigator.of(context).pop();
      },
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isVictory ? '🎉 勝利！' : '💀 失敗',
                style: TextStyle(
                  color: isVictory ? const Color(0xFFFFD700) : const Color(0xFFFF4444),
                  fontSize: 48, fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '共擊殺 $score 名敵軍',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 32),
              const Text(
                '點擊返回首頁',
                style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
