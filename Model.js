function emptyState() {
  return {
    ok: true,
    active: false,
    mic: [],
    camera: [],
    screen: [],
    counts: { mic: 0, camera: 0, screen: 0, total: 0 },
  }
}

function parseScan(raw) {
  try {
    var data = JSON.parse(String(raw || "").trim() || "{}")
    if (!data || typeof data !== "object") return emptyState()
    var mic = Array.isArray(data.mic) ? data.mic : []
    var camera = Array.isArray(data.camera) ? data.camera : []
    var screen = Array.isArray(data.screen) ? data.screen : []
    var counts = data.counts || {}
    return {
      ok: data.ok !== false,
      active: !!(data.active || mic.length || camera.length || screen.length),
      mic: mic,
      camera: camera,
      screen: screen,
      counts: {
        mic: Number(counts.mic != null ? counts.mic : mic.length) || 0,
        camera: Number(counts.camera != null ? counts.camera : camera.length) || 0,
        screen: Number(counts.screen != null ? counts.screen : screen.length) || 0,
        total: Number(counts.total != null ? counts.total : (mic.length + camera.length + screen.length)) || 0,
      },
    }
  } catch (e) {
    return emptyState()
  }
}

function barLabel(state) {
  if (!state || !state.active) return "󰕥"
  var parts = []
  if (state.counts && state.counts.mic > 0) parts.push("󰍬")
  if (state.counts && state.counts.camera > 0) parts.push("󰄀")
  if (state.counts && state.counts.screen > 0) parts.push("󰹑")
  return parts.length ? parts.join("") : "󰀪"
}

function tooltip(state) {
  if (!state) return "Privacy Pulse"
  if (!state.active) return "Privacy clear — no mic, camera, or screen capture"
  var bits = []
  if (state.counts.mic) bits.push(state.counts.mic + " mic")
  if (state.counts.camera) bits.push(state.counts.camera + " camera")
  if (state.counts.screen) bits.push(state.counts.screen + " screen")
  return "In use: " + bits.join(", ")
}

function sectionTitle(kind) {
  if (kind === "mic") return "Microphone"
  if (kind === "camera") return "Camera"
  if (kind === "screen") return "Screen share"
  return kind
}

function sectionIcon(kind) {
  if (kind === "mic") return "󰍬"
  if (kind === "camera") return "󰄀"
  if (kind === "screen") return "󰹑"
  return "•"
}

function flattenRows(state) {
  var rows = []
  var kinds = ["mic", "camera", "screen"]
  for (var i = 0; i < kinds.length; i++) {
    var kind = kinds[i]
    var items = (state && state[kind]) || []
    if (!items.length) continue
    rows.push({ type: "header", kind: kind, title: sectionTitle(kind), icon: sectionIcon(kind) })
    for (var j = 0; j < items.length; j++) {
      var item = items[j] || {}
      rows.push({
        type: "item",
        kind: kind,
        app: String(item.app || "unknown"),
        detail: String(item.detail || ""),
        pid: item.pid != null ? item.pid : null,
      })
    }
  }
  if (!rows.length) {
    rows.push({ type: "empty", title: "All clear", detail: "No mic, camera, or screen capture in use" })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyState: emptyState,
    parseScan: parseScan,
    barLabel: barLabel,
    tooltip: tooltip,
    flattenRows: flattenRows,
    sectionTitle: sectionTitle,
    sectionIcon: sectionIcon,
  }
}
