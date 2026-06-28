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

  void playerRecruit() {
    final cost = state.playerRecruitCost;
    if (state.playerFood < cost) return;

    final newHand = List<HandCard?>.from(state.playerHand);
    // 隨機產生 kHandSize 張牌填滿手牌
    final keys = kBasicUnits.keys.toList();
    for (int i = 0; i < kHandSize; i++) {
      final k = keys[_rng.nextInt(keys.length)];
      final lv = _rng.nextDouble() < 0.2 ? 2 : 1;
      newHand[i] = HandCard(type: 'unit', key: k, level: lv);
    }

    state = state.copyWith(
      playerFood: state.playerFood - cost,
      playerRecruitTimes: state.playerRecruitTimes + 1,
      playerRecruitVersion: state.playerRecruitVersion + 1,
      playerHand: newHand,
    );
  }

  void addShovelToHand() {
    final newHand = List<HandCard?>.from(state.playerHand);
    final slot = newHand.indexWhere((c) => c == null);
    if (slot == -1) return;
    newHand[slot] = const HandCard(type: 'shovel', key: '鏟');
    state = state.copyWith(playerHand: newHand);
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

    // 有單位：同種同級升級合並，否則替換（原單位退回手牌）
    if (cell.unit != null) {
      final existing = cell.unit!;
      final newBoard = _copyBoard(board);
      final newHand = List<HandCard?>.from(state.playerHand);
      if (existing.key == card.key && existing.type == card.type &&
          existing.level == card.level && existing.level < existing.maxLevel) {
        // 同兵種同等級 → 升級合並
        newBoard[row][col] = cell.copyWith(
          unit: existing.copyWith(level: existing.level + 1),
        );
        newHand[handIndex] = null;
        state = state.copyWith(playerBoard: newBoard, playerHand: newHand);
        return;
      }
      // 不同兵種/等級 → 替換：原單位退回手牌，新卡放入
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
      if (target.key == movingUnit.key && target.type == movingUnit.type &&
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

  void returnUnitToHand(int row, int col, int slotIndex) {
    final board = state.playerBoard;
    final cell = board[row][col];
    if (cell.unit == null) return;
    final existingCard = state.playerHand[slotIndex];
    if (existingCard != null) return; // 目標格有牌

    final newHand = List<HandCard?>.from(state.playerHand);
    newHand[slotIndex] = cell.unit!.toHandCard();
    final newBoard = _copyBoard(board);
    newBoard[row][col] = cell.copyWith(clearUnit: true);
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

  void aiDeployUnit(String key, int row, int col, {int level = 1}) {
    final board = state.aiBoard;
    final cell = board[row][col];
    if (cell.kind != CellKind.unlocked || cell.unit != null) return;

    final unit = Unit(
      id: _uid('au'), type: 'unit', key: key,
      level: level, row: row, col: col,
    );
    final newBoard = _copyBoard(board);
    newBoard[row][col] = cell.copyWith(unit: unit);
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

  // ── 工具 ────────────────────────────────────────────

  static List<List<Cell>> _copyBoard(List<List<Cell>> board) {
    return List.generate(board.length, (r) => List<Cell>.from(board[r]));
  }
}
