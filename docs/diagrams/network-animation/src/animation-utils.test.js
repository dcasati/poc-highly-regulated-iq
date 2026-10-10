import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {beatAt, motionAt, pointOnPath} from "./animation-utils.js";
import {BEATS, DURATION_IN_FRAMES, FPS, PAUSE_SECONDS} from "./timeline-data.js";

const scene = JSON.parse(readFileSync(new URL("./scene.json", import.meta.url)));
test("all stages are contiguous; reset holds for three seconds", () => {
  let time = 0;
  for (const beat of BEATS) {
    assert.equal(beat.start, time);
    time += beat.duration;
    assert.ok(beat.legs.every(([key]) => scene.routes[key]));
  }
  assert.equal(time + PAUSE_SECONDS, DURATION_IN_FRAMES / FPS);
  assert.equal(beatAt(DURATION_IN_FRAMES - 1), null);
});
test("pure frame interpolation stays on valid routes and honors response direction", () => {
  for (let frame = 0; frame < DURATION_IN_FRAMES; frame++) {
    const beat = beatAt(frame);
    if (!beat) continue;
    const motion = motionAt(frame, beat);
    assert.ok(motion.progress >= 0 && motion.progress <= 1);
    const points = scene.routes[motion.route].points;
    assert.ok(pointOnPath(points, motion.progress).every(Number.isFinite));
    assert.deepEqual(pointOnPath(points, 0), points[0]);
    assert.deepEqual(pointOnPath(points, 1), points.at(-1));
  }
  assert.equal(motionAt(12 * FPS + 2 * FPS, BEATS[3]).progress, 1);
});
