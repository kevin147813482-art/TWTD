// 手牌區 + 招募按鈕 + 鏟子按鈕（底部 overlay）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/providers.dart';
import '../../state/models.dart';
import '../../game/config.dart';

// 由 GameScreen 傳入，用於拖放交互
typedef OnCardDragStart = void Function(int handIndex, HandCard card);
typedef OnShovelTap = void Function();

class HandAreaOverlay extends ConsumerStatefulWidget {
  final OnCardDragStart? onDragStart;
  final OnShovelTap? onShovelTap;
  const HandAreaOverlay({super.key, this.onDragStart, this.onShovelTap});

  @override
  ConsumerState<HandAreaOverlay> createState() => _HandAreaOverlayState();
}

class _HandAreaOverlayState extends ConsumerState<HandAreaOverlay>
    with TickerProviderStateMixin {
  int _prevRecruitVersion = -1;
  bool _animating = false;
  bool _prevCanRecruit = false;
  late final AnimationController _ctrl;
  late final AnimationController _flashCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _animating = false);
      }
    });
    _flashCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gameNotifierProvider);

    // 手牌飛入動畫
    if (s.playerRecruitVersion != _prevRecruitVersion) {
      _prevRecruitVersion = s.playerRecruitVersion;
      if (_prevRecruitVersion > 0) {
        _animating = true;
        _ctrl.forward(from: 0);
      }
    }

    // 征兵按鈕閃爍：糧食夠時脈動提示
    final canRecruit = s.canPlayerRecruit;
    if (canRecruit != _prevCanRecruit) {
      _prevCanRecruit = canRecruit;
      if (canRecruit) {
        _flashCtrl.repeat(reverse: true);
      } else {
        _flashCtrl.stop();
        _flashCtrl.value = 0;
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 行動按鈕列
        _ActionRow(s: s, flashAnim: _flashCtrl),
        const SizedBox(height: 4),
        // 手牌列
        SizedBox(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(kHandSize, (i) {
              final card = s.playerHand[i];
              return _HandCardSlot(
                index: i,
                card: card,
                animating: _animating,
                animCtrl: _ctrl,
                onDragStart: widget.onDragStart,
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ActionRow extends ConsumerWidget {
  final GameUiState s;
  final Animation<double> flashAnim;
  const _ActionRow({required this.s, required this.flashAnim});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameNotifierProvider.notifier);
    final cost = s.playerRecruitCost;
    final canRecruit = s.canPlayerRecruit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 招募按鈕（可招募時邊框脈動 + 光暈）
          GestureDetector(
            onTap: canRecruit ? notifier.playerRecruit : null,
            child: AnimatedBuilder(
              animation: flashAnim,
              builder: (ctx, _) {
                final t = canRecruit ? flashAnim.value : 0.0;
                return Container(
                  decoration: canRecruit ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Color.lerp(Colors.transparent,
                            const Color(0xFF66FF66), t)!,
                        blurRadius: 8 + t * 6,
                        spreadRadius: t * 2,
                      ),
                    ],
                  ) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: canRecruit ? const Color(0xFF2e7d32) : const Color(0xFF424242),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: canRecruit
                            ? Color.lerp(const Color(0xFF66BB6A),
                                const Color(0xFF00FF77), t)!
                            : const Color(0xFF757575),
                        width: canRecruit ? 1.5 + t * 1.0 : 1.0,
                      ),
                    ),
                    child: Text(
                      '征兵 🍞$cost',
                      style: TextStyle(
                        color: canRecruit ? Colors.white : const Color(0xFFAAAAAA),
                        fontSize: 13, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 鏟子按鈕
          GestureDetector(
            onTap: notifier.addShovelToHand,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4e342e),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8D6E63)),
              ),
              child: const Text('⛏ 鏟子',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandCardSlot extends StatelessWidget {
  final int index;
  final HandCard? card;
  final bool animating;
  final AnimationController animCtrl;
  final OnCardDragStart? onDragStart;

  const _HandCardSlot({
    required this.index, required this.card, required this.animating,
    required this.animCtrl, this.onDragStart,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardWidget = _CardFace(card: card);

    if (card != null && animating) {
      final delay = (kHandSize - 1 - index) * 0.12;
      final anim = CurvedAnimation(
        parent: animCtrl,
        curve: Interval(delay.clamp(0.0, 0.8), 1.0, curve: Curves.easeOutCubic),
      );
      cardWidget = AnimatedBuilder(
        animation: anim,
        child: cardWidget,
        builder: (ctx, child) => Transform.translate(
          offset: Offset((1 - anim.value) * 120, 0),
          child: Opacity(opacity: anim.value, child: child),
        ),
      );
    }

    if (card != null && onDragStart != null) {
      cardWidget = Draggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.75, child: _CardFace(card: card)),
        ),
        childWhenDragging: _CardFace(card: card, dimmed: true),
        onDragStarted: () => onDragStart!(index, card!),
        child: cardWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: cardWidget,
    );
  }
}

class _CardFace extends StatelessWidget {
  final HandCard? card;
  final bool dimmed;
  const _CardFace({this.card, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final isEmpty = card == null;

    return Opacity(
      opacity: dimmed ? 0.3 : 1.0,
      child: Container(
        width: 58, height: 80,
        decoration: BoxDecoration(
          color: isEmpty ? const Color(0x22FFFFFF) : _cardBg(card!),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEmpty ? const Color(0x22FFFFFF) : _cardBorder(card!),
            width: 1.5,
          ),
        ),
        child: isEmpty
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 等級
                  if (card!.level > 1)
                    Text('★' * card!.level,
                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 8)),
                  // 主字
                  Text(
                    card!.type == 'shovel' ? '⛏' : card!.key,
                    style: TextStyle(
                      color: _cardTextColor(card!),
                      fontSize: card!.type == 'shovel' ? 24 : 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // 種類標籤
                  Text(
                    _cardLabel(card!),
                    style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
                  ),
                ],
              ),
      ),
    );
  }

  Color _cardBg(HandCard c) {
    if (c.type == 'shovel')       return const Color(0xFF3e2723);
    if (c.type == 'general' ||
        c.type == 'general_char') return const Color(0xFF3a2a00);
    return const Color(0xFF1a3a1a);
  }

  Color _cardBorder(HandCard c) {
    if (c.type == 'shovel')       return const Color(0xFF8D6E63);
    if (c.type == 'general' ||
        c.type == 'general_char') return const Color(0xFFFFD700);
    return const Color(0xFF4CAF50);
  }

  Color _cardTextColor(HandCard c) {
    if (c.type == 'general' || c.type == 'general_char') return const Color(0xFFFFD700);
    return Colors.white;
  }

  String _cardLabel(HandCard c) {
    if (c.type == 'shovel')       return '鏟子';
    if (c.type == 'general')      return '武將';
    if (c.type == 'general_char') return '文字';
    return c.key == '步' ? '步兵'
         : c.key == '炮' ? '炮兵'
         : c.key == '槍' ? '機槍'
         : c.key == '坦' ? '坦克' : '';
  }
}
