import { onUnmounted, ref, watch } from 'vue'

/**
 * 轻量级力导向布局
 * 为节点拓扑提供弹簧物理：拖拽一个节点时，绑定节点会像被弹簧牵引一样跟随
 */
export function useNodeForceLayout({
  nodes,
  bindings,
  width,
  height,
  enabled,
  pinnedId,
  getInitialPosition,
}) {
  const positions = ref({})
  const velocities = ref({})
  const isRunning = ref(false)

  let rafId = null
  let lastTime = null

  const params = {
    springK: 0.05,
    restLength: 140,
    repulsion: 8000,
    repulsionRange: 300,
    centerPull: 0.005,
    damping: 0.85,
    maxSpeed: 30,
    dtScale: 0.3,
  }

  function ensureNode(id) {
    if (!positions.value[id]) {
      const init = getInitialPosition?.(id) || { x: width.value / 2, y: height.value / 2 }
      positions.value = { ...positions.value, [id]: { ...init } }
      velocities.value = { ...velocities.value, [id]: { vx: 0, vy: 0 } }
    }
  }

  function removeDeletedNodes() {
    const ids = new Set(nodes.value.map(n => n.id))
    const newPositions = {}
    const newVelocities = {}
    for (const id in positions.value) {
      if (ids.has(id)) {
        newPositions[id] = positions.value[id]
        newVelocities[id] = velocities.value[id]
      }
    }
    positions.value = newPositions
    velocities.value = newVelocities
  }

  function step(deltaMs) {
    const ids = nodes.value.map(n => n.id)
    ids.forEach(ensureNode)

    const dt = Math.min(deltaMs, 50) * params.dtScale / 1000
    const cx = width.value / 2
    const cy = height.value / 2
    const forces = Object.fromEntries(ids.map(id => [id, { fx: 0, fy: 0 }]))

    // 构建邻接表
    const adj = {}
    bindings.value.forEach((b) => {
      adj[b.controllerId] = adj[b.controllerId] || []
      adj[b.controllerId].push(b.actuatorId)
      adj[b.actuatorId] = adj[b.actuatorId] || []
      adj[b.actuatorId].push(b.controllerId)
    })

    ids.forEach((id) => {
      const p = positions.value[id]
      const f = forces[id]

      // 向心力
      f.fx += (cx - p.x) * params.centerPull
      f.fy += (cy - p.y) * params.centerPull

      // 节点斥力
      ids.forEach((oid) => {
        if (oid === id)
          return
        const op = positions.value[oid]
        const dx = p.x - op.x
        const dy = p.y - op.y
        const dist = Math.sqrt(dx * dx + dy * dy) || 1
        if (dist < params.repulsionRange) {
          const force = params.repulsion / (dist * dist)
          f.fx += (dx / dist) * force
          f.fy += (dy / dist) * force
        }
      })

      // 弹簧力
      ;(adj[id] || []).forEach((oid) => {
        const op = positions.value[oid]
        const dx = op.x - p.x
        const dy = op.y - p.y
        const dist = Math.sqrt(dx * dx + dy * dy) || 1
        const force = (dist - params.restLength) * params.springK
        f.fx += (dx / dist) * force
        f.fy += (dy / dist) * force
      })
    })

    // 积分
    ids.forEach((id) => {
      if (pinnedId.value === id) {
        velocities.value = { ...velocities.value, [id]: { vx: 0, vy: 0 } }
        return
      }

      let { vx, vy } = velocities.value[id]
      const { fx, fy } = forces[id]
      vx = (vx + fx * dt) * params.damping
      vy = (vy + fy * dt) * params.damping

      const speed = Math.sqrt(vx * vx + vy * vy)
      if (speed > params.maxSpeed) {
        vx = (vx / speed) * params.maxSpeed
        vy = (vy / speed) * params.maxSpeed
      }

      velocities.value = { ...velocities.value, [id]: { vx, vy } }

      const margin = 30
      positions.value = {
        ...positions.value,
        [id]: {
          x: Math.max(margin, Math.min(width.value - margin, positions.value[id].x + vx)),
          y: Math.max(margin, Math.min(height.value - margin, positions.value[id].y + vy)),
        },
      }
    })
  }

  function loop(t) {
    if (!enabled.value)
      return
    step(t - (lastTime ?? t))
    lastTime = t
    rafId = requestAnimationFrame(loop)
  }

  function start() {
    if (rafId)
      return
    lastTime = null
    isRunning.value = true
    rafId = requestAnimationFrame(loop)
  }

  function stop() {
    if (!rafId)
      return
    cancelAnimationFrame(rafId)
    rafId = null
    isRunning.value = false
    lastTime = null
  }

  function reset() {
    stop()
    positions.value = {}
    velocities.value = {}
  }

  function updatePosition(id, x, y) {
    positions.value = { ...positions.value, [id]: { x, y } }
    velocities.value = { ...velocities.value, [id]: { vx: 0, vy: 0 } }
  }

  watch(enabled, (v) => {
    v ? start() : stop()
  }, { immediate: true })

  watch(() => nodes.value.length, () => {
    removeDeletedNodes()
  })

  onUnmounted(() => {
    stop()
  })

  return {
    positions,
    velocities,
    isRunning,
    start,
    stop,
    reset,
    updatePosition,
  }
}
