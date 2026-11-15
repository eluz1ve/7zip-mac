import React from 'react';
import {Composition} from 'remotion';
import {Demo} from './Demo';
import {en, ru, FPS, totalFrames} from './scenes';

export const Root: React.FC = () => (
  <>
    <Composition id="Demo-en" component={Demo} defaultProps={{script: en}}
      durationInFrames={totalFrames(en)} fps={FPS} width={1920} height={1080} />
    <Composition id="Demo-ru" component={Demo} defaultProps={{script: ru}}
      durationInFrames={totalFrames(ru)} fps={FPS} width={1920} height={1080} />
  </>
);
