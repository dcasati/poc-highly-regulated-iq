import React from "react";
import {Composition} from "remotion";
import {PrivateNetwork} from "./PrivateNetwork.jsx";
import {DURATION_IN_FRAMES, FPS, HEIGHT, WIDTH} from "./timeline-data.js";

export const Root = () => <Composition id="PrivateNetwork" component={PrivateNetwork}
  durationInFrames={DURATION_IN_FRAMES} fps={FPS} width={WIDTH} height={HEIGHT}/>;
