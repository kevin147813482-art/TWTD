<template>
  <!-- 有精灵图：显示动画精灵 -->
  <img v-if="asset.sprite"
    :src="asset.sprite"
    :alt="asset.char"
    :class="['enemy-sprite', `anim-${animState}`]"
  />
  <!-- 无精灵图：汉字占位 -->
  <span v-else class="enemy-char-text" :style="{ color: asset.color }">{{ asset.char }}</span>
</template>

<script setup>
import { computed } from 'vue'
import { ENEMY_ASSETS } from '../game/assets.js'

const props = defineProps({
  enemyKey:  { type: String, required: true },
  // 动画状态：idle | attack | death
  animState: { type: String, default: 'idle' },
})

const asset = computed(() =>
  ENEMY_ASSETS[props.enemyKey] ?? { char: props.enemyKey, color: '#333', sprite: null }
)
</script>

<style scoped>
.enemy-sprite {
  width: 80%;
  height: 80%;
  object-fit: contain;
}
.enemy-sprite.anim-attack { animation: enemyAtk 0.3s ease-out; }
.enemy-sprite.anim-death  { animation: enemyDie 0.4s ease-out forwards; }
@keyframes enemyAtk { 0%{transform:scale(1)} 50%{transform:scale(1.2)} 100%{transform:scale(1)} }
@keyframes enemyDie { to { opacity: 0; transform: scale(0.3) translateY(-20px); } }
</style>
