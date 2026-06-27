<template>
  <div class="app">
    <HomeScreen v-if="store.phase === 'home'" @start="startGame" />
    <GameBoard v-else-if="store.phase === 'playing' || store.phase === 'paused'" />
    <ResultScreen v-else-if="store.phase === 'victory' || store.phase === 'defeat'"
      :phase="store.phase"
      @restart="startGame"
      @home="goHome"
    />
  </div>
</template>

<script setup>
import { onUnmounted } from 'vue'
import { gameStore as store } from './stores/gameStore.js'
import { startEngine, stopEngine } from './game/engine.js'
import HomeScreen from './components/HomeScreen.vue'
import GameBoard from './components/GameBoard.vue'
import ResultScreen from './components/ResultScreen.vue'

function startGame() {
  stopEngine()
  store.startGame()
  startEngine()
}

function goHome() {
  stopEngine()
  store.phase = 'home'
}

onUnmounted(() => stopEngine())
</script>

<style>
* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Noto Serif TC', '黑體', serif;
  background: #111;
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
}

.app {
  width: 100%;
  max-width: 420px;
  height: 100vh;
  max-height: 900px;
  position: relative;
  overflow: hidden;
  background: #1a1a1a;
}
</style>
