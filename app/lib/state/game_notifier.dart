// GameNotifier — UI 狀態管理（Riverpod StateNotifier）
// 引擎（tower_defense_game.dart）負責遊戲邏輯，此處只管 UI 相關狀態
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import '../game/config.dart';

final _rng = Random();
int _idCounter = 0;
String _uid(String prefix) => '${prefix}_${++_idCounter}';

class GameNotifier extends StateNotifier<GameUiState> {
  GameNotifier() : super(GameUiState(
    playerHand: List.filled(kHandSize, null),
    playerBoard: createBoard(false),
    aiBoard: createBoard(true),
  ));

  // ── 遊戲流程 ──────────────────────────────────────────

  void startGame() {
    state = GameUiState(
      phase: GamePhase.prep,
      playerHand: List.filled(kHandSize, null),
      playerBoard: createBoard(false),
      aiBoard: createBoard(true),
      playerFood: kInitialFood,
      aiFood: kInitialFood,
    );
  }

  void setPhase(GamePhase phase) {
    state = state.copyWith(phase: phase);
  }

  void togglePause() {
    if (state.phase == GamePhase.playing) {
      state = state.copyWith(phase: GamePhase.paused);
    } else if (state.phase == GamePhase.paused) {
      state = state.copyWith(phase: GamePhase.playing);
    }
  }

  void nextWave() {
    state = state.copyWith(wave: state.wave + 1, bossWarning: false);
  }

  void setBossWarning(bool v) {
    state = state.copyWith(bossWarning: v);
  }

  // ── 玩家操作 ──────────────────────────────────────────

  // 波次遞增（對齊原版範圍）
  // 武將字：15%（波1）→ 20%（波6+），每波+1%
  // 鏟子：8%（固定）
  // 基礎兵：剩餘（約77%→72%）
  HandCard _randomHandCard(int wave) {
    final generalChance = min(0.15 + wave * 0.01, 0.20);
    const shovelChance = 0.08;
    final r = _rng.nextDouble();
    if (r < generalChance) {
      final gKeys = kGenerals.keys.toList();
      final gKey = gKeys[_rng.nextInt(gKeys.length)];
      final g = kGenerals[gKey]!;
      final char = g.chars[_rng.nextInt(g.chars.length)];
      return HandCard(type: 'general_char', key: char, generalKey: gKey, charStr: char);
    } else if (r < generalChance + shovelChance) {
      return const HandCard(type: 'shovel', key: '鏟');
    } else {
      final keys = kBasicUnits.keys.toList();
      return HandCard(type: 'unit', key: keys[_rng.nextInt(keys.length)]);
    }
  }

  void playerRecruit() {
    final cost = state.playerRecruitCost;
    if (state.playerFood < cost) return;

    final wave = state.wave;
    final newHand = List<HandCard?>.from(state.playerHand);
    for (int i = 0; i < kHandSize; i++) {
      newHand[i] = _randomHandCard(wave);
    }

    state = state.copyWith(
      playerFood: state.playerFood - cost,
      playerRecruitTimes: state.playerRecruitTimes + 1,
      playerRecruitVersion: state.playerRecruitVersion + 1,
      playerHand: newHand,
    );
  }

  // 手牌兩槽合成：同種同等級基礎兵 → 升一級（武將字不合成）
  void mergeHandCards(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    final hand = state.playerHand;
    final from = hand[fromIndex];
    final to   = hand[toIndex];
    if (from == null || to == null) return;
    if (from.type == 'general_char' || to.type == 'general_char') return;
    if (from.type != to.type || from.key != to.key || from.level != to.level) return;
    final maxLv = kBasicUnits[from.key]?.maxLevel ?? 5;
    if (from.level >= maxLv) return;
    final newHand = List<HandCard?>.from(hand);
    newHand[toIndex]   = from.copyWith(level: from.level + 1);
    newHand[fromIndex] = null;
    state = state.copyWith(playerHand: newHand);
  }

  void addShovelToHand() {
    final newHand = List<HandCard?>.from(state.playerHand);
    final slot = newHand.indexWhere((c) => c == null);
    if (slot == -1) return;
    newHand[slot] = const HandCard(type: 'shovel', key: '鏟');
    state = state.copyWith(playerHand: newHand);
  }

  // P0-1 武將升級回調（引擎設置，擊殺達閾值時升級場上兩張字牌）
  void Function(String generalKey, int newLevel)? onGeneralLevelUp;

  // 由引擎呼叫：將場上該武將的兩張字牌同時升一級
  void generalLevelUp(String generalKey, int newLevel) {
    if (newLevel > 5) return;
    final newBoard = _copyBoard(state.playerBoard);
    bool changed = false;
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final unit = newBoard[r][c].unit;
        if (unit?.type == 'general_char' && unit?.generalKey == generalKey) {
          newBoard[r][c] = newBoard[r][c].copyWith(
            unit: unit!.copyWith(level: newLevel),
          );
          changed = true;
        }
      }
    }
    if (changed) state = state.copyWith(playerBoard: newBoard);
  }

  void deployUnit(int handIndex, int row, int col) {
    final card = state.playerHand[handIndex];
    if (card == null) return;
    if (card.type == 'shovel') {
      _openCell(handIndex, row, col);
      return;
    }

    final board = state.playerBoard;
    final cell = board[row][col];
    if (cell.kind != CellKind.unlocked) return;

    // 有單位：武將字牌不合并（不同字拼合，不升級）；基礎兵同種同級升級合並，否則替換
    if (cell.unit != null) {
      final existing = cell.unit!;
      final newBoard = _copyBoard(board);
      final newHand = List<HandCard?>.from(state.playerHand);
      if (card.type != 'general_char' &&
          existing.key == card.key && existing.type == card.type &&
          existing.level == card.level && existing.level < existing.maxLevel) {
        // 同兵種同等級 → 升級合並
        newBoard[row][col] = cell.copyWith(
          unit: existing.copyWith(level: existing.level + 1),
        );
        newHand[handIndex] = null;
        state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
        return;
      }
      // 不同兵種/等級/武將字 → 替換：原單位退回手牌，新卡放入
      newHand[handIndex] = existing.toHandCard();
      newBoard[row][col] = cell.copyWith(
        unit: Unit(
          id: _uid('pu'), type: card.type, key: card.key,
          level: card.level, row: row, col: col,
          generalKey: card.generalKey, charStr: card.charStr,
        ),
      );
      state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
      return;
    }

    final unit = Unit(
      id: _uid('pu'), type: card.type, key: card.key,
      level: card.level, row: row, col: col,
      generalKey: card.generalKey, charStr: card.charStr,
    );
    final newBoard = _copyBoard(board);
    newBoard[row][col] = cell.copyWith(unit: unit);
    final newHand = List<HandCard?>.from(state.playerHand);
    newHand[handIndex] = null;
    state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
  }

  void _openCell(int handIndex, int row, int col) {
    final board = state.playerBoard;
    final cell = board[row][col];
    if (cell.kind != CellKind.locked) return;

    final newBoard = _copyBoard(board);
    newBoard[row][col] = cell.copyWith(kind: CellKind.unlocked);
    final newHand = List<HandCard?>.from(state.playerHand);
    newHand[handIndex] = null;
    state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
  }

  void moveOrMergeUnit(int fromRow, int fromCol, int toRow, int toCol) {
    final board = state.playerBoard;
    final fromCell = board[fromRow][fromCol];
    final toCell = board[toRow][toCol];
    if (fromCell.unit == null) return;
    if (toCell.kind != CellKind.unlocked) return;

    final movingUnit = fromCell.unit!;
    final newBoard = _copyBoard(board);

    if (toCell.unit != null) {
      final target = toCell.unit!;
      if (movingUnit.type != 'general_char' &&
          target.key == movingUnit.key && target.type == movingUnit.type &&
          target.level == movingUnit.level && target.level < target.maxLevel) {
        // 同兵種同等級 → 合并升級
        newBoard[toRow][toCol] = toCell.copyWith(
          unit: target.copyWith(level: target.level + 1),
        );
        newBoard[fromRow][fromCol] = fromCell.copyWith(clearUnit: true);
        state = state.copyWith(playerBoard: newBoard);
        return;
      }
      // 不同兵種/等級 → 交換位置
      newBoard[toRow][toCol] = toCell.copyWith(
        unit: movingUnit.copyWith(row: toRow, col: toCol),
      );
      newBoard[fromRow][fromCol] = fromCell.copyWith(
        unit: target.copyWith(row: fromRow, col: fromCol),
      );
      state = state.copyWith(playerBoard: newBoard);
      return;
    }

    // 移動
    newBoard[toRow][toCol] = toCell.copyWith(
      unit: movingUnit.copyWith(row: toRow, col: toCol),
    );
    newBoard[fromRow][fromCol] = fromCell.copyWith(clearUnit: true);
    state = state.copyWith(playerBoard: newBoard);
  }

  // 棋盤單位拖回手牌：空格→返回；同種同級→合并；其他→交換
  void returnUnitToHand(int row, int col, int slotIndex) {
    final board = state.playerBoard;
    final cell = board[row][col];
    if (cell.unit == null) return;

    final movingUnit = cell.unit!;
    final existingCard = state.playerHand[slotIndex];
    final newBoard = _copyBoard(board);
    final newHand = List<HandCard?>.from(state.playerHand);

    if (existingCard == null) {
      // 空格：直接放回
      newHand[slotIndex] = movingUnit.toHandCard();
      newBoard[row][col] = cell.copyWith(clearUnit: true);
    } else if (movingUnit.type != 'general_char' &&
               existingCard.type != 'general_char' &&
               existingCard.type != 'shovel' &&
               existingCard.key == movingUnit.key &&
               existingCard.type == movingUnit.type &&
               existingCard.level == movingUnit.level &&
               existingCard.level < (kBasicUnits[existingCard.key]?.maxLevel ?? 5)) {
      // 同種同級：合并升一級
      newHand[slotIndex] = existingCard.copyWith(level: existingCard.level + 1);
      newBoard[row][col] = cell.copyWith(clearUnit: true);
    } else {
      // 其他：交換（手牌→棋盤，棋盤→手牌）
      newHand[slotIndex] = movingUnit.toHandCard();
      newBoard[row][col] = cell.copyWith(
        unit: Unit(
          id: _uid('pu'), type: existingCard.type, key: existingCard.key,
          level: existingCard.level, row: row, col: col,
          generalKey: existingCard.generalKey, charStr: existingCard.charStr,
        ),
      );
    }

    state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
  }

  // ── 引擎回調（戰鬥事件） ──────────────────────────────

  void onPlayerEnemyKilled() {
    state = state.copyWith(
      playerFood: state.playerFood + kFoodPerKill,
      playerScore: state.playerScore + 1,
    );
  }

  void onPlayerJiangHit() {
    final newHp = state.playerJiangHp - 1;
    // 蔣受擊 +10 糧食（對齊 Vue FOOD_ON_HIT）
    final newFood = (state.playerFood + kFoodOnHit).clamp(0, 99);
    if (newHp <= 0) {
      state = state.copyWith(playerJiangHp: 0, playerFood: newFood, phase: GamePhase.defeat);
    } else {
      state = state.copyWith(
        playerJiangHp: newHp,
        playerFood: newFood,
        playerDanger: newHp == 1,
      );
    }
  }

  void onAiEnemyKilled() {
    state = state.copyWith(aiFood: state.aiFood + kFoodPerKill);
  }

  void onAiJiangHit() {
    final newHp = state.aiJiangHp - 1;
    final newAiFood = (state.aiFood + kFoodOnHit).clamp(0, 99);
    if (newHp <= 0) {
      state = state.copyWith(aiJiangHp: 0, aiFood: newAiFood, phase: GamePhase.victory);
    } else {
      state = state.copyWith(
        aiJiangHp: newHp,
        aiFood: newAiFood,
        aiDanger: newHp == 1,
      );
    }
  }

  // ── AI 操作（由引擎調用） ────────────────────────────

  void aiDeployUnit(String key, int row, int col, {
    int level = 1, String type = 'unit',
    String? generalKey, String? charStr,
  }) {
    final board = state.aiBoard;
    final cell = board[row][col];
    if (cell.kind != CellKind.unlocked || cell.unit != null) return;

    final unit = Unit(
      id: _uid('au'), type: type, key: key,
      level: level, row: row, col: col,
      generalKey: generalKey, charStr: charStr,
    );
    final newBoard = _copyBoard(board);
    newBoard[row][col] = cell.copyWith(unit: unit);
    state = state.copyWith(aiBoard: newBoard);
  }

  // AI 用鏟子解鎖格：優先解鎖鄰近已解鎖格且靠近路線的鎖定格
  void aiUnlockCell() {
    final board = state.aiBoard;
    const deltas = [[-1,0],[1,0],[0,-1],[0,1]];
    final candidates = <List<int>>[];
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        if (board[r][c].kind != CellKind.locked) continue;
        for (final d in deltas) {
          final nr = r + d[0]; final nc = c + d[1];
          if (nr < 0 || nr >= kRows || nc < 0 || nc >= kCols) continue;
          if (board[nr][nc].kind == CellKind.unlocked) {
            candidates.add([r, c]);
            break;
          }
        }
      }
    }
    if (candidates.isEmpty) return;
    // 優先靠近 AI 路線的格（col=kCols-2 或 row=kRows-2）
    final near = candidates.where((p) =>
        p[1] == kCols - 2 || p[0] == kRows - 2).toList();
    final pool = near.isNotEmpty ? near : candidates;
    final rng = Random();
    final pos = pool[rng.nextInt(pool.length)];
    final cell = board[pos[0]][pos[1]];
    final newBoard = _copyBoard(board);
    newBoard[pos[0]][pos[1]] = cell.copyWith(kind: CellKind.unlocked);
    state = state.copyWith(aiBoard: newBoard);
  }

  void aiRecruit() {
    final cost = getRecruitCost(state.aiRecruitTimes);
    if (state.aiFood < cost) return;
    state = state.copyWith(
      aiFood: state.aiFood - cost,
      aiRecruitTimes: state.aiRecruitTimes + 1,
    );
  }

  void aiAddFood(int amount) {
    state = state.copyWith(aiFood: state.aiFood + amount);
  }

  // AI 嘗試合併相鄰同種同級單位（對齊 Vue aiTryMerge）
  bool aiMergeUnits() {
    final board = state.aiBoard;
    const deltas = [[-1,0],[1,0],[0,-1],[0,1]];
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final unit = board[r][c].unit;
        if (unit == null || unit.type != 'unit') continue;
        for (final d in deltas) {
          final nr = r + d[0], nc = c + d[1];
          if (nr < 0 || nr >= kRows || nc < 0 || nc >= kCols) continue;
          final nb = board[nr][nc].unit;
          if (nb == null || nb.type != 'unit') continue;
          if (unit.key == nb.key && unit.level == nb.level && unit.level < unit.maxLevel) {
            final newBoard = _copyBoard(board);
            newBoard[nr][nc] = board[nr][nc].copyWith(unit: nb.copyWith(level: nb.level + 1));
            newBoard[r][c] = board[r][c].copyWith(clearUnit: true);
            state = state.copyWith(aiBoard: newBoard);
            return true;
          }
        }
      }
    }
    return false;
  }

  // ── 工具 ────────────────────────────────────────────

  static List<List<Cell>> _copyBoard(List<List<Cell>> board) {
    return List.generate(board.length, (r) => List<Cell>.from(board[r]));
  }
}
