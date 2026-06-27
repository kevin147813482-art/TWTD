<template>
  <div class="home-screen">
    <div class="title">立人與中正</div>
    <div class="subtitle">保衛蔣，守住中華民國！</div>
    <div class="jiang-display">蔣</div>
    <button class="start-btn" @click="$emit('start')">開始遊戲</button>
  </div>
</template>

<script setup>
defineEmits(['start'])
</script>

<style scoped>
.home-screen {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  background: linear-gradient(180deg, #2c1810 0%, #4a2c1a 100%);
  color: #f5e6c8;
}
.title {
  font-size: 2.5rem;
  font-weight: bold;
  color: #ffd700;
  text-shadow: 2px 2px 8px rgba(0,0,0,0.8);
  margin-bottom: 0.5rem;
}
.subtitle {
  font-size: 1rem;
  color: #d4b896;
  margin-bottom: 2rem;
}
.jiang-display {
  font-size: 6rem;
  font-weight: bold;
  color: #ffd700;
  background: rgba(0,0,0,0.3);
  border: 3px solid #ffd700;
  border-radius: 12px;
  width: 120px;
  height: 120px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 2rem;
  box-shadow: 0 0 20px rgba(255,215,0,0.3);
}
.start-btn {
  padding: 1rem 3rem;
  font-size: 1.3rem;
  background: linear-gradient(135deg, #c41e3a, #8b0000);
  color: white;
  border: 2px solid #ffd700;
  border-radius: 8px;
  cursor: pointer;
  font-weight: bold;
  letter-spacing: 0.1em;
}
.start-btn:active {
  transform: scale(0.97);
}
</style>
