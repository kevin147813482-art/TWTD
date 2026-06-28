/**
 * 游戏视觉资源注册表 — 唯一入口
 *
 * 替换素材时只修改此文件，无需改动组件或模板。
 * sprite: null → 显示汉字占位；string → 图片/精灵表路径
 * frames: 精灵表动画帧定义，格式 { idle, attack, skill, death }
 *         每帧: { x, y, w, h, count, fps }（未来接 CSS animation 或 Canvas）
 * animState 枚举: 'idle' | 'attack' | 'skill' | 'death'
 */

// ── 单位（棋盘友军） ──────────────────────────────────────────────────────────
export const UNIT_ASSETS = {
  // 基础兵种
  步:  { char: '步', sprite: null, frames: null },
  炮:  { char: '炮', sprite: null, frames: null },
  槍:  { char: '槍', sprite: null, frames: null },
  坦:  { char: '坦', sprite: null, frames: null },
  // 武将（两字key，char 取首字占位）
  立人: { char: '立', sprite: null, frames: null },
  崇禧: { char: '崇', sprite: null, frames: null },
  薛岳: { char: '薛', sprite: null, frames: null },
  靈甫: { char: '靈', sprite: null, frames: null },
  宗南: { char: '宗', sprite: null, frames: null },
  耀湘: { char: '耀', sprite: null, frames: null },
}

// ── 主将（蒋） ────────────────────────────────────────────────────────────────
export const JIANG_ASSETS = {
  player: { char: '蔣', sprite: null, frames: null },
  ai:     { char: '蔣', sprite: null, frames: null },
}

// ── 敌军 ─────────────────────────────────────────────────────────────────────
export const ENEMY_ASSETS = {
  // 普通敌军
  匪: { char: '匪', color: '#555',    sprite: null, frames: null },
  共: { char: '共', color: '#1a237e', sprite: null, frames: null },
  赤: { char: '赤', color: '#c62828', sprite: null, frames: null },
  寇: { char: '寇', color: '#4e342e', sprite: null, frames: null },
  // BOSS
  朱德: { char: '朱', color: '#b71c1c', sprite: null, frames: null },
  林彪: { char: '林', color: '#880e4f', sprite: null, frames: null },
  德懷: { char: '德', color: '#4a148c', sprite: null, frames: null },
  恩來: { char: '恩', color: '#1a237e', sprite: null, frames: null },
  澤東: { char: '澤', color: '#bf360c', sprite: null, frames: null },
}

// ── 投射物 ───────────────────────────────────────────────────────────────────
export const PROJECTILE_ASSETS = {
  slash:  { char: '✦', sprite: null },
  bullet: { char: '·', sprite: null },
  shell:  { char: '●', sprite: null },
  arrow:  { char: '→', sprite: null },
}

// ── 地块 ─────────────────────────────────────────────────────────────────────
export const TILE_ASSETS = {
  path:     { sprite: null },   // 路径格（敌军走的格子）
  unlocked: { sprite: null },   // 解锁格（可放单位）
  locked:   { sprite: null },   // 锁定格（需鏟子解锁）
}

// ── 技能特效 ──────────────────────────────────────────────────────────────────
// duration: 特效持续时间(ms)；sprite: 特效精灵图/视频路径
export const SKILL_EFFECT_ASSETS = {
  鐵拳: { sprite: null, duration: 600 },
  謀略: { sprite: null, duration: 800 },
  天爐: { sprite: null, duration: 1000 },
  突擊: { sprite: null, duration: 600 },
  守備: { sprite: null, duration: 800 },
  鋼甲: { sprite: null, duration: 600 },
  封鎖: { sprite: null, duration: 1200 },
  摧魂: { sprite: null, duration: 1500 },
  召魂: { sprite: null, duration: 1800 },
  滲透: { sprite: null, duration: 1200 },
  人海: { sprite: null, duration: 2000 },
}
