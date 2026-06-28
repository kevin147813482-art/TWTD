// 頂部狀態欄：[⏸ 粮食] | [地圖/波次] | [擊N]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/providers.dart';
import '../../state/models.dart';

class TopBarOverlay extends ConsumerWidget {
  const TopBarOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameNotifierProvider);

    return Column(
      children: [
        Container(
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xCC111111),
            border: Border(bottom: BorderSide(color: Color(0x33FFFFFF))),
          ),
          child: Row(
            children: [
              // 左：暫停 + 粮食
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _PauseButton(phase: s.phase),
                    const SizedBox(width: 8),
                    _FoodBadge(food: s.playerFood),
                  ],
                ),
              ),
              // 中：準備階段顯示提示；作戰階段顯示地圖名+波次
              Expanded(
                child: s.phase == GamePhase.prep
                  ? const Text(
                      '護駕！先布防',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFFFD700), fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.mapName,
                          style: const TextStyle(
                            color: Color(0xFFFFD700), fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          s.bossWarning ? '⚠️ BOSS' : '第 ${s.wave} 波',
                          style: TextStyle(
                            color: s.bossWarning
                                ? const Color(0xFFFF4444)
                                : const Color(0xAAFFFFFF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
              ),
              // 右：得分 + 血量
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '擊 ${s.playerScore}',
                      style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    _HpDots(hp: s.playerJiangHp, maxHp: s.playerJiangMaxHp,
                            danger: s.playerDanger),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PauseButton extends ConsumerWidget {
  final GamePhase phase;
  const _PauseButton({required this.phase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaused = phase == GamePhase.paused;
    return GestureDetector(
      onTap: () => ref.read(gameNotifierProvider.notifier).togglePause(),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          isPaused ? Icons.play_arrow : Icons.pause,
          color: Colors.white, size: 20,
        ),
      ),
    );
  }
}

class _FoodBadge extends StatelessWidget {
  final int food;
  const _FoodBadge({required this.food});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x55FFD700),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '🍞 $food',
        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _HpDots extends StatelessWidget {
  final int hp, maxHp;
  final bool danger;
  const _HpDots({required this.hp, required this.maxHp, required this.danger});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxHp, (i) => Container(
        width: 8, height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < hp
              ? (danger ? const Color(0xFFFF4444) : const Color(0xFF66BB6A))
              : const Color(0x44FFFFFF),
        ),
      )),
    );
  }
}
