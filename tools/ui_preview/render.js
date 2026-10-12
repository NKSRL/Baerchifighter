// render.js — zeichnet einen Roblox-UI-Baum (JSON aus driver.lua) als HTML.
// Layoutregeln wie Roblox: Groesse = Eltern * Scale + Offset, AnchorPoint,
// UIPadding (Innenflaeche), UIListLayout (Reihe), AutomaticSize, UIScale
// (Transform), ZIndex unter Geschwistern, ClipsDescendants, ScrollingFrame.
// Optik: UICorner, UIStroke (aussen bzw. als Schriftkontur), UIGradient
// (multipliziert mit der Hintergrundfarbe), TextScaled mit
// UITextSizeConstraint (groesste Schrift, die passt).
"use strict";

const INSET = 36;
const GUI = new Set(["Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ScrollingFrame", "TextBox", "CanvasGroup"]);
const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);
const report = { texts: [], rects: {}, overflow: [], minFontPx: 999, warnings: [] };
const measure = document.getElementById("measure");

function mod(node, cls) { return node.children.filter(c => c.class === cls); }
function mod1(node, cls) { return node.children.find(c => c.class === cls && (c.props.Enabled !== false)); }
function udim(u, total) { return u ? (u.Scale || 0) * total + (u.Offset || 0) : 0; }
function rgb(c, a) { return `rgba(${Math.round(c[0]*255)},${Math.round(c[1]*255)},${Math.round(c[2]*255)},${a === undefined ? 1 : a})`; }
function vis(n) { return n.props.Visible !== false; }

function padding(node, w, h) {
  const p = mod1(node, "UIPadding");
  if (!p) return { l: 0, r: 0, t: 0, b: 0 };
  return {
    l: udim(p.props.PaddingLeft, w), r: udim(p.props.PaddingRight, w),
    t: udim(p.props.PaddingTop, h), b: udim(p.props.PaddingBottom, h),
  };
}

function textConstraint(node) {
  const c = mod1(node, "UITextSizeConstraint");
  return c ? { min: c.props.MinTextSize || 1, max: c.props.MaxTextSize || 100 } : { min: 1, max: 100 };
}

function measureText(text, size, wrapWidth) {
  measure.style.fontSize = size + "px";
  if (wrapWidth) { measure.style.whiteSpace = "pre-wrap"; measure.style.width = wrapWidth + "px"; measure.style.wordBreak = "break-word"; }
  else { measure.style.whiteSpace = "pre"; measure.style.width = "auto"; }
  measure.textContent = text;
  return { w: measure.scrollWidth, h: measure.scrollHeight };
}

// Groesste Schrift <= max, die in w x h passt (TextScaled)
function fitText(node, w, h) {
  const text = node.props.Text || "";
  const { min, max } = textConstraint(node);
  if (!text) return { size: max, fits: true };
  const wrap = node.props.TextWrapped === true;
  let lo = 1, hi = Math.max(1, Math.min(max, 200)), best = null;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    const m = measureText(text, mid, wrap ? w : null);
    if (m.w <= w + 0.5 && m.h <= h + 0.5) { best = mid; lo = mid + 1; } else hi = mid - 1;
  }
  if (best === null) return { size: min, fits: false };
  if (best < min) return { size: min, fits: false };
  return { size: best, fits: true };
}

function naturalSize(node, w, h) {
  // AutomaticSize: Inhalt (Text oder Kinder) + Polsterung
  const pad = padding(node, w, h);
  let nw = 0, nh = 0;
  if (TEXT.has(node.class) && !node.props.TextScaled) {
    const m = measureText(node.props.Text || "", node.props.TextSize || 14, null);
    nw = m.w; nh = m.h;
  }
  for (const c of node.children) {
    if (!GUI.has(c.class) || !vis(c)) continue;
    const cs = sizeOf(c, Math.max(0, w - pad.l - pad.r), Math.max(0, h - pad.t - pad.b));
    const px = udim(c.props.Position && c.props.Position.X, w);
    nw = Math.max(nw, Math.max(0, px) + cs.w);
    nh = Math.max(nh, cs.h);
  }
  return { w: nw + pad.l + pad.r, h: nh + pad.t + pad.b };
}

function sizeOf(node, pw, ph) {
  const s = node.props.Size || { X: { Scale: 0, Offset: 100 }, Y: { Scale: 0, Offset: 100 } };
  let w = udim(s.X, pw), h = udim(s.Y, ph);
  const auto = node.props.AutomaticSize;
  if (auto && auto !== "None") {
    const nat = naturalSize(node, w, h);
    if (auto === "X" || auto === "XY") w = Math.max(w, nat.w);
    if (auto === "Y" || auto === "XY") h = Math.max(h, nat.h);
  }
  const c = mod1(node, "UISizeConstraint");
  if (c) {
    const mn = c.props.MinSize || { X: 0, Y: 0 }, mx = c.props.MaxSize || { X: 1e9, Y: 1e9 };
    w = Math.min(Math.max(w, mn.X), mx.X); h = Math.min(Math.max(h, mn.Y), mx.Y);
  }
  return { w: Math.max(0, w), h: Math.max(0, h) };
}

function gradientCss(node, bg, bgT) {
  const g = mod1(node, "UIGradient");
  const base = bg || [1, 1, 1];
  if (!g) return null;
  const kps = (g.props.Color && g.props.Color.Keypoints) || [];
  const tk = (g.props.Transparency && g.props.Transparency.Keypoints) || [];
  const tAt = (t) => {
    if (!tk.length) return 0;
    for (let i = 1; i < tk.length; i++) {
      if (t <= tk[i].Time) {
        const a = tk[i - 1], b = tk[i]; const f = (t - a.Time) / Math.max(1e-6, b.Time - a.Time);
        return a.Value + (b.Value - a.Value) * f;
      }
    }
    return tk[tk.length - 1].Value;
  };
  const times = new Set([0, 1]); kps.forEach(k => times.add(k.Time)); tk.forEach(k => times.add(k.Time));
  const sorted = [...times].sort((a, b) => a - b);
  const colAt = (t) => {
    if (!kps.length) return [1, 1, 1];
    for (let i = 1; i < kps.length; i++) {
      if (t <= kps[i].Time) {
        const a = kps[i - 1], b = kps[i]; const f = (t - a.Time) / Math.max(1e-6, b.Time - a.Time);
        return [0, 1, 2].map(j => a.Value[j] + (b.Value[j] - a.Value[j]) * f);
      }
    }
    return kps[kps.length - 1].Value;
  };
  const stops = sorted.map(t => {
    const c = colAt(t);
    const a = (1 - bgT) * (1 - tAt(t));
    return `${rgb([c[0] * base[0], c[1] * base[1], c[2] * base[2]], a)} ${(t * 100).toFixed(1)}%`;
  });
  const angle = (g.props.Rotation || 0) + 90;
  return `linear-gradient(${angle}deg, ${stops.join(", ")})`;
}

function applyLook(node, el, w, h) {
  const p = node.props;
  const bgT = p.BackgroundTransparency === undefined ? 0 : p.BackgroundTransparency;
  if (bgT < 1) {
    const grad = gradientCss(node, p.BackgroundColor3, bgT);
    if (grad) el.style.backgroundImage = grad;
    else if (p.BackgroundColor3) el.style.backgroundColor = rgb(p.BackgroundColor3, 1 - bgT);
  }
  const corner = mod1(node, "UICorner");
  if (corner) {
    const r = udim(corner.props.CornerRadius, Math.min(w, h));
    el.style.borderRadius = Math.min(r, Math.min(w, h) / 2) + "px";
  }
  for (const st of mod(node, "UIStroke")) {
    if (st.props.Enabled === false) continue;
    const mode = st.props.ApplyStrokeMode || "Contextual";
    const t = st.props.Thickness || 1;
    const col = rgb(st.props.Color || [0, 0, 0], 1 - (st.props.Transparency || 0));
    if (TEXT.has(node.class) && mode === "Contextual") {
      el.dataset.textStroke = JSON.stringify({ t, col });
    } else {
      el.style.boxShadow = (el.style.boxShadow ? el.style.boxShadow + "," : "") + `0 0 0 ${t}px ${col}`;
    }
  }
}

function textLook(node, el, w, h, globalScale, path) {
  const p = node.props;
  const inner = document.createElement("div");
  inner.className = "t";
  inner.style.width = w + "px"; inner.style.height = h + "px";
  const xa = p.TextXAlignment || "Center", ya = p.TextYAlignment || "Center";
  inner.style.justifyContent = xa === "Left" ? "flex-start" : xa === "Right" ? "flex-end" : "center";
  inner.style.alignItems = ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center";
  inner.style.textAlign = xa === "Left" ? "left" : xa === "Right" ? "right" : "center";
  let size = p.TextSize || 14, fits = true;
  if (p.TextScaled) { const f = fitText(node, w, h); size = f.size; fits = f.fits; }
  else {
    const m = measureText(p.Text || "", size, p.TextWrapped ? w : null);
    fits = m.w <= w + 1 || p.AutomaticSize === "X" || p.AutomaticSize === "XY";
  }
  inner.style.fontSize = size + "px";
  inner.style.whiteSpace = p.TextWrapped ? "pre-wrap" : "pre";
  const c = p.TextColor3 || [0, 0, 0];
  inner.style.color = rgb(c, 1 - (p.TextTransparency || 0));
  const ts = el.dataset.textStroke ? JSON.parse(el.dataset.textStroke) : null;
  if (ts) { inner.style.webkitTextStroke = `${ts.t * 2}px ${ts.col}`; inner.style.paintOrder = "stroke fill"; }
  else if ((p.TextStrokeTransparency ?? 1) < 1) {
    inner.style.webkitTextStroke = `2px ${rgb(p.TextStrokeColor3 || [0, 0, 0], 1 - p.TextStrokeTransparency)}`;
    inner.style.paintOrder = "stroke fill";
  }
  inner.textContent = p.Text || "";
  el.appendChild(inner);
  if (p.Text && (p.TextTransparency || 0) < 1) {
    const px = size * globalScale;
    report.texts.push({ path, text: p.Text, sizeUnits: size, px: +px.toFixed(1) });
    report.minFontPx = Math.min(report.minFontPx, px);
    if (!fits) report.overflow.push({ path, text: p.Text, sizeUnits: size });
  }
}

let globalScaleRef = 1;

function build(node, parentEl, pw, ph, ox, oy, absX, absY, accScale, path) {
  // node ist ein GuiObject; (ox, oy) = Position in der Innenflaeche der Eltern
  const s = sizeOf(node, pw, ph);
  const el = document.createElement("div");
  el.className = "n";
  el.style.left = ox + "px"; el.style.top = oy + "px";
  el.style.width = s.w + "px"; el.style.height = s.h + "px";
  el.style.zIndex = String(node.props.ZIndex || 1);
  const p = node.props;
  const ap = p.AnchorPoint || { X: 0, Y: 0 };
  const sc = mod1(node, "UIScale");
  const scale = sc ? (sc.props.Scale ?? 1) : 1;
  const rot = p.Rotation || 0;
  const tf = [];
  if (rot) tf.push(`rotate(${rot}deg)`);
  if (scale !== 1) tf.push(`scale(${scale})`);
  if (tf.length) { el.style.transform = tf.join(" "); el.style.transformOrigin = `${ap.X * 100}% ${ap.Y * 100}%`; }
  if (p.ClipsDescendants || node.class === "ScrollingFrame") el.style.overflow = "hidden";
  applyLook(node, el, s.w, s.h);
  const myPath = path + "/" + node.name;
  const absScale = accScale * scale;
  report.rects[myPath] = { x: absX * globalScaleRef, y: absY * globalScaleRef + INSET, w: s.w * absScale * globalScaleRef, h: s.h * absScale * globalScaleRef };
  if (TEXT.has(node.class)) textLook(node, el, s.w, s.h, globalScaleRef * absScale, myPath);
  if ((node.class === "ImageLabel" || node.class === "ImageButton") && p.Image) {
    const src = ICONS[p.Image];
    if (src) {
      const img = document.createElement("img");
      img.src = src; img.style.width = "100%"; img.style.height = "100%"; img.style.objectFit = "contain";
      img.style.opacity = String(1 - (p.ImageTransparency || 0));
      el.appendChild(img);
    }
  }
  parentEl.appendChild(el);
  layoutChildren(node, el, s.w, s.h, absX, absY, absScale, myPath);
  return el;
}

function layoutChildren(node, el, w, h, absX, absY, accScale, path) {
  const pad = padding(node, w, h);
  const cw = Math.max(0, w - pad.l - pad.r), ch = Math.max(0, h - pad.t - pad.b);
  let scrollY = 0;
  if (node.class === "ScrollingFrame") scrollY = (node.props.CanvasPosition && node.props.CanvasPosition.Y) || 0;
  const kids = node.children.filter(c => GUI.has(c.class) && vis(c));
  const list = mod1(node, "UIListLayout");
  if (list) {
    const horiz = list.props.FillDirection === "Horizontal";
    const gap = udim(list.props.Padding, horiz ? cw : ch);
    const sorted = kids.slice().sort((a, b) => (list.props.SortOrder === "LayoutOrder" ? (a.props.LayoutOrder || 0) - (b.props.LayoutOrder || 0) : 0) || (a.id - b.id));
    const sizes = sorted.map(k => sizeOf(k, cw, ch));
    const total = sizes.reduce((acc, s) => acc + (horiz ? s.w : s.h), 0) + gap * Math.max(0, sizes.length - 1);
    const ha = list.props.HorizontalAlignment || "Center", va = list.props.VerticalAlignment || "Center";
    let cursor = horiz
      ? (ha === "Center" ? (cw - total) / 2 : ha === "Right" ? cw - total : 0)
      : (va === "Center" ? (ch - total) / 2 : va === "Bottom" ? ch - total : 0);
    sorted.forEach((k, i) => {
      const s = sizes[i];
      let x, y;
      if (horiz) { x = cursor; y = va === "Center" ? (ch - s.h) / 2 : va === "Bottom" ? ch - s.h : 0; cursor += s.w + gap; }
      else { y = cursor; x = ha === "Center" ? (cw - s.w) / 2 : ha === "Right" ? cw - s.w : 0; cursor += s.h + gap; }
      x += pad.l; y += pad.t - scrollY;
      build(k, el, cw, ch, x, y, absX + x * accScale, absY + y * accScale, accScale, path);
    });
    return;
  }
  for (const k of kids.sort((a, b) => a.id - b.id)) {
    const s = sizeOf(k, cw, ch);
    const pos = k.props.Position || { X: { Scale: 0, Offset: 0 }, Y: { Scale: 0, Offset: 0 } };
    const ap = k.props.AnchorPoint || { X: 0, Y: 0 };
    const x = pad.l + udim(pos.X, cw) - ap.X * s.w;
    const y = pad.t + udim(pos.Y, ch) - ap.Y * s.h - scrollY;
    build(k, el, cw, ch, x, y, absX + x * accScale, absY + y * accScale, accScale, path);
  }
}

async function main() {
  await document.fonts.load("20px FredokaOne");
  await document.fonts.ready;
  const gs = TREE.children.find(c => c.class === "UIScale");
  const g = gs ? (gs.props.Scale || 1) : 1;
  globalScaleRef = g;
  report.globalScale = g;
  const root = document.getElementById("root");
  root.className = "n";
  const W = VW / g, H = (VH - INSET) / g;
  Object.assign(root.style, { left: "0px", top: INSET + "px", width: W + "px", height: H + "px", transform: `scale(${g})`, transformOrigin: "0 0" });
  layoutChildren(TREE, root, W, H, 0, 0, 1, "RBL");
  window.__report = report;
  window.__done = true;
}
main();
