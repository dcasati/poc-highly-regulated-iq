import {Easing, interpolate} from "remotion";
import {BEATS, FPS} from "./timeline-data.js";

export function beatAt(frame) {
  const time = frame / FPS;
  return BEATS.find((beat) => time >= beat.start && time < beat.start + beat.duration) ?? null;
}

export function motionAt(frame, beat) {
  const local = frame / FPS - beat.start;
  const slot = beat.duration / beat.legs.length;
  const index = Math.min(beat.legs.length - 1, Math.floor(local / slot));
  const progress = interpolate(local - index * slot, [0, slot * 0.72], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.ease),
  });
  const [route, direction] = beat.legs[index];
  return {route, progress: direction === 1 ? progress : 1 - progress};
}

export function pointOnPath(points, progress) {
  const lengths = points.slice(1).map((p, i) => Math.hypot(p[0] - points[i][0], p[1] - points[i][1]));
  let remaining = progress * lengths.reduce((sum, n) => sum + n, 0);
  for (let i = 0; i < lengths.length; i++) {
    if (remaining <= lengths[i] || i === lengths.length - 1) {
      const ratio = Math.max(0, Math.min(1, remaining / lengths[i]));
      return [points[i][0] + (points[i + 1][0] - points[i][0]) * ratio,
        points[i][1] + (points[i + 1][1] - points[i][1]) * ratio];
    }
    remaining -= lengths[i];
  }
  return points[points.length - 1];
}
