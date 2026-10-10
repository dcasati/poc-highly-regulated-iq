import React from "react";
import {AbsoluteFill, useCurrentFrame} from "remotion";
import scene from "./scene.json";
import {beatAt, motionAt, pointOnPath} from "./animation-utils.js";

export function PrivateNetwork() {
  const frame = useCurrentFrame();
  const beat = beatAt(frame);
  const motion = beat ? motionAt(frame, beat) : null;
  const route = motion ? scene.routes[motion.route] : null;
  const packet = route ? pointOnPath(route.points, motion.progress) : null;
  return <AbsoluteFill style={{backgroundColor: "white"}}>
    <div style={{width: "100%", height: "100%"}} dangerouslySetInnerHTML={{
      __html: scene.svg.replace('width="1800" height="2060"', 'width="100%" height="100%"'),
    }}/>
    <svg viewBox={`0 0 ${scene.width} ${scene.height}`} style={{position: "absolute", inset: 0, width: "100%", height: "100%"}}>
      {route && <>
        <polyline points={route.points.map((p) => p.join(",")).join(" ")}
          fill="none" stroke={route.color} strokeWidth="7" strokeLinejoin="round" opacity="0.7"/>
        <circle cx={packet[0]} cy={packet[1]} r="10" fill={route.color} stroke="white" strokeWidth="3"/>
      </>}
      <rect x="26" y="1851" width="1748" height="120" rx="15" fill="white"/>
      <text x="55" y="1890" fontFamily="Helvetica, Arial, sans-serif" fontSize="29" fontWeight="700" fill="black">
        {beat?.title ?? "Pause / reset · Private network, distinct identity and outbound paths"}
      </text>
      <text x="55" y="1928" fontFamily="Helvetica, Arial, sans-serif" fontSize="23" fill="black">
        {beat?.detail ?? "Synthetic PoC; not a certification, readiness dashboard or guarantee of perfect injection prevention."}
      </text>
      <text x="55" y="1957" fontFamily="Helvetica, Arial, sans-serif" fontSize="21" fill="black">
        {beat ? `Moving packet: ${beat.packet} · solid HTTPS / transport · dashed DNS · amber supporting path` :
          "Loop resumes after a three-second pause. No customer documents or identifiers are embedded."}
      </text>
    </svg>
  </AbsoluteFill>;
}
