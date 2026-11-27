// The canvas animation loop. The renderer is kept out of Lustre's virtual DOM:
// Gleam computes the full curve of every path once (whenever the code or
// `shape_slider` changes) and pushes it here via `setDrawing`. A single
// requestAnimationFrame loop owns the clock and, each frame, reveals a growing
// prefix of the precomputed points straight to the 2D context. So per frame
// there is no geometry work and no vdom diffing — just canvas strokes — which
// is what lets many paths animate at high frames per second.
//
// Values cross the Gleam/JS boundary directly — no JSON: a Gleam record arrives
// as an object with named fields, and a Gleam list is iterable.

import {
  drawComet,
  drawParticles,
  kaleidoscopeScale,
  makeKaleidoscopeCopies,
  PARTICLE_LIFETIME,
  pathProgress,
  strokePath,
} from "./canvas_effects.mjs";

let canvas = null;
let ctx = null;
let drawing = null;
let effects = { kaleidoscope: false, neon: false, particles: false };
let rate = 1; // a multiple of normal speed; negative plays the drawing backward
let looping = false;
let clock = 0; // the drawing's time, in tenths of a second, in [0, endClock]
let lastTs = 0;
let lastPaintedClock = null;
let running = false;
let framesWithoutCanvas = 0;
let onPlaybackChange = null;
let lastPlaybackState = null;

const TENTHS_PER_SECOND = 10;
const NEON_BLUE = "#00e5ff";
const MAX_DETAILED_PATHS = 960;
// How many frames (about 10 seconds' worth) to wait for the canvas to appear
// before reporting that it hasn't.
const MAX_FRAMES_WITHOUT_CANVAS = 600;

// Replace the drawing being animated. `pathList` is the List(RenderPath) built
// by render.gleam; each path's points are packed into a flat Float64Array so
// the per-frame draw loop touches only contiguous numbers.
export function setDrawing(pathList) {
  const paths = [];
  let lastFinish = -Infinity;
  for (const p of pathList) {
    const flat = [];
    for (const q of p.points) flat.push(q.x, q.y);
    const finish = Math.max(p.start, p.end);
    lastFinish = Math.max(lastFinish, finish);
    paths.push({
      pts: new Float64Array(flat),
      thickness: p.thickness,
      color: p.color,
      start: p.start,
      end: p.end,
      finish,
    });
  }
  // Keep the current clock across drawing swaps: dragging the shape slider on an
  // already-finished drawing shows the new shape complete, rather than restarting.
  drawing = { paths, lastFinish, scale: null };
  updateDrawingEffects();
  if (!running) {
    running = true;
    lastTs = performance.now();
    requestAnimationFrame(frame);
  }
}

export function setVisualEffects(settings) {
  effects = settings;
  if (drawing) updateDrawingEffects();
}

function updateDrawingEffects() {
  lastPaintedClock = null;
  drawing.copies = effects.kaleidoscope
    ? makeKaleidoscopeCopies(effects.sectors, effects.mirror, effects.stagger_ms, effects.neon)
    : [];
  const delay = drawing.copies.at(-1)?.delay ?? 0;
  const fade = Math.max(effects.neon ? effects.trail_length : 0,
    effects.particles ? PARTICLE_LIFETIME : 0);
  // Empty drawings keep the clock running. Otherwise give the final copy and
  // its glow or particles time to finish before holding at the end.
  drawing.endClock = drawing.paths.length === 0
    ? Infinity : Math.max(0, drawing.lastFinish + delay + fade);
  if (effects.kaleidoscope && drawing.scale === null) {
    drawing.scale = kaleidoscopeScale(drawing.paths);
  }
  const copies = Math.max(1, drawing.copies.length);
  drawing.detailStride = Math.max(1, Math.ceil(drawing.paths.length * copies / MAX_DETAILED_PATHS));
  clock = Math.min(clock, drawing.endClock);
  reportPlayback();
}

export function setSpeed(r) {
  rate = r;
  reportPlayback();
}

export function setLooping(enabled) {
  looping = enabled;
  reportPlayback();
}

function canLoop() {
  return looping && Number.isFinite(drawing.endClock) && drawing.endClock > 0;
}

export function startPlayback(r, restart) {
  const end = drawing?.endClock ?? 0;
  const reachedLimit = r < 0 ? clock <= 0 : clock >= end;
  if (restart || reachedLimit) {
    clock = r < 0 && Number.isFinite(end) ? end : 0;
  }
  setSpeed(r);
}

export function watchPlayback(onChange) {
  onPlaybackChange = onChange;
  lastPlaybackState = null;
  reportPlayback();
}

function reportPlayback() {
  if (!onPlaybackChange || !drawing) return;
  const playing = rate !== 0 && (canLoop()
    || (rate > 0 ? clock < drawing.endClock : clock > 0));
  if (playing !== lastPlaybackState) {
    lastPlaybackState = playing;
    onPlaybackChange(playing);
  }
}

// Jump the animation back to the start (empty canvas).
export function resetClock() {
  clock = 0;
}

function frame(ts) {
  // Cap dt so a backgrounded/paused tab can't jump the clock far ahead.
  const dt = Math.min((ts - lastTs) / 1000, 0.1);
  lastTs = ts;
  const next = clock + dt * rate * TENTHS_PER_SECOND;
  const end = drawing.endClock;
  if (canLoop() && (next < 0 || next > end)) {
    const remainder = next % end;
    clock = remainder < 0 ? remainder + end : remainder;
  } else {
    clock = clamp(next, 0, end);
  }
  render();
  reportPlayback();
  requestAnimationFrame(frame);
}

// Match the backing store to the element's CSS size (× device pixel ratio) so
// the drawing stays crisp; only touched when the size actually changes.
function ensureSize() {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.round(canvas.clientWidth * dpr);
  const h = Math.round(canvas.clientHeight * dpr);
  if (w > 0 && h > 0 && (canvas.width !== w || canvas.height !== h)) {
    canvas.width = w;
    canvas.height = h;
    lastPaintedClock = null;
  }
}

// Find the page's canvas, which Lustre can add to the page after the first drawing
// arrives. Returns whether it is there.
function findCanvas() {
  const el = document.getElementById("animation-canvas");
  if (!el) {
    framesWithoutCanvas += 1;
    if (framesWithoutCanvas === MAX_FRAMES_WITHOUT_CANVAS) {
      console.error('The page has no <canvas id="animation-canvas"> element to draw on.');
    }
    return false;
  }
  if (el !== canvas) {
    canvas = el;
    ctx = canvas.getContext("2d");
    canvas.addEventListener("contextrestored", invalidateCanvas);
    lastPaintedClock = null;
  }
  return true;
}

function invalidateCanvas() {
  lastPaintedClock = null;
}

function render() {
  if (!findCanvas()) return;
  ensureSize();
  if (clock === lastPaintedClock) return;
  lastPaintedClock = clock;
  const w = canvas.width;
  const h = canvas.height;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, w, h);
  // Draw functions work in a 0..1000 world centred on the origin: scale it to
  // fill the canvas and translate (0, 0) to the middle, so positive coordinates
  // run toward the bottom-right corner.
  ctx.setTransform(w / 1000, 0, 0, h / 1000, w / 2, h / 2);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  drawCopies(drawInk);
  if (effects.particles) drawCopies(drawSplatter);
}

function drawCopies(paint) {
  if (drawing.copies.length === 0) {
    paint(clock, null);
    return;
  }

  for (const { color, cos, sin, mirror, delay } of drawing.copies) {
    const scale = drawing.scale;
    ctx.save();
    ctx.transform(cos * scale, sin * scale, -sin * scale * mirror, cos * scale * mirror, 0, 0);
    paint(clock - delay, color);
    ctx.restore();
  }
}

function drawInk(time, copyColor) {
  for (let i = 0; i < drawing.paths.length; i++) {
    const path = drawing.paths[i];
    if (time < path.start) continue;
    const color = emitterColor(path, copyColor);
    if (!effects.neon || effects.keep_ink) {
      const opacity = effects.neon ? .42 : 1;
      strokePath(ctx, path, color, 0, pathProgress(path, time), path.thickness, opacity);
    }
    if (effects.neon) {
      const detailed = i % drawing.detailStride === 0;
      drawComet(ctx, path, color, time, effects.trail_length, detailed);
    }
  }
}

// Paint ink droplets over the neon so the glow cannot wash out their edges.
function drawSplatter(time, copyColor) {
  for (let i = 0; i < drawing.paths.length; i += drawing.detailStride) {
    const path = drawing.paths[i];
    if (time >= path.start) drawParticles(ctx, path, i, emitterColor(path, copyColor), time);
  }
}

function emitterColor(path, copyColor) {
  return copyColor ?? (effects.neon ? NEON_BLUE : path.color);
}

function clamp(x, lo, hi) {
  return x < lo ? lo : x > hi ? hi : x;
}

