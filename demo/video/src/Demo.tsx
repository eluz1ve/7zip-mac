import React from 'react';
import {
  AbsoluteFill, Easing, Img, Sequence, interpolate, spring, staticFile,
  useCurrentFrame, useVideoConfig,
} from 'remotion';
import tlEn from '../public/en/timeline.json';
import tlRu1 from '../public/ru1/timeline.json';
import tlRu2 from '../public/ru2/timeline.json';
import tlRu3 from '../public/ru3/timeline.json';
import {
  CUT_FADE, FPS, INTRO, OUTRO, OVERLAP, Rect, Scene, Script, sceneFrames, sceneStarts, segmentsOf, totalFrames,
} from './scenes';

type Timeline = {
  width: number; height: number; scale: number; offsetX: number; offsetY: number;
  frames: {file: string; t: number}[];
};
const timelines: Record<Scene['src'], Timeline> = {en: tlEn, ru1: tlRu1, ru2: tlRu2, ru3: tlRu3};

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif';
const W = 1920, H = 1080;
// Где на холсте живёт «экран»: оставляем снизу место под подписи.
const AREA = {cx: 960, cy: 455, w: 1640, h: 760};
const MAX_ZOOM = 2.1;
const STRIP = 150; // полоса Stage Manager слева — в кадр не берём

const ease = Easing.bezier(0.45, 0, 0.2, 1);

// ---------- фон ----------

const Background: React.FC = () => {
  const f = useCurrentFrame();
  const a = f / 90;
  return (
    <AbsoluteFill style={{background: '#070a14'}}>
      <AbsoluteFill style={{
        background: `radial-gradient(900px 700px at ${30 + 8 * Math.sin(a)}% ${25 + 6 * Math.cos(a * 0.8)}%, rgba(56,110,255,0.32), transparent 70%),
                     radial-gradient(800px 650px at ${75 + 7 * Math.cos(a * 0.7)}% ${70 + 6 * Math.sin(a * 0.9)}%, rgba(140,80,255,0.26), transparent 70%),
                     radial-gradient(1200px 500px at 50% 115%, rgba(20,190,220,0.12), transparent 70%)`,
      }} />
      <AbsoluteFill style={{
        backgroundImage: 'linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)',
        backgroundSize: '64px 64px',
        maskImage: 'radial-gradient(ellipse at center, black 30%, transparent 80%)',
        WebkitMaskImage: 'radial-gradient(ellipse at center, black 30%, transparent 80%)',
      }} />
      <AbsoluteFill style={{background: 'radial-gradient(ellipse at center, transparent 55%, rgba(0,0,0,0.55) 100%)'}} />
    </AbsoluteFill>
  );
};

// ---------- запись экрана с камерой ----------

const frameAt = (tl: Timeline, t: number) => {
  let lo = 0, hi = tl.frames.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (tl.frames[mid].t <= t) lo = mid; else hi = mid - 1;
  }
  return tl.frames[lo];
};

const camAt = (keys: [number, Rect][], t: number): Rect => {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [t0, r0] = keys[i], [t1, r1] = keys[i + 1];
    if (t <= t1) {
      const p = ease((t - t0) / Math.max(0.001, t1 - t0));
      return r0.map((v, k) => v + (r1[k] - v) * p) as Rect;
    }
  }
  return keys[keys.length - 1][1];
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Один «снимок» записи на момент t с камерой, смотрящей туда, куда нужно в этот момент. */
const Layer: React.FC<{scene: Scene; t: number; push: number; opacity: number}> = ({scene, t, push, opacity}) => {
  const tl = timelines[scene.src];
  const frame = frameAt(tl, t);
  const [x, y, w, h] = camAt(scene.cam, t);
  const pad = 36;
  const zoom = Math.min(AREA.w / (w + pad * 2), AREA.h / (h + pad * 2), MAX_ZOOM) * push;
  const tx = AREA.cx - (x + w / 2) * zoom;
  const ty = AREA.cy - (y + h / 2) * zoom;
  const imgW = tl.width / tl.scale, imgH = tl.height / tl.scale;
  const patch = scene.patch;
  const ptl = patch ? timelines[patch.src] : null;
  return (
    <AbsoluteFill style={{opacity}}>
      <div style={{
        position: 'absolute', left: 0, top: 0, width: 1512, height: 982,
        transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${zoom})`,
        filter: 'drop-shadow(0 18px 34px rgba(0,0,0,0.5))',
      }}>
        <div style={{position: 'absolute', left: STRIP, top: 0, width: 1512 - STRIP, height: 982, overflow: 'hidden'}}>
          <Img src={staticFile(`${scene.src}/${frame.file}`)} style={{
            position: 'absolute', left: tl.offsetX - STRIP, top: tl.offsetY, width: imgW, height: imgH,
          }} />
        </div>
        {patch && ptl && (
          <div style={{position: 'absolute', left: patch.rect[0], top: patch.rect[1], width: patch.rect[2], height: patch.rect[3], overflow: 'hidden'}}>
            <Img src={staticFile(`${patch.src}/${patch.file}`)} style={{
              position: 'absolute', left: ptl.offsetX - patch.rect[0], top: ptl.offsetY - patch.rect[1],
              width: ptl.width / ptl.scale, height: ptl.height / ptl.scale,
            }} />
          </div>
        )}
      </div>
    </AbsoluteFill>
  );
};

const Shot: React.FC<{scene: Scene; frames: number}> = ({scene, frames}) => {
  const f = useCurrentFrame();
  const speed = scene.speed ?? 1;
  const tau = (f / FPS) * speed; // секунды записи от начала сцены, без вырезанных кусков
  const segments = segmentsOf(scene);

  // Где в сцене стыки вырезанных кусков.
  const joins: number[] = [];
  let acc = 0;
  for (const [a, b] of segments) { acc += b - a; joins.push(acc); }
  joins.pop();

  const mapIn = (i: number) => {
    const start = i === 0 ? 0 : joins[i - 1];
    const [a, b] = segments[i];
    return Math.min(b, Math.max(a, a + tau - start));
  };
  let seg = joins.findIndex((j) => tau < j);
  if (seg < 0) seg = segments.length - 1;

  const push = 1 + 0.035 * (f / frames); // лёгкий наезд через всю сцену
  const half = (CUT_FADE / 2 / FPS) * speed;
  let layers: {t: number; opacity: number}[] = [{t: mapIn(seg), opacity: 1}];
  for (let i = 0; i < joins.length; i++) {
    const d = tau - joins[i];
    if (Math.abs(d) < half) {
      const p = Easing.inOut(Easing.ease)((d + half) / (2 * half));
      layers = [{t: mapIn(i), opacity: 1 - p}, {t: mapIn(i + 1), opacity: p}];
    }
  }

  const fadeIn = interpolate(f, [0, OVERLAP], [0, 1], clamp);
  const fadeOut = interpolate(f, [frames - OVERLAP, frames], [1, 0], clamp);
  const scale = 1.03 - 0.03 * Easing.out(Easing.cubic)(fadeIn) - 0.02 * Easing.in(Easing.cubic)(1 - fadeOut);
  return (
    <AbsoluteFill style={{opacity: Math.min(fadeIn, fadeOut), transform: `scale(${scale})`}}>
      {layers.map((l, i) => <Layer key={i} scene={scene} t={l.t} push={push} opacity={l.opacity} />)}
    </AbsoluteFill>
  );
};

// ---------- подписи ----------

// Подпись сцены. Старая успевает уйти до того, как появится новая, — они не накладываются.
const Caption: React.FC<{title: string; sub: string; index: number; frames: number}> =
  ({title, sub, index, frames}) => {
    const f = useCurrentFrame();
    const {fps} = useVideoConfig();
    const enter = spring({frame: f - OVERLAP + 2, fps, config: {damping: 200}, durationInFrames: 18});
    const exit = Easing.in(Easing.cubic)(interpolate(f, [frames - OVERLAP - 8, frames - OVERLAP + 1], [0, 1], clamp));
    const o = enter * (1 - exit);
    return (
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 84, display: 'flex', flexDirection: 'column',
        alignItems: 'center', fontFamily: FONT, opacity: o, transform: `translateY(${(1 - enter) * 22 + exit * 12}px)`,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 18, padding: '14px 30px 14px 16px', borderRadius: 22,
          background: 'rgba(14,18,32,0.62)', border: '1px solid rgba(255,255,255,0.10)',
          boxShadow: '0 20px 50px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.06)',
          backdropFilter: 'blur(18px)',
        }}>
          <div style={{
            width: 54, height: 54, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)', color: 'white', fontWeight: 700, fontSize: 22,
            letterSpacing: 0.5, boxShadow: '0 6px 18px rgba(80,100,255,0.45)',
          }}>{String(index + 1).padStart(2, '0')}</div>
          <div style={{display: 'flex', flexDirection: 'column', gap: 4}}>
            <div style={{color: 'white', fontSize: 38, fontWeight: 700, letterSpacing: -0.5}}>{title}</div>
            <div style={{color: 'rgba(214,222,255,0.72)', fontSize: 23, fontWeight: 500}}>{sub}</div>
          </div>
        </div>
      </div>
    );
  };

// Индикатор шагов: один на всё видео, активная точка плавно растягивается на следующую.
const Steps: React.FC<{script: Script}> = ({script}) => {
  const f = useCurrentFrame();
  const starts = sceneStarts(script);
  const count = script.scenes.length;
  const end = totalFrames(script) - OUTRO;
  const visible = interpolate(f, [INTRO - OVERLAP, INTRO], [0, 1], clamp) * interpolate(f, [end - 6, end + 6], [1, 0], clamp);
  // Непрерывная «позиция» 0..count-1: переход между шагами — в момент смены сцен.
  let pos = 0;
  starts.forEach((s, i) => {
    if (i > 0) pos += Easing.inOut(Easing.cubic)(interpolate(f, [s - 2, s + OVERLAP + 2], [0, 1], clamp));
  });
  const DOT = 8, GAP = 10, ACTIVE = 34;
  return (
    <div style={{position: 'absolute', left: 0, right: 0, bottom: 52, display: 'flex', justifyContent: 'center', opacity: visible}}>
      <div style={{display: 'flex', gap: GAP, alignItems: 'center'}}>
        {Array.from({length: count}, (_, i) => {
          const k = Math.max(0, 1 - Math.abs(pos - i)); // насколько точка «активна»
          return (
            <div key={i} style={{
              width: DOT + (ACTIVE - DOT) * k, height: DOT, borderRadius: DOT / 2,
              background: `linear-gradient(90deg, rgba(96,165,250,${0.22 + 0.78 * k}), rgba(167,139,250,${0.22 + 0.78 * k}))`,
            }} />
          );
        })}
      </div>
    </div>
  );
};

// ---------- заставка и финал ----------

const Title: React.FC<{title: string; line: string; badge?: string; frames: number; mono?: boolean}> =
  ({title, line, badge, frames, mono}) => {
    const f = useCurrentFrame();
    const {fps} = useVideoConfig();
    const icon = spring({frame: f, fps, config: {damping: 12, stiffness: 90, mass: 0.8}});
    const text = spring({frame: f - 10, fps, config: {damping: 200}});
    const sub = spring({frame: f - 18, fps, config: {damping: 200}});
    const out = interpolate(f, [frames - OVERLAP, frames], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
    return (
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily: FONT, opacity: out,
        filter: out < 1 ? `blur(${(1 - out) * 12}px)` : undefined}}>
        <div style={{position: 'relative', width: 230, height: 230, transform: `scale(${0.6 + 0.4 * icon}) rotate(${(1 - icon) * -12}deg)`, opacity: Math.min(1, icon * 1.5)}}>
          <div style={{position: 'absolute', inset: -60, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(96,140,255,0.45), transparent 65%)'}} />
          <Img src={staticFile('icon.png')} style={{position: 'absolute', inset: 0, width: 230, height: 230,
            filter: 'drop-shadow(0 24px 40px rgba(0,0,0,0.55))'}} />
        </div>
        <div style={{marginTop: 46, color: 'white', fontSize: mono ? 58 : 92, fontWeight: 800, letterSpacing: mono ? -0.5 : -2.5,
          opacity: text, transform: `translateY(${(1 - text) * 24}px)`,
          background: 'linear-gradient(180deg, #ffffff, #c9d4ff)', WebkitBackgroundClip: 'text', color: 'transparent'} as React.CSSProperties}>
          {title}
        </div>
        <div style={{marginTop: 14, color: 'rgba(214,222,255,0.78)', fontSize: 34, fontWeight: 500,
          opacity: sub, transform: `translateY(${(1 - sub) * 18}px)`}}>{line}</div>
        {badge && (
          <div style={{marginTop: 30, padding: '9px 20px', borderRadius: 999, fontSize: 21, fontWeight: 600,
            color: 'rgba(200,212,255,0.9)', border: '1px solid rgba(160,180,255,0.28)', background: 'rgba(80,100,200,0.14)',
            opacity: sub}}>{badge}</div>
        )}
      </AbsoluteFill>
    );
  };

// ---------- монтаж ----------

export const Demo: React.FC<{script: Script}> = ({script}) => {
  const starts = sceneStarts(script);
  const items = script.scenes.map((scene, i) => {
    const frames = sceneFrames(scene);
    return (
      <Sequence key={i} from={starts[i]} durationInFrames={frames}>
        <Shot scene={scene} frames={frames} />
        <Caption title={scene.title} sub={scene.sub} index={i} frames={frames} />
      </Sequence>
    );
  });
  const start = totalFrames(script) - OUTRO - OVERLAP;
  return (
    <AbsoluteFill style={{width: W, height: H}}>
      <Background />
      <Sequence durationInFrames={INTRO}>
        <Title title={script.intro.title} line={script.intro.tagline} badge={script.intro.badge} frames={INTRO} />
      </Sequence>
      {items}
      <Steps script={script} />
      <Sequence from={start} durationInFrames={OUTRO + OVERLAP}>
        <Title title={script.outro.title} line={script.outro.line} frames={OUTRO + OVERLAP + 30} mono />
      </Sequence>
    </AbsoluteFill>
  );
};
