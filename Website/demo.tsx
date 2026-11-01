import { createRoot } from 'react-dom/client';
import { useRef, useState } from 'react';
import { MousePointer2, Pencil, ArrowUpRight, Square, Circle, Type, Undo2, Copy, Check, RotateCcw } from 'lucide-react';
import { Stage } from './vendor/stageshow/kit/stage';
import { Window, Text } from './vendor/stageshow/kit/window';
import type { Act } from './vendor/stageshow/kit/act';
import './demo.css';

type Scene = { tool: string; drawn: number; copied: boolean };
const initial: Scene = { tool: 'pointer', drawn: 0, copied: false };
const poster: Scene = { tool: 'pointer', drawn: 1, copied: true };
const english = document.documentElement.lang.startsWith('en');
const words = english ? {
  title: 'Screenshot annotation', tag: 'A LITTLE FIELD NOTE', headline: <>Good ideas.<br />Room to grow.</>,
  foot: 'Worth a closer look.', copied: 'Copied to clipboard', replay: 'Replay demo',
  description: 'Illustrated demo: select the rectangle tool, highlight the headline, then copy the screenshot.',
} : {
  title: '截图标注', tag: 'A LITTLE FIELD NOTE', headline: <>好点子，<br />从这里开始。</>,
  foot: '让重点，一眼可见。', copied: '已复制到剪贴板', replay: '重播演示',
  description: '功能示意演示：选择矩形工具，框出标题，再复制截图。',
};

// Once in view: the annotation remains as the result until the visitor replays.
async function annotate(a: Act<Scene>) {
  await a.wait(1100);
  await a.click('rectangle');
  await a.set({ tool: 'rectangle' });
  a.mark('tool');
  await a.wait(750);
  await a.cursor('crosshair');
  const box = a.rect('highlight');
  await a.move({ x: box.x, y: box.y });
  await a.drag({ x: box.x + box.width, y: box.y + box.height }, at => a.put({ drawn: (at.x - box.x) / box.width }), {
    duration: 1200, cursor: 'preserve',
    path: (progress, from, to) => ({ x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress }),
  });
  a.mark('outlined');
  await a.wait(1600);
  await a.cursor('pointer');
  await a.click('pointer');
  await a.set({ tool: 'pointer' });
  await a.wait(600);
  await a.click('copy');
  await a.set({ copied: true });
  a.mark('copied');
  await a.wait(3000);
}

function Demo() {
  const [take, setTake] = useState(0);
  const reduced = useRef(window.matchMedia('(prefers-reduced-motion: reduce)'));
  return <>
    <span className="demo-sr-only">{words.description}</span>
    <div aria-hidden="true">
      <Stage key={take} width={620} height={480} compact={{ below: 570, width: 358, height: 358 }} initial={initial} poster={poster}
        script={annotate} play="once" fidelity="realistic" cursor={{ at: 'rectangle', kind: 'pointer', style: 'real' }} className="sakura-demo"
        tokens={{ '--ss-accent': '#b56383', '--ss-canvas': '#e3eaf1', '--ss-surface': '#f8fafc', '--ss-chrome': '#f8fafc', '--ss-text-strong': '#314b61', '--ss-text': '#60768b', '--ss-well': 'transparent' }}>
        {(s) => <>
          <Window title={words.title} className="sakura-editor" toolbar={<span className="demo-zoom">100%</span>}>
            <div className="demo-canvas">
              <div className="demo-paper" data-cursor={s.tool === 'rectangle' ? 'crosshair' : 'pointer'}>
                <Text className="demo-paper-tag">{words.tag}</Text>
                <div className="demo-headline">{words.headline}</div>
                <svg className="demo-art" viewBox="0 0 176 202" aria-hidden="true"><path d="M0 88a88 88 0 0 1 176 0v114H0Z" fill="#d7e4f0" /><circle cx="100" cy="70" r="45" fill="#e4b0c1" /><path d="M0 118q90 14 176 80v4H0Z" fill="#afc5d7" /><path d="M0 202q66-53 176-57v57Z" fill="#6e8ca6" /></svg>
                <Text className="demo-paper-foot">{words.foot}</Text>
                <div className="demo-highlight" data-target="highlight"><div style={{ width: `${s.drawn * 100}%`, height: `${s.drawn * 100}%`, opacity: s.drawn > 0 ? 1 : 0 }} /></div>
              </div>
              <div className="demo-toolbar">
                {[
                  ['pointer', MousePointer2], ['pen', Pencil], ['arrow', ArrowUpRight], ['rectangle', Square], ['ellipse', Circle], ['text', Type],
                ].map(([name, Glyph]) => {
                  const Tool = Glyph as typeof Square;
                  return <span key={name as string} className="demo-tool" data-target={name as string} data-cursor="pointer" data-active={s.tool === name || undefined}><Tool size={18} strokeWidth={1.7} /></span>;
                })}
                <span className="demo-divider" />
                <span className="demo-tool demo-color" />
                <span className="demo-tool demo-undo"><Undo2 size={18} strokeWidth={1.7} /></span>
                <span className="demo-divider" />
                <span className="demo-tool demo-copy" data-target="copy" data-cursor="pointer" data-copied={s.copied || undefined}><Copy size={18} strokeWidth={1.7} className="demo-copy-icon" /><Check size={18} strokeWidth={1.7} className="demo-check-icon" /></span>
              </div>
            </div>
          </Window>
          <div className="demo-confirmation" data-show={s.copied || undefined}><span className="demo-confirm-icon"><Check size={16} strokeWidth={1.7} /></span><Text>{words.copied}</Text></div>
        </>}
      </Stage>
    </div>
    <button type="button" className="demo-replay" onClick={() => { if (!reduced.current.matches) setTake(value => value + 1); }}><RotateCcw size={13} strokeWidth={1.7} />{words.replay}</button>
  </>;
}

const host = document.getElementById('product-demo');
if (host) {
  createRoot(host).render(<Demo />);
  host.classList.add('demo-mounted');
}
