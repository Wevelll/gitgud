import React, { useState, useEffect, useRef } from "react";

// ---- geometry ---------------------------------------------------------------
const CX = 180, CY = 180;
const RO = 150, RI = 96, RL = 123;        // segment outer / inner / label radius
const HUB = 82;                            // center hub radius
const TICK_IN = 152, TICK_OUT = 160, TICK_MAJ = 167;
const NUM_R = 176;
const D = Math.PI / 180;
const pt = (r, a) => [CX + r * Math.sin(a * D), CY - r * Math.cos(a * D)];
const timeAngle = (min) => (min / 1440) * 360;     // clockwise from top, midnight at top
const mod = (n, m) => ((n % m) + m) % m;

function sectorPath(a0, a1, ri, ro) {
  const large = a1 - a0 > 180 ? 1 : 0;
  const [x0o, y0o] = pt(ro, a0), [x1o, y1o] = pt(ro, a1);
  const [x1i, y1i] = pt(ri, a1), [x0i, y0i] = pt(ri, a0);
  return `M ${x0o} ${y0o} A ${ro} ${ro} 0 ${large} 1 ${x1o} ${y1o} L ${x1i} ${y1i} A ${ri} ${ri} 0 ${large} 0 ${x0i} ${y0i} Z`;
}
const pad = (n) => String(n).padStart(2, "0");
const fmt = (min) => { const m = mod(Math.round(min), 1440); return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`; };
const fmtDur = (min) => { const h = Math.floor(min / 60), m = Math.round(min % 60); return h === 0 ? `${m}m` : m === 0 ? `${h}h` : `${h}h ${m}m`; };

// ---- data -------------------------------------------------------------------
// Blocks are stored in cyclic schedule order; each block's end is the next start.
const INITIAL = [
  { start: 1380, name: "Sleep",     color: "#4B4FA6" }, // 23:00
  { start: 420,  name: "Morning",   color: "#C98A3E" }, // 07:00
  { start: 540,  name: "Deep work", color: "#2E8B8B" }, // 09:00
  { start: 780,  name: "Lunch",     color: "#B5624F" }, // 13:00
  { start: 840,  name: "Work",      color: "#3E7CB1" }, // 14:00
  { start: 1080, name: "Free time", color: "#6FA85B" }, // 18:00
];
const durOf = (b, i) => mod(b[(i + 1) % b.length].start - b[i].start, 1440);
const indexAt = (b, now) => { for (let i = 0; i < b.length; i++) { if (mod(now - b[i].start, 1440) < durOf(b, i)) return i; } return 0; };

// ---- component --------------------------------------------------------------
export default function DayDial() {
  const nowMin = () => { const d = new Date(); return d.getHours() * 60 + d.getMinutes(); };
  const [now, setNow] = useState(nowMin());
  const [live, setLive] = useState(true);
  const [playing, setPlaying] = useState(false);
  const [mode, setMode] = useState("compass");      // "compass" (ring rotates) | "clock" (hand rotates)
  const [blocks, setBlocks] = useState(INITIAL);
  const [sel, setSel] = useState(null);
  const [tasks, setTasks] = useState([
    { label: "Take meds", done: false },
    { label: "20 min stretch", done: false },
    { label: "Reply to Andrei", done: true },
  ]);
  const timer = useRef(null);

  useEffect(() => {
    if (live && !playing) { const t = setInterval(() => setNow(nowMin()), 1000); return () => clearInterval(t); }
  }, [live, playing]);
  useEffect(() => {
    if (playing) { timer.current = setInterval(() => setNow((n) => mod(n + 4, 1440)), 60); return () => clearInterval(timer.current); }
  }, [playing]);

  const cur = indexAt(blocks, now);
  const off = mod(now - blocks[cur].start, 1440);
  const remain = durOf(blocks, cur) - off;
  const nxt = blocks[(cur + 1) % blocks.length];
  const theta = mode === "compass" ? -timeAngle(now) : 0;  // disc rotation

  const resize = (i, delta) => {
    setBlocks((bs) => {
      const j = (i + 1) % bs.length;
      const S = durOf(bs, i) + durOf(bs, j);
      const cand = mod(bs[j].start + delta, 1440);
      const dI = mod(cand - bs[i].start, 1440);
      if (dI < 15 || dI > S - 15) return bs;
      const copy = bs.map((b) => ({ ...b }));
      copy[j].start = cand;
      return copy;
    });
  };

  const numerals = [0, 3, 6, 9, 12, 15, 18, 21];

  return (
    <div className="w-full min-h-screen flex justify-center p-4" style={{ background: "#0A0D18", color: "#E7E9F2", fontFamily: "ui-sans-serif, system-ui, sans-serif" }}>
      <div className="w-full max-w-md flex flex-col gap-4">
        <div className="flex items-baseline justify-between">
          <div>
            <div className="text-xs uppercase tracking-widest" style={{ color: "#7C82A0" }}>your day · 24h</div>
            <div className="font-mono text-lg" style={{ color: "#E7E9F2" }}>{fmt(now)}</div>
          </div>
          <div className="flex gap-1 p-1 rounded-full" style={{ background: "#141A2B" }}>
            {["compass", "clock"].map((m) => (
              <button key={m} onClick={() => setMode(m)} className="px-3 py-1 rounded-full text-xs capitalize"
                style={{ background: mode === m ? "#2E8B8B" : "transparent", color: mode === m ? "#04140F" : "#9AA0BC", fontWeight: mode === m ? 600 : 400 }}>
                {m}
              </button>
            ))}
          </div>
        </div>

        {/* ---- the dial ---- */}
        <div className="rounded-3xl p-3" style={{ background: "#0E1322", boxShadow: "inset 0 1px 0 rgba(255,255,255,.04)" }}>
          <svg viewBox="0 0 360 360" className="w-full h-auto">
            <defs>
              <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#0F1526" />
                <stop offset="100%" stopColor="#1B2136" />
              </linearGradient>
              <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="2.4" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
            </defs>

            <circle cx={CX} cy={CY} r={RO + 12} fill="url(#plate)" stroke="#232A42" strokeWidth="1" />

            {/* rotating day-disc: segments + ticks + numerals */}
            <g transform={`rotate(${theta} ${CX} ${CY})`}>
              {blocks.map((b, i) => {
                const a0 = timeAngle(b.start), a1 = a0 + timeAngle(durOf(blocks, i));
                const selected = sel === i;
                return (
                  <path key={i} d={sectorPath(a0, a1, RI, RO)} fill={b.color}
                    fillOpacity={selected ? 1 : 0.9} stroke={selected ? "#F2E9D8" : "#0E1322"}
                    strokeWidth={selected ? 2 : 1.5} style={{ cursor: "pointer" }}
                    onClick={() => setSel(i)} />
                );
              })}

              {Array.from({ length: 24 }).map((_, h) => {
                const a = h * 15, [x1, y1] = pt(TICK_IN, a), maj = h % 6 === 0;
                const [x2, y2] = pt(maj ? TICK_MAJ : TICK_OUT, a);
                return <line key={h} x1={x1} y1={y1} x2={x2} y2={y2} stroke={maj ? "#5A607F" : "#333A54"} strokeWidth={maj ? 1.6 : 1} />;
              })}

              {blocks.map((b, i) => {
                const am = timeAngle(b.start) + timeAngle(durOf(blocks, i)) / 2;
                const [x, y] = pt(RL, am);
                if (durOf(blocks, i) < 55) return null; // hide labels on very thin wedges
                return (
                  <text key={i} x={x} y={y} transform={`rotate(${-theta} ${x} ${y})`} textAnchor="middle"
                    dominantBaseline="central" fontSize="11" fill="#F3F4FB" fontWeight="600"
                    style={{ pointerEvents: "none" }}>{b.name}</text>
                );
              })}

              {numerals.map((h) => {
                const a = h * 15, [x, y] = pt(NUM_R, a);
                return (
                  <text key={h} x={x} y={y} transform={`rotate(${-theta} ${x} ${y})`} textAnchor="middle"
                    dominantBaseline="central" fontSize="10" fill="#737a9c" style={{ pointerEvents: "none", fontFamily: "ui-monospace, monospace" }}>{pad(h)}</text>
                );
              })}
            </g>

            {/* fixed hub / readout */}
            <circle cx={CX} cy={CY} r={HUB} fill="#0B1020" stroke="#232A42" strokeWidth="1" />
            <text x={CX} y={CY - 22} textAnchor="middle" fontSize="10" fill="#8B90AE" style={{ letterSpacing: "1.5px", textTransform: "uppercase" }}>now</text>
            <text x={CX} y={CY - 4} textAnchor="middle" fontSize="15" fill="#F3F4FB" fontWeight="700">{blocks[cur].name}</text>
            <text x={CX} y={CY + 20} textAnchor="middle" fontSize="19" fill={blocks[cur].color} style={{ fontFamily: "ui-monospace, monospace", fontWeight: 700 }}>{fmtDur(remain)} left</text>
            <text x={CX} y={CY + 40} textAnchor="middle" fontSize="9.5" fill="#7C82A0">next · {nxt.name} at {fmt(nxt.start)}</text>

            {/* now indicator */}
            {mode === "compass" ? (
              <g filter="url(#glow)">
                <path d={`M ${CX} ${CY - RO + 4} L ${CX - 8} ${CY - RO - 12} L ${CX + 8} ${CY - RO - 12} Z`} fill="#F2E9D8" />
              </g>
            ) : (
              <g filter="url(#glow)">
                <line x1={CX} y1={CY} x2={pt(RO - 4, timeAngle(now))[0]} y2={pt(RO - 4, timeAngle(now))[1]} stroke="#F2E9D8" strokeWidth="2.5" strokeLinecap="round" />
                <circle cx={CX} cy={CY} r="4" fill="#F2E9D8" />
              </g>
            )}
          </svg>
        </div>

        {/* ---- controls ---- */}
        <div className="flex gap-2">
          <button onClick={() => { setLive((v) => !v); setPlaying(false); }} className="flex-1 py-2 rounded-xl text-sm"
            style={{ background: live ? "#2E8B8B" : "#141A2B", color: live ? "#04140F" : "#9AA0BC", fontWeight: live ? 600 : 400 }}>
            {live ? "● Live" : "Live"}
          </button>
          <button onClick={() => { setPlaying((v) => !v); setLive(false); }} className="flex-1 py-2 rounded-xl text-sm"
            style={{ background: playing ? "#C98A3E" : "#141A2B", color: playing ? "#160C02" : "#9AA0BC", fontWeight: playing ? 600 : 400 }}>
            {playing ? "⏸ Stop demo" : "▶ Watch a day"}
          </button>
        </div>

        <div className="rounded-xl p-3" style={{ background: "#0E1322" }}>
          <div className="flex justify-between text-xs mb-2" style={{ color: "#7C82A0" }}>
            <span>Scrub the day</span><span className="font-mono">{fmt(now)}</span>
          </div>
          <input type="range" min={0} max={1439} value={now} disabled={live || playing}
            onChange={(e) => setNow(Number(e.target.value))} className="w-full" style={{ accentColor: "#2E8B8B", opacity: live || playing ? 0.4 : 1 }} />
        </div>

        {/* selected block editor */}
        <div className="rounded-xl p-3 flex items-center justify-between" style={{ background: "#0E1322" }}>
          {sel === null ? (
            <span className="text-sm" style={{ color: "#7C82A0" }}>Tap a wedge to resize it →</span>
          ) : (
            <>
              <div className="text-sm">
                <div style={{ color: blocks[sel].color, fontWeight: 600 }}>{blocks[sel].name}</div>
                <div className="font-mono text-xs" style={{ color: "#7C82A0" }}>{fmt(blocks[sel].start)}–{fmt(mod(blocks[(sel + 1) % blocks.length].start, 1440))} · {fmtDur(durOf(blocks, sel))}</div>
              </div>
              <div className="flex gap-2">
                <button onClick={() => resize(sel, -15)} className="w-9 h-9 rounded-lg" style={{ background: "#1B2136", color: "#E7E9F2" }}>−</button>
                <button onClick={() => resize(sel, 15)} className="w-9 h-9 rounded-lg" style={{ background: "#1B2136", color: "#E7E9F2" }}>+</button>
              </div>
            </>
          )}
        </div>

        {/* recurring untimed tasks */}
        <div className="rounded-xl p-3" style={{ background: "#0E1322" }}>
          <div className="text-xs uppercase tracking-widest mb-2" style={{ color: "#7C82A0" }}>Must-do today · no fixed time</div>
          <div className="flex flex-col gap-1.5">
            {tasks.map((t, i) => (
              <button key={i} onClick={() => setTasks((ts) => ts.map((x, k) => (k === i ? { ...x, done: !x.done } : x)))}
                className="flex items-center gap-2 text-sm text-left py-1">
                <span className="inline-flex items-center justify-center w-4 h-4 rounded" style={{ border: "1.5px solid #3E7CB1", background: t.done ? "#3E7CB1" : "transparent", color: "#04140F", fontSize: 11 }}>{t.done ? "✓" : ""}</span>
                <span style={{ color: t.done ? "#5A6078" : "#D6D9E8", textDecoration: t.done ? "line-through" : "none" }}>{t.label}</span>
              </button>
            ))}
          </div>
        </div>

        <p className="text-xs leading-relaxed" style={{ color: "#5A6078" }}>
          Compass mode locks <span style={{ color: "#F2E9D8" }}>now</span> to the top marker and rotates the whole day beneath it — what's next is the wedge just clockwise of the pointer. Clock mode keeps the dial fixed and moves a hand instead. Hit “Watch a day” to see the rotation.
        </p>
      </div>
    </div>
  );
}
