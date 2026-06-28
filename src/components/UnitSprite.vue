<template>
  <!-- 有精灵图：显示动画精灵 -->
  <img v-if="asset.sprite"
    :src="asset.sprite"
    :alt="displayChar"
    :class="['unit-sprite', `anim-${animState}`]"
  />
  <!-- 无精灵图：汉字占位 -->
  <span v-else class="unit-char-text">{{ displayChar }}</span>
</template>

<script setup>
import { computed } from 'vue'
import { UNIT_ASSETS } from '../game/assets.js'

const props = defineProps({
  unit: { type: Object, required: true },
  // 动画状态：idle | attack | skill | death
  animState: { type: String, default: 'idle' },
})

const asset = computed(() =>
  UNIT_ASSETS[props.unit.type] ?? { char: props.unit.key, sprite: null }
)

// 武将两字显示 unit.char（来自config chars数组），普通兵种用 asset.char
const displayChar = computed(() =>
  props.unit.type === 'general_char' ? props.unit.char : asset.value.char
)
</script>

<style scoped>
.unit-sprite {
  width: 100%;
  height: 100%;
  object-fit: contain;
}
/* anim-attack / anim-skill / anim-death 在有精灵图时激活 */
.unit-sprite.anim-attack { animation: unitAtk 0.3s ease-out; }
.unit-sprite.anim-death  { animation: unitDie 0.5s ease-out forwards; }
@keyframes unitAtk { 0%{transform:scale(1)} 50%{transform:scale(1.15)} 100%{transform:scale(1)} }
@keyframes unitDie { to { opacity: 0; transform: scale(0.5); } }
</style>
