<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useNodeStore } from '@/store/useNodeStore'

const props = defineProps({
  width: { type: Number, default: 800 },
  height: { type: Number, default: 500 },
})

const emit = defineEmits(['nodeClick', 'nodeDblclick'])

const store = useNodeStore()
const svgRef = ref(null)

// 布局：根据节点数量自动分配位置
function autoLayout() {
  const controllers = store.controllers.value
  const actuators = store.actuators.value
  const padding = 60
  const ctrlGapX = (props.width - padding * 2) / Math.max(controllers.length || 1, 1)
  const actGapX = (props.width - padding * 2) / Math.max(actuators.length || 1, 1)

  controllers.forEach((node, i) => {
    if (!store.getNodePosition(node.id)) {
      const x = padding + i * ctrlGapX + ctrlGapX / 2
      store.updateNodePosition(node.id, x, 80)
    }
  })

  actuators.forEach((node, i) => {
    if (!store.getNodePosition(node.id)) {
      const x = padding + i * actGapX + actGapX / 2
      store.updateNodePosition(node.id, x, props.height - 80)
    }
  })
}

onMounted(() => {
  autoLayout()
})

// 节点新增/删除时自动补位，避免依赖外层强制 key 重挂载
watch(() => store.nodes.value.length, () => {
  autoLayout()
})

// 节点在画布上的渲染数据
const nodeElements = computed(() => {
  return store.nodes.value.map((node) => {
    const pos = store.getNodePosition(node.id) || { x: props.width / 2, y: props.height / 2 }
    const isController = node.type === 'controller'
    return {
      id: node.id,
      x: pos.x,
      y: pos.y,
      r: 24,
      name: node.name || node.id,
      fill: node.status === 'online'
        ? (isController ? '#3b82f6' : '#22c55e')
        : (node.status === 'offline' ? '#6b7280' : '#f59e0b'),
      stroke: store.selectedNodeId.value === node.id ? '#facc15' : 'none',
      strokeWidth: store.selectedNodeId.value === node.id ? 3 : 0,
      type: isController ? '控制器' : '执行器',
    }
  })
})

// 连线渲染数据：自动将控制器与所有执行器用线连接
const linkElements = computed(() => {
  const controllers = store.controllers.value
  const actuators = store.actuators.value
  if (controllers.length === 0 || actuators.length === 0)
    return []

  const ctrl = controllers[0]
  const ctrlPos = store.getNodePosition(ctrl.id)
  if (!ctrlPos)
    return []

  const nodeR = 24
  return actuators.map((act) => {
    const actPos = store.getNodePosition(act.id)
    if (!actPos)
      return null

    const dx = actPos.x - ctrlPos.x
    const dy = actPos.y - ctrlPos.y
    const dist = Math.sqrt(dx * dx + dy * dy) || 1
    const ux = dx / dist
    const uy = dy / dist

    // 起点从控制器边缘出发，终点在执行器边缘前预留箭头空间
    return {
      id: `link_${ctrl.id}_${act.id}`,
      x1: ctrlPos.x + ux * nodeR,
      y1: ctrlPos.y + uy * nodeR,
      x2: actPos.x - ux * (nodeR + 8),
      y2: actPos.y - uy * (nodeR + 8),
    }
  }).filter(Boolean)
})

// 拖拽
const dragging = ref(null)
let dragStartX = 0
let dragStartY = 0
let nodeStartX = 0
let nodeStartY = 0

function onPointerDown(e, nodeId) {
  const pos = store.getNodePosition(nodeId)
  if (!pos)
    return
  dragging.value = nodeId
  dragStartX = e.clientX
  dragStartY = e.clientY
  nodeStartX = pos.x
  nodeStartY = pos.y
  store.selectNode(nodeId)
  e.target.setPointerCapture(e.pointerId)
}

function onPointerMove(e) {
  if (!dragging.value)
    return
  const dx = e.clientX - dragStartX
  const dy = e.clientY - dragStartY
  const newX = Math.max(30, Math.min(props.width - 30, nodeStartX + dx))
  const newY = Math.max(30, Math.min(props.height - 30, nodeStartY + dy))
  store.updateNodePosition(dragging.value, newX, newY)
}

function onPointerUp() {
  dragging.value = null
}
</script>

<template>
  <svg
    ref="svgRef"
    :viewBox="`0 0 ${width} ${height}`"
    class="w-full h-full bg-background/20"
    @pointermove="onPointerMove"
    @pointerup="onPointerUp"
    @pointerleave="onPointerUp"
  >
    <!-- 绑定关系箭头标记 -->
    <defs>
      <marker
        id="arrowhead"
        markerWidth="10"
        markerHeight="7"
        refX="10"
        refY="3.5"
        orient="auto"
      >
        <polygon points="0 0, 10 3.5, 0 7" fill="#6366f1" />
      </marker>
    </defs>

    <!-- 连线 -->
    <g v-if="linkElements.length > 0">
      <line
        v-for="link in linkElements"
        :key="link.id"
        :x1="link.x1"
        :y1="link.y1"
        :x2="link.x2"
        :y2="link.y2"
        stroke="#6366f1"
        stroke-width="2"
        marker-end="url(#arrowhead)"
        class="cursor-pointer"
      />
    </g>

    <!-- 空状态提示 -->
    <text
      v-if="store.nodes.value.length === 0"
      :x="width / 2"
      :y="height / 2"
      text-anchor="middle"
      fill="#9ca3af"
      font-size="14"
    >
      暂无节点，点击"扫描"或"添加"按钮开始
    </text>

    <!-- 节点 -->
    <g
      v-for="node in nodeElements"
      :key="node.id"
      :style="{ cursor: dragging === node.id ? 'grabbing' : 'grab' }"
      @pointerdown="e => onPointerDown(e, node.id)"
      @click="emit('nodeClick', node.id)"
      @dblclick="emit('nodeDblclick', node.id)"
    >
      <!-- 阴影 -->
      <circle
        :cx="node.x + 2"
        :cy="node.y + 2"
        :r="node.r"
        fill="rgba(0,0,0,0.15)"
      />
      <!-- 节点圆 -->
      <circle
        :cx="node.x"
        :cy="node.y"
        :r="node.r"
        :fill="node.fill"
        :stroke="node.stroke"
        :stroke-width="node.strokeWidth"
        class="transition-colors duration-200"
      />
      <!-- 节点类型标签 -->
      <text
        :x="node.x"
        :y="node.y + 4"
        text-anchor="middle"
        fill="white"
        font-size="11"
        font-weight="bold"
      >
        {{ node.type === '控制器' ? 'C' : 'A' }}
      </text>
      <!-- 节点名称 -->
      <text
        :x="node.x"
        :y="node.y + node.r + 16"
        text-anchor="middle"
        fill="currentColor"
        font-size="12"
        class="select-none"
      >
        {{ node.name.length > 8 ? `${node.name.slice(0, 8)}…` : node.name }}
      </text>
    </g>
  </svg>
</template>
