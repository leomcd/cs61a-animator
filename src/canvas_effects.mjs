const NEON_CORE = "#ffffff";
const PARTICLE_INTERVAL = 1;
export const PARTICLE_LIFETIME = 6;

export function makeKaleidoscopeCopies(sectors, mirror, staggerMs, neon) {
  const copiesPerSector = mirror ? 2 : 1;
  const count = sectors * copiesPerSector;
  return Array.from({ length: count }, (_, index) => {
    const angle = Math.floor(index / copiesPerSector) * 2 * Math.PI / sectors;
    const hue = (190 + index * 360 / count) % 360;
    return {
      color: `hsl(${hue} ${neon ? "100% 58%" : "86% 73%"})`,
      cos: Math.cos(angle),
      sin: Math.sin(angle),
      mirror: mirror && index % 2 !== 0 ? -1 : 1,
      delay: index * staggerMs / 100,
    };
  });
}

// A circle of this radius fits even when a drawing reaches into the corners.
export function kaleidoscopeScale(paths) {
  let radius = 455;
  for (const { pts } of paths) {
    for (let i = 0; i < pts.length; i += 2) {
      radius = Math.max(radius, Math.hypot(pts[i], pts[i + 1]));
    }
  }
  return 455 / radius;
}

export function pathProgress(path, time) {
  const duration = path.end - path.start;
  if (duration <= 0) return time >= path.start ? 1 : 0;
  return Math.max(0, Math.min(1, (time - path.start) / duration));
}

function pointAt(pts, position) {
  const last = pts.length / 2 - 1;
  const index = Math.min(last - 1, Math.floor(position));
  const fraction = position - index;
  const x = pts[2 * index];
  const y = pts[2 * index + 1];
  return [
    x + (pts[2 * index + 2] - x) * fraction,
    y + (pts[2 * index + 3] - y) * fraction,
  ];
}

// Trace the requested interval of a polyline, including partial end segments.
export function strokePath(ctx, path, color, from, to, width = path.thickness, opacity = 1) {
  const { pts } = path;
  if (pts.length < 4) return;
  const segments = pts.length / 2 - 1;
  const first = from * segments;
  const last = to * segments;
  const lastVertex = Math.floor(last);
  ctx.beginPath();
  if (first === 0) ctx.moveTo(pts[0], pts[1]);
  else ctx.moveTo(...pointAt(pts, first));
  for (let vertex = Math.floor(first) + 1; vertex <= lastVertex; vertex++) {
    ctx.lineTo(pts[2 * vertex], pts[2 * vertex + 1]);
  }
  if (last > lastVertex) ctx.lineTo(...pointAt(pts, last));
  ctx.globalAlpha = opacity;
  ctx.lineWidth = width;
  ctx.strokeStyle = color;
  ctx.stroke();
}

export function drawComet(ctx, path, color, time, length, detailed) {
  if (path.pts.length < 4 || time >= path.finish + length) return;
  const from = pathProgress(path, time - length);
  const to = pathProgress(path, time);
  const width = Math.max(2, path.thickness);
  const fade = 1 - Math.max(0, time - path.finish) / length;
  if (!detailed) {
    if (from < to) strokePath(ctx, path, color, from, to, width + 1, fade * .95);
    return;
  }

  const slices = 6;
  const duration = Math.max(0, path.end - path.start);
  for (let i = 0; from < to && i < slices; i++) {
    const start = from + (to - from) * i / slices;
    const end = from + (to - from) * (i + 1) / slices;
    const sampleTime = path.start + (start + end) / 2 * duration;
    const glow = Math.max(0, 1 - (time - sampleTime) / length);
    const brightness = glow * (1.65 - .65 * glow);
    strokePath(ctx, path, color, start, end, width + 4, brightness * .24);
    strokePath(ctx, path, color, start, end, width + 1.5, brightness);
    strokePath(ctx, path, NEON_CORE, start, end, Math.max(1, width * .55), brightness * .96);
  }

  const [x, y] = pointAt(path.pts, to * (path.pts.length / 2 - 1));
  dot(ctx, x, y, width * .6 + 3, color, fade * .24);
  dot(ctx, x, y, width * .6 + 1.25, color, fade);
  dot(ctx, x, y, width * .35 + .7, NEON_CORE, fade);
}

function dot(ctx, x, y, radius, color, opacity) {
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.globalAlpha = opacity;
  ctx.fillStyle = color;
  ctx.fill();
}

// A fixed hash makes each drop return to the same spot when time is rewound.
function particleSeed(pathIndex, emission) {
  const bits = Math.imul(pathIndex + 1, 0x9e3779b1) ^ Math.imul(emission + 1, 0x85ebca6b);
  return Math.imul(bits ^ (bits >>> 16), 0x45d9f3b) >>> 0;
}

export function drawParticles(ctx, path, pathIndex, color, time) {
  if (path.pts.length < 4 || time >= path.finish + PARTICLE_LIFETIME) return;
  const latest = Math.floor((Math.min(time, path.finish) - path.start) / PARTICLE_INTERVAL);
  if (!Number.isFinite(latest)) return;
  const slots = Math.ceil(PARTICLE_LIFETIME / PARTICLE_INTERVAL);
  for (let offset = 0; offset < slots && offset <= latest; offset++) {
    const emission = latest - offset;
    const emittedAt = path.start + emission * PARTICLE_INTERVAL;
    const age = time - emittedAt;
    if (age < 0 || age >= PARTICLE_LIFETIME) continue;
    const u = pathProgress(path, emittedAt);
    const [x, y] = pointAt(path.pts, u * (path.pts.length / 2 - 1));
    const seed = particleSeed(pathIndex, emission);
    const angle = (seed & 1023) / 1024 * Math.PI * 2;
    const speed = 65 + ((seed >>> 10) & 127);
    const seconds = age / 10;
    const dropX = x + Math.cos(angle) * speed * seconds;
    const dropY = y + Math.sin(angle) * speed * seconds + 150 * seconds ** 2;
    const size = 1.6 + ((seed >>> 18) & 7) * .36;
    const shrink = Math.min(1, 2 * (1 - age / PARTICLE_LIFETIME));
    dot(ctx, dropX, dropY, size * shrink, color, 1);
  }
}
