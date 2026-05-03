// Call hook — bridges the LiveView UI to the Phoenix `room:<slug>`
// channel that fronts the Membrane RTC Engine. Also paints accessory
// overlays on top of each video tile when the LV pushes
// `muddle:pin` / `muddle:unpin` events, with face-landmark tracking
// via MediaPipe FaceLandmarker.
import {Socket} from "phoenix"

// MediaPipe face mesh landmark indices for face-anchored keypoints.
// `scale` is the accessory width as a fraction of detected face width.
// `anchorY` shifts the image vertically relative to its own height —
// 0.0 = image bottom rests on the landmark, 0.5 = image centered,
// 1.0 = image top sits at the landmark (good for hats).
const FACE_KEYPOINTS = {
  head:           {idx: 10,  scale: 1.4, anchorY: 1.0},
  forehead:       {idx: 10,  scale: 0.9, anchorY: 0.6},
  left_eye:       {idx: 33,  scale: 0.40, anchorY: 0.5},
  right_eye:      {idx: 263, scale: 0.40, anchorY: 0.5},
  nose:           {idx: 1,   scale: 0.35, anchorY: 0.5},
  mouth:          {idx: 13,  scale: 0.55, anchorY: 0.5},
  left_ear:       {idx: 234, scale: 0.40, anchorY: 0.5},
  right_ear:      {idx: 454, scale: 0.40, anchorY: 0.5},
  chin:           {idx: 152, scale: 0.60, anchorY: 0.0},
}

// MediaPipe Pose model has 33 anatomical landmarks. The names below
// describe how each Muddle keypoint resolves to one — either a single
// landmark index or a function that derives a point (e.g. neck =
// midpoint of shoulders). Sizing comes from `widthFn`, which gets the
// pose landmarks and returns a fraction of frame width to use.
//
// Indices we use:
//    11 = left shoulder, 12 = right shoulder
//    15 = left wrist,    16 = right wrist
//    23 = left hip,      24 = right hip
const POSE_KEYPOINTS = {
  left_shoulder:  {idx: 11, scale: 0.40, anchorY: 0.5},
  right_shoulder: {idx: 12, scale: 0.40, anchorY: 0.5},
  left_hand:      {idx: 15, scale: 0.30, anchorY: 0.5},
  right_hand:     {idx: 16, scale: 0.30, anchorY: 0.5},
  neck:           {fn: l => midpoint(l[11], l[12]), scale: 0.45, anchorY: 0.4},
  chest:          {fn: l => centroid([l[11], l[12], l[23], l[24]]), scale: 0.65, anchorY: 0.5},
}

// Static fractional fallback when pose detection hasn't produced a
// frame yet (or fails). Keeps the accessory visible at a reasonable
// spot so the user knows it's pinned.
const BODY_FALLBACK = {
  neck:           {x: 0.50, y: 0.80, size: 0.40},
  left_shoulder:  {x: 0.25, y: 0.85, size: 0.35},
  right_shoulder: {x: 0.75, y: 0.85, size: 0.35},
  chest:          {x: 0.50, y: 0.95, size: 0.50},
  left_hand:      {x: 0.15, y: 0.70, size: 0.25},
  right_hand:     {x: 0.85, y: 0.70, size: 0.25},
}

const MEDIAPIPE_VERSION = "0.10.18"
const MEDIAPIPE_BASE = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}`
const FACE_MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
const POSE_MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"

const Call = {
  async mounted() {
    this.slug = this.el.dataset.roomSlug
    this.peerId = this.el.dataset.peerId
    this.userId = parseInt(this.el.dataset.userId, 10)
    this.token = this.el.dataset.socketToken

    // Pin records keyed by `${userId}|${keypoint}`. Each: {image_url, keypoint}.
    this.pins = new Map()
    // Per-tile most recent face mesh result.
    this.faceLandmarks = new Map() // tileId -> {points, faceWidth, faceHeight}
    // Per-tile most recent pose result.
    this.poseLandmarks = new Map() // tileId -> {points, scale}

    this.handleEvent("muddle:pin", payload => this.applyPin(payload))
    this.handleEvent("muddle:unpin", payload => this.removePin(payload))

    await this.startLocalMedia()
    this.connectChannel()
    this.startTracking()
  },

  destroyed() {
    this._tracking = false
    if (this.localStream) this.localStream.getTracks().forEach(t => t.stop())
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
    for (const lm of [this.faceLandmarker, this.poseLandmarker]) {
      if (lm) { try { lm.close() } catch (_) {} }
    }
    this.faceLandmarker = null
    this.poseLandmarker = null
  },

  async startLocalMedia() {
    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({audio: true, video: true})
      this.addTile("self", this.localStream, {muted: true, label: "you", userId: this.userId})
    } catch (err) {
      console.error("[muddle] getUserMedia failed", err)
      this.showError(`camera/mic blocked: ${err.message || err.name}`)
    }
  },

  connectChannel() {
    this.socket = new Socket("/socket", {params: {token: this.token}})
    this.socket.onError(err => console.error("[muddle] socket error", err))
    this.socket.connect()

    this.channel = this.socket.channel(`room:${this.slug}`, {peer_id: this.peerId})
    this.channel.on("media_event", ({event}) => this.applyMediaEvent(event))

    this.channel.join()
      .receive("ok", () => {
        console.info("[muddle] joined room", this.slug)
        if (this.localStream) this.produceTracks(this.localStream)
      })
      .receive("error", err => {
        console.error("[muddle] channel join failed", err)
        this.showError(`could not join room: ${err.reason || JSON.stringify(err)}`)
      })
      .receive("timeout", () => console.warn("[muddle] channel join timed out"))
  },

  produceTracks(_stream) {
    // Replace with Membrane WebRTC JS SDK glue: forward SDP/ICE events
    // to the channel as `media_event` messages.
  },

  applyMediaEvent(_event) {
    // SDK consumes server media events here and emits `onTrackReady`
    // callbacks → call `addTile(peerId, stream, {userId})`.
  },

  // --- Tile management -------------------------------------------------

  addTile(id, stream, opts = {}) {
    const tiles = document.getElementById("video-tiles")
    if (!tiles) return null

    let el = document.getElementById(`tile-${id}`)
    if (!el) {
      el = document.createElement("div")
      el.id = `tile-${id}`
      el.className = "relative aspect-video rounded-box overflow-hidden bg-black"
      if (opts.userId != null) el.dataset.userId = String(opts.userId)

      const video = document.createElement("video")
      video.autoplay = true
      video.playsInline = true
      if (opts.muted) video.muted = true
      video.style.width = "100%"
      video.style.height = "100%"
      video.style.objectFit = "cover"
      el.appendChild(video)

      const overlay = document.createElement("div")
      overlay.className = "absolute inset-0 pointer-events-none"
      overlay.dataset.role = "accessory-overlay"
      // Perspective lets rotateX/rotateY produce real 3D foreshortening
      // on accessory images (otherwise they'd just shear).
      overlay.style.perspective = "800px"
      overlay.style.transformStyle = "preserve-3d"
      el.appendChild(overlay)

      if (opts.label) {
        const label = document.createElement("div")
        label.className = "absolute bottom-1 left-2 text-xs bg-black/60 text-white px-2 py-0.5 rounded"
        label.textContent = opts.label
        el.appendChild(label)
      }

      tiles.appendChild(el)
    }
    el.querySelector("video").srcObject = stream
    return el
  },

  // --- Accessory overlays ---------------------------------------------

  applyPin(payload) {
    const {user_id, keypoint, image_url, accessory_id, calibration} = payload
    if (!image_url) return
    const tile = this.tileForUser(user_id)
    if (!tile) {
      console.warn("[muddle] pin for unknown user", user_id)
      return
    }
    const overlay = tile.querySelector('[data-role="accessory-overlay"]')
    const id = `pin-${user_id}-${keypoint}`
    const isMine = Number(user_id) === this.userId
    let img = overlay.querySelector(`#${CSS.escape(id)}`)
    if (!img) {
      img = document.createElement("img")
      img.id = id
      img.style.position = "absolute"
      img.style.willChange = "transform, width, top, left"
      img.style.userSelect = "none"
      img.draggable = false
      overlay.appendChild(img)
      if (isMine) this.makeAdjustable(img, tile)
    }
    img.src = image_url
    img.alt = keypoint
    img.dataset.keypoint = keypoint
    img.dataset.accessoryId = String(accessory_id ?? "")
    img.dataset.scale = String(calibration?.scale ?? 1.0)
    img.dataset.offsetX = String(calibration?.offset_x ?? 0.0)
    img.dataset.offsetY = String(calibration?.offset_y ?? 0.0)
    img.dataset.rotation = String(calibration?.rotation ?? 0.0)
    img.style.pointerEvents = isMine ? "auto" : "none"
    img.style.cursor = isMine ? "grab" : "default"

    this.pins.set(`${user_id}|${keypoint}`, {image_url, keypoint, user_id})

    // Initial position before the first landmark frame arrives so the
    // image at least appears immediately.
    this.positionPin(img, tile, keypoint)
  },

  // Attach drag-to-move and wheel-to-scale gestures. Called once per
  // accessory image, only on the local user's pins.
  makeAdjustable(img, tile) {
    let dragging = false
    let startX = 0, startY = 0
    let baseOffsetX = 0, baseOffsetY = 0
    let tileRect = null

    const persist = () => {
      const accessoryId = img.dataset.accessoryId
      if (!accessoryId) return
      this.pushEvent("calibrate", {
        accessory_id: accessoryId,
        scale: parseFloat(img.dataset.scale),
        offset_x: parseFloat(img.dataset.offsetX),
        offset_y: parseFloat(img.dataset.offsetY),
        rotation: parseFloat(img.dataset.rotation),
      })
    }

    img.addEventListener("mousedown", e => {
      e.preventDefault()
      dragging = true
      tileRect = tile.getBoundingClientRect()
      startX = e.clientX
      startY = e.clientY
      baseOffsetX = parseFloat(img.dataset.offsetX) || 0
      baseOffsetY = parseFloat(img.dataset.offsetY) || 0
      img.style.cursor = "grabbing"
    })

    window.addEventListener("mousemove", e => {
      if (!dragging) return
      const dx = (e.clientX - startX) / tileRect.width
      const dy = (e.clientY - startY) / tileRect.height
      img.dataset.offsetX = String(baseOffsetX + dx)
      img.dataset.offsetY = String(baseOffsetY + dy)
      this.positionPin(img, tile, img.dataset.keypoint)
    })

    window.addEventListener("mouseup", () => {
      if (!dragging) return
      dragging = false
      img.style.cursor = "grab"
      persist()
    })

    img.addEventListener("wheel", e => {
      e.preventDefault()
      if (e.shiftKey) {
        // Shift+wheel = rotate (5° per tick).
        const step = (e.deltaY < 0 ? -1 : 1) * (5 * Math.PI / 180)
        let rot = (parseFloat(img.dataset.rotation) || 0) + step
        // Wrap to [-π, π] to keep the value sane.
        while (rot >  Math.PI) rot -= 2 * Math.PI
        while (rot < -Math.PI) rot += 2 * Math.PI
        img.dataset.rotation = String(rot)
      } else {
        // Plain wheel = scale (5% per tick).
        const factor = e.deltaY < 0 ? 1.05 : 1 / 1.05
        let scale = (parseFloat(img.dataset.scale) || 1.0) * factor
        scale = Math.max(0.1, Math.min(8.0, scale))
        img.dataset.scale = String(scale)
      }
      this.positionPin(img, tile, img.dataset.keypoint)
      // Debounce persistence so the wheel doesn't fire dozens of saves.
      clearTimeout(this._wheelTimer)
      this._wheelTimer = setTimeout(persist, 250)
    }, {passive: false})

    // Double-click to reset.
    img.addEventListener("dblclick", e => {
      e.preventDefault()
      img.dataset.scale = "1.0"
      img.dataset.offsetX = "0.0"
      img.dataset.offsetY = "0.0"
      img.dataset.rotation = "0.0"
      this.positionPin(img, tile, img.dataset.keypoint)
      persist()
    })
  },

  removePin({user_id, keypoint}) {
    const tile = this.tileForUser(user_id)
    this.pins.delete(`${user_id}|${keypoint}`)
    if (!tile) return
    const overlay = tile.querySelector('[data-role="accessory-overlay"]')
    const img = overlay.querySelector(`#${CSS.escape(`pin-${user_id}-${keypoint}`)}`)
    if (img) img.remove()
  },

  tileForUser(userId) {
    if (Number(userId) === this.userId) return document.getElementById("tile-self")
    return document.querySelector(`#video-tiles [data-user-id="${userId}"]`)
  },

  positionPin(img, tile, keypoint) {
    const face = this.faceLandmarks.get(tile.id)
    const pose = this.poseLandmarks.get(tile.id)

    const calScale    = parseFloat(img.dataset.scale)    || 1.0
    const calX        = parseFloat(img.dataset.offsetX)  || 0.0
    const calY        = parseFloat(img.dataset.offsetY)  || 0.0
    const calRotation = parseFloat(img.dataset.rotation) || 0.0

    const faceCfg = FACE_KEYPOINTS[keypoint]
    if (faceCfg && face) {
      const point = face.points[faceCfg.idx]
      if (point) {
        return applyTransform(img,
          point.x + calX,
          point.y + calY,
          faceCfg.scale * face.faceWidth * calScale,
          faceCfg.anchorY,
          {yaw: face.yaw, pitch: face.pitch, roll: face.roll + calRotation})
      }
    }

    const poseCfg = POSE_KEYPOINTS[keypoint]
    if (poseCfg && pose) {
      const point = poseCfg.fn ? poseCfg.fn(pose.points) : pose.points[poseCfg.idx]
      if (point) {
        return applyTransform(img,
          point.x + calX,
          point.y + calY,
          poseCfg.scale * pose.scale * calScale,
          poseCfg.anchorY,
          {roll: pose.roll + calRotation})
      }
    }

    const fallback = BODY_FALLBACK[keypoint]
    if (fallback) {
      return applyTransform(img,
        fallback.x + calX,
        fallback.y + calY,
        fallback.size * calScale,
        0.5,
        {roll: calRotation})
    }
    applyTransform(img, 0.5 + calX, 0.3 + calY, 0.4 * calScale, 0.5, {roll: calRotation})
  },

  repositionAllOnTile(tileId) {
    const tile = document.getElementById(tileId)
    if (!tile) return
    tile
      .querySelectorAll('[data-role="accessory-overlay"] img[data-keypoint]')
      .forEach(img => this.positionPin(img, tile, img.dataset.keypoint))
  },

  // --- Face + Pose tracking ------------------------------------------

  async ensureMediaPipe() {
    if (this._mediaPipePromise) return this._mediaPipePromise
    this._mediaPipePromise = (async () => {
      // `new Function` hides the URL from esbuild so the dynamic
      // import resolves at runtime in the browser, against the CDN.
      const importESM = new Function("u", "return import(u)")
      const vision = await importESM(`${MEDIAPIPE_BASE}/+esm`)
      const fileset = await vision.FilesetResolver.forVisionTasks(`${MEDIAPIPE_BASE}/wasm`)
      return {vision, fileset}
    })()
    return this._mediaPipePromise
  },

  async ensureFaceLandmarker() {
    if (this._faceLandmarkerPromise) return this._faceLandmarkerPromise
    this._faceLandmarkerPromise = (async () => {
      const {vision, fileset} = await this.ensureMediaPipe()
      const lm = await vision.FaceLandmarker.createFromOptions(fileset, {
        baseOptions: {modelAssetPath: FACE_MODEL_URL, delegate: "GPU"},
        runningMode: "VIDEO",
        numFaces: 1,
        // Returns a 4x4 head-pose matrix per face. We decompose it
        // into Euler angles for pitch/yaw/roll.
        outputFacialTransformationMatrixes: true,
      })
      console.info("[muddle] FaceLandmarker ready")
      this.faceLandmarker = lm
      return lm
    })()
    return this._faceLandmarkerPromise
  },

  async ensurePoseLandmarker() {
    if (this._poseLandmarkerPromise) return this._poseLandmarkerPromise
    this._poseLandmarkerPromise = (async () => {
      const {vision, fileset} = await this.ensureMediaPipe()
      const lm = await vision.PoseLandmarker.createFromOptions(fileset, {
        baseOptions: {modelAssetPath: POSE_MODEL_URL, delegate: "GPU"},
        runningMode: "VIDEO",
        numPoses: 1,
      })
      console.info("[muddle] PoseLandmarker ready")
      this.poseLandmarker = lm
      return lm
    })()
    return this._poseLandmarkerPromise
  },

  async startTracking() {
    this._tracking = true

    // Load both detectors in parallel. Either failing should not break
    // the other.
    const facePromise = this.ensureFaceLandmarker().catch(err => {
      console.error("[muddle] FaceLandmarker load failed", err)
      return null
    })
    const posePromise = this.ensurePoseLandmarker().catch(err => {
      console.error("[muddle] PoseLandmarker load failed", err)
      return null
    })

    const [face, pose] = await Promise.all([facePromise, posePromise])
    if (!face && !pose) return

    const tileId = "tile-self"
    const video = document.querySelector(`#${tileId} video`)
    if (!video) return

    let lastFaceTs = -1
    let lastPoseTs = -1
    const tick = () => {
      if (!this._tracking) return

      if (video.readyState >= 2 && video.videoWidth > 0) {
        const ts = performance.now()

        if (face && ts > lastFaceTs) {
          lastFaceTs = ts
          try {
            const result = face.detectForVideo(video, ts)
            const points = result.faceLandmarks && result.faceLandmarks[0]
            const matrix = result.facialTransformationMatrixes && result.facialTransformationMatrixes[0]
            if (points && points.length > 0) {
              this.faceLandmarks.set(tileId, summarizeFace(points, matrix))
            } else {
              this.faceLandmarks.delete(tileId)
            }
          } catch (err) {
            console.warn("[muddle] face detect failed", err)
          }
        }

        if (pose && ts > lastPoseTs) {
          // Slightly stagger pose timestamps so we don't collide with face's.
          lastPoseTs = ts + 0.5
          try {
            const result = pose.detectForVideo(video, lastPoseTs)
            const points = result.landmarks && result.landmarks[0]
            if (points && points.length > 0) {
              this.poseLandmarks.set(tileId, summarizePose(points))
            } else {
              this.poseLandmarks.delete(tileId)
            }
          } catch (err) {
            console.warn("[muddle] pose detect failed", err)
          }
        }

        this.repositionAllOnTile(tileId)
      }

      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  },

  showError(msg) {
    const tiles = document.getElementById("video-tiles")
    if (!tiles) return
    let el = document.getElementById("tile-error")
    if (!el) {
      el = document.createElement("div")
      el.id = "tile-error"
      el.className = "aspect-video rounded-box bg-error/10 border border-error/30 text-error text-sm flex items-center justify-center p-4 text-center"
      tiles.appendChild(el)
    }
    el.textContent = msg
  },
}

// Compute the bounding-box width and height of the detected face mesh
// in normalized coordinates (0..1 of the video frame). When the face
// transformation matrix is available, decompose it into pitch/yaw/roll
// for full 3D head pose.
function summarizeFace(points, matrix) {
  let minX = 1, maxX = 0, minY = 1, maxY = 0
  for (const p of points) {
    if (p.x < minX) minX = p.x
    if (p.x > maxX) maxX = p.x
    if (p.y < minY) minY = p.y
    if (p.y > maxY) maxY = p.y
  }

  // Roll is sourced from the eye-line angle (verified to track in the
  // correct direction in screen space). Pitch and yaw come from the
  // 3D head-pose matrix when available — these have no good 2D
  // landmark proxy.
  let roll = 0, pitch = 0, yaw = 0
  const eyeA = points[33], eyeB = points[263]
  if (eyeA && eyeB) {
    const left  = eyeA.x < eyeB.x ? eyeA : eyeB
    const right = eyeA.x < eyeB.x ? eyeB : eyeA
    roll = Math.atan2(right.y - left.y, right.x - left.x)
  }

  if (matrix && matrix.data) {
    const e = decomposeYXZ(matrix.data)
    pitch = e.pitch
    yaw   = e.yaw
    // Intentionally not taking roll from the matrix — its sign in
    // MediaPipe's face-model frame doesn't match the eye-line
    // convention used in screen space.
  }

  return {
    points,
    pitch,
    yaw,
    roll,
    faceWidth: Math.max(0.001, maxX - minX),
    faceHeight: Math.max(0.001, maxY - minY),
  }
}

// MediaPipe returns a 4×4 column-major matrix. The top-left 3×3 is the
// rotation; we decompose it as YXZ Euler angles so the resulting
// `rotateY(yaw) rotateX(pitch) rotateZ(roll)` CSS chain reconstructs
// the same orientation. Coordinate system is +X right, +Y up, +Z out
// of the screen.
function decomposeYXZ(d) {
  // Column-major access: element at row r, col c is d[c * 4 + r].
  const m11 = d[0],  m12 = d[4],  m13 = d[8]
  const m21 = d[1],  m22 = d[5],  m23 = d[9]
  const m31 = d[2],  m32 = d[6],  m33 = d[10]

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
  const pitch = Math.asin(-clamp(m23, -1, 1))

  let yaw, roll
  if (Math.abs(m23) < 0.9999999) {
    yaw  = Math.atan2(m13, m33)
    roll = Math.atan2(m21, m22)
  } else {
    yaw  = Math.atan2(-m31, m11)
    roll = 0
  }
  return {pitch, yaw, roll}
}

// Pose landmarks are in normalized 0..1 coords too. We use shoulder
// width as the reference scale so accessory sizes stay sane regardless
// of how far the subject is from the camera, and the shoulder line for
// torso roll.
function summarizePose(points) {
  const a = points[11], b = points[12]
  let scale = 0.4
  let roll = 0
  if (a && b) {
    const dx = b.x - a.x
    const dy = b.y - a.y
    scale = Math.max(0.05, Math.hypot(dx, dy))
    // Pick screen-left and screen-right shoulders by x to stay
    // orientation-agnostic, same convention as the face roll.
    const left  = a.x < b.x ? a : b
    const right = a.x < b.x ? b : a
    roll = Math.atan2(right.y - left.y, right.x - left.x)
  }
  return {points, scale, roll}
}

function midpoint(a, b) {
  if (!a || !b) return null
  return {x: (a.x + b.x) / 2, y: (a.y + b.y) / 2}
}

function centroid(pts) {
  const valid = pts.filter(Boolean)
  if (valid.length === 0) return null
  const x = valid.reduce((s, p) => s + p.x, 0) / valid.length
  const y = valid.reduce((s, p) => s + p.y, 0) / valid.length
  return {x, y}
}

function applyTransform(img, x, y, widthFraction, anchorY, rot = {}) {
  img.style.left = `${x * 100}%`
  img.style.top  = `${y * 100}%`
  img.style.width = `${widthFraction * 100}%`
  img.style.height = "auto"
  // Pivot rotations around the anchor point (e.g. bottom-center of a
  // hat for `anchorY=1.0`) so rotating doesn't drift the anchor off
  // the head. Then translate so the anchor sits at the keypoint.
  const radToDeg = r => (r || 0) * 180 / Math.PI
  const yaw   = radToDeg(rot.yaw)
  const pitch = radToDeg(rot.pitch)
  const roll  = radToDeg(rot.roll)
  img.style.transformOrigin = `50% ${anchorY * 100}%`
  img.style.transform =
    `translate(-50%, -${anchorY * 100}%) ` +
    `rotateY(${yaw}deg) rotateX(${pitch}deg) rotateZ(${roll}deg)`
}

export default Call
