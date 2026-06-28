// 遊戲主畫面：flame canvas + Flutter overlay（topBar / handArea）
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../state/models.dart';
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

  // 拖放狀態
  int? _draggingHandIndex;

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
    setState(() => _draggingHandIndex = handIndex);
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
            onAcceptWithDetails: (details) {
              // details.offset 是相對於 DragTarget RenderBox 的局部座標
              final hit = _game.hitTest(details.offset);
              if (hit == null || hit.isAi) return;
              ref.read(gameNotifierProvider.notifier)
                  .deployUnit(details.data, hit.row, hit.col);
              setState(() => _draggingHandIndex = null);
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

          // ── 勝負畫面 ──
          if (s.phase == GamePhase.victory || s.phase == GamePhase.defeat)
            _ResultOverlay(phase: s.phase, score: s.playerScore),
        ],
      ),
    );
  }

  void _handleTap(Offset pos) {
    if (_draggingHandIndex == null) return;
    final hit = _game.hitTest(pos);
    if (hit == null || hit.isAi) return;
    ref.read(gameNotifierProvider.notifier).deployUnit(
      _draggingHandIndex!, hit.row, hit.col,
    );
    setState(() => _draggingHandIndex = null);
  }
}

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
