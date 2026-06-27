<template>
  <div class="result-screen" :class="isVictory ? 'victory' : 'defeat'">
    <div class="result-banner">
      <div class="result-title">{{ isVictory ? '勝利！' : '失敗' }}</div>
      <div class="result-subtitle">{{ isVictory ? '恭喜守住蔣！' : '蔣已陣亡，再接再厲！' }}</div>
    </div>
    <div class="jiang-result">{{ isVictory ? '蔣' : '蔣' }}</div>
    <div class="score-display">
      <div class="score-label">擊殺敵軍</div>
      <div class="score-value">{{ store.score }}</div>
    </div>
    <div class="result-buttons">
      <button class="btn-primary" @click="$emit('restart')">再戰一局</button>
      <button class="btn-secondary" @click="$emit('home')">返回主頁</button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { gameStore as store } from '../stores/gameStore.js'

const props = defineProps({ phase: String })
defineEmits(['restart', 'home'])

const isVictory = computed(() => props.phase === 'victory')
</script>

<style scoped>
.result-screen {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  gap: 1.5rem;
}

.victory { background: linear-gradient(180deg, #1a3a1a, #2d5a2d); }
.defeat { background: linear-gradient(180deg, #3a1a1a, #5a2d2d); }

.result-banner {
  text-align: center;
}

.result-title {
  font-size: 3rem;
  font-weight: bold;
  color: #ffd700;
}

.result-subtitle {
  font-size: 1rem;
  color: #ddd;
}

.jiang-result {
  font-size: 5rem;
  font-weight: bold;
  color: #ffd700;
  background: rgba(0,0,0,0.3);
  border: 3px solid #ffd700;
  border-radius: 12px;
  width: 100px;
  height: 100px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.score-display {
  text-align: center;
  color: white;
}

.score-label { font-size: 0.9rem; color: #aaa; }
.score-value { font-size: 2.5rem; font-weight: bold; color: #ffd700; }

.result-buttons {
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 200px;
}

.btn-primary {
  padding: 12px;
  background: linear-gradient(135deg, #c41e3a, #8b0000);
  color: white;
  border: 2px solid #ffd700;
  border-radius: 8px;
  font-size: 1.1rem;
  font-weight: bold;
  cursor: pointer;
}

.btn-secondary {
  padding: 12px;
  background: rgba(255,255,255,0.1);
  color: #ddd;
  border: 1px solid #555;
  border-radius: 8px;
  font-size: 1rem;
  cursor: pointer;
}
</style>
