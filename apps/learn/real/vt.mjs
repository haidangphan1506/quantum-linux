// Giả lập terminal tối giản (xterm-like): đủ cho bash, vim, less, htop, nano…
// Màn hình = lưới ô {c: ký tự, f: màu chữ, b: màu nền, a: cờ (1 đậm, 2 mờ, 4 gạch chân, 8 đảo)}.
const PAL = ["#1f1d1a", "#e06c60", "#8fc27a", "#e5c07b", "#6fa3ef", "#c792ea", "#5fc3b8", "#d8d0c0",
             "#6b645a", "#ff8a7a", "#a9dc94", "#f5d68f", "#8dbcff", "#dcaaff", "#7fe0d4", "#fbf4e6"];
function color256(n) {
  if (n < 16) return PAL[n];
  if (n >= 232) { const v = 8 + (n - 232) * 10; return `rgb(${v},${v},${v})`; }
  n -= 16; const l = [0, 95, 135, 175, 215, 255];
  return `rgb(${l[Math.floor(n / 36)]},${l[Math.floor(n / 6) % 6]},${l[n % 6]})`;
}
export class VT {
  constructor(rows = 28, cols = 100) {
    this.dec = new TextDecoder("utf-8");
    this.scrollback = []; this.maxSb = 2000;
    this.alt = null; this.resize(rows, cols, true);
  }
  blank() { return { c: " ", f: null, b: null, a: 0 }; }
  newRow() { return Array.from({ length: this.cols }, () => this.blank()); }
  resize(rows, cols, init) {
    if (init) { this.rows = rows; this.cols = cols; this.grid = Array.from({ length: rows }, () => this.newRow()); this.x = 0; this.y = 0; this.top = 0; this.bot = rows - 1; this.pen = { f: null, b: null, a: 0 }; this.saved = null; this.curVis = true; this.state = 0; this.buf = ""; this.wrapNext = false; return; }
    const g = this.grid;
    this.rows = rows; this.cols = cols;
    this.grid = Array.from({ length: rows }, (_, i) => {
      const old = g[i]; const r = this.newRow();
      if (old) for (let j = 0; j < Math.min(cols, old.length); j++) r[j] = old[j];
      return r;
    });
    this.top = 0; this.bot = rows - 1; this.x = Math.min(this.x, cols - 1); this.y = Math.min(this.y, rows - 1);
  }
  scrollUp(n = 1) {
    for (let i = 0; i < n; i++) {
      const r = this.grid.splice(this.top, 1)[0];
      if (!this.alt && this.top === 0) { this.scrollback.push(r); if (this.scrollback.length > this.maxSb) this.scrollback.shift(); }
      this.grid.splice(this.bot, 0, this.newRow());
    }
  }
  scrollDown(n = 1) { for (let i = 0; i < n; i++) { this.grid.splice(this.bot, 1); this.grid.splice(this.top, 0, this.newRow()); } }
  lf() { if (this.y === this.bot) this.scrollUp(); else if (this.y < this.rows - 1) this.y++; }
  put(ch) {
    if (this.wrapNext) { this.x = 0; this.lf(); this.wrapNext = false; }
    const row = this.grid[this.y];
    row[this.x] = { c: ch, f: this.pen.f, b: this.pen.b, a: this.pen.a };
    if (this.x >= this.cols - 1) this.wrapNext = true; else this.x++;
  }
  write(bytes) {
    const s = this.dec.decode(bytes, { stream: true });
    for (const ch of s) this.feed(ch);
  }
  feed(ch) {
    const code = ch.codePointAt(0);
    if (this.state === 0) {
      if (ch === "\x1b") { this.state = 1; this.buf = ""; return; }
      if (code < 32 || code === 127) {
        if (ch === "\n" || ch === "\v" || ch === "\f") { this.lf(); this.wrapNext = false; }
        else if (ch === "\r") { this.x = 0; this.wrapNext = false; }
        else if (ch === "\b") { if (this.x > 0) this.x--; this.wrapNext = false; }
        else if (ch === "\t") { this.x = Math.min(this.cols - 1, (this.x + 8) & ~7); }
        return;
      }
      this.put(ch); return;
    }
    if (this.state === 1) {
      if (ch === "[") { this.state = 2; this.buf = ""; }
      else if (ch === "]") { this.state = 3; this.buf = ""; }
      else if (ch === "(" || ch === ")" || ch === "#") { this.state = 4; }
      else {
        this.state = 0;
        if (ch === "7") this.saved = { x: this.x, y: this.y, pen: { ...this.pen } };
        else if (ch === "8" && this.saved) { this.x = this.saved.x; this.y = this.saved.y; this.pen = { ...this.saved.pen }; }
        else if (ch === "M") { if (this.y === this.top) this.scrollDown(); else if (this.y > 0) this.y--; }
        else if (ch === "D") this.lf();
        else if (ch === "E") { this.x = 0; this.lf(); }
        else if (ch === "c") { this.resize(this.rows, this.cols, true); }
      }
      return;
    }
    if (this.state === 4) { this.state = 0; return; }
    if (this.state === 3) {   // OSC: hasta BEL o ESC \
      if (ch === "\x07") { this.osc(this.buf); this.state = 0; }
      else if (ch === "\x1b") { this.state = 5; }
      else this.buf += ch;
      return;
    }
    if (this.state === 5) { this.osc(this.buf); this.state = ch === "\\" ? 0 : 0; return; }
    // CSI
    if (code >= 0x40 && code <= 0x7e) { this.state = 0; this.csi(this.buf, ch); }
    else this.buf += ch;
  }
  osc(s) { if (this.onOsc) this.onOsc(s); }
  csi(params, fin) {
    const priv = params[0] === "?" || params[0] === ">" || params[0] === "=";
    const p = params.replace(/^[?>=]/, "").split(";").map((x) => (x === "" ? 0 : parseInt(x, 10) || 0));
    const n = (d = 1) => (p[0] > 0 ? p[0] : d);
    const clampY = () => { this.y = Math.max(0, Math.min(this.rows - 1, this.y)); };
    this.wrapNext = false;
    switch (fin) {
      case "A": this.y -= n(); clampY(); break;
      case "B": case "e": this.y += n(); clampY(); break;
      case "C": case "a": this.x = Math.min(this.cols - 1, this.x + n()); break;
      case "D": this.x = Math.max(0, this.x - n()); break;
      case "E": this.y += n(); clampY(); this.x = 0; break;
      case "F": this.y -= n(); clampY(); this.x = 0; break;
      case "G": case "`": this.x = Math.max(0, Math.min(this.cols - 1, n() - 1)); break;
      case "d": this.y = Math.max(0, Math.min(this.rows - 1, n() - 1)); break;
      case "H": case "f": this.y = Math.max(0, Math.min(this.rows - 1, (p[0] || 1) - 1)); this.x = Math.max(0, Math.min(this.cols - 1, (p[1] || 1) - 1)); break;
      case "J": {
        const m = p[0];
        if (m === 0) { this.clearRow(this.y, this.x, this.cols); for (let r = this.y + 1; r < this.rows; r++) this.clearRow(r, 0, this.cols); }
        else if (m === 1) { for (let r = 0; r < this.y; r++) this.clearRow(r, 0, this.cols); this.clearRow(this.y, 0, this.x + 1); }
        else { for (let r = 0; r < this.rows; r++) this.clearRow(r, 0, this.cols); if (m === 3) this.scrollback = []; }
        break;
      }
      case "K": { const m = p[0]; if (m === 0) this.clearRow(this.y, this.x, this.cols); else if (m === 1) this.clearRow(this.y, 0, this.x + 1); else this.clearRow(this.y, 0, this.cols); break; }
      case "L": { const k = Math.min(n(), this.bot - this.y + 1); for (let i = 0; i < k; i++) { this.grid.splice(this.bot, 1); this.grid.splice(this.y, 0, this.newRow()); } break; }
      case "M": { const k = Math.min(n(), this.bot - this.y + 1); for (let i = 0; i < k; i++) { this.grid.splice(this.y, 1); this.grid.splice(this.bot, 0, this.newRow()); } break; }
      case "P": { const row = this.grid[this.y]; row.splice(this.x, n()); while (row.length < this.cols) row.push(this.blank()); break; }
      case "@": { const row = this.grid[this.y]; for (let i = 0; i < n(); i++) row.splice(this.x, 0, this.blank()); row.length = this.cols; break; }
      case "X": this.clearRow(this.y, this.x, Math.min(this.cols, this.x + n())); break;
      case "S": this.scrollUp(n()); break;
      case "T": this.scrollDown(n()); break;
      case "r": this.top = Math.max(0, (p[0] || 1) - 1); this.bot = Math.min(this.rows - 1, (p[1] || this.rows) - 1); this.x = 0; this.y = this.top; break;
      case "s": this.saved = { x: this.x, y: this.y, pen: { ...this.pen } }; break;
      case "u": if (this.saved) { this.x = this.saved.x; this.y = this.saved.y; } break;
      case "m": this.sgr(p); break;
      case "h": case "l": {
        if (!priv) break;
        const on = fin === "h";
        for (const m of p) {
          if (m === 25) this.curVis = on;
          else if (m === 1049 || m === 1047 || m === 47) this.altScreen(on);
        }
        break;
      }
      case "n": if (p[0] === 6 && this.reply) this.reply(`\x1b[${this.y + 1};${this.x + 1}R`); break;
      case "c": if (this.reply && !priv) this.reply("\x1b[?1;2c"); break;
    }
  }
  clearRow(r, from, to) { const row = this.grid[r]; for (let i = from; i < to; i++) row[i] = this.blank(); }
  altScreen(on) {
    if (on && !this.alt) { this.alt = { grid: this.grid, x: this.x, y: this.y }; this.grid = Array.from({ length: this.rows }, () => this.newRow()); this.x = this.y = 0; }
    else if (!on && this.alt) { this.grid = this.alt.grid; this.x = this.alt.x; this.y = this.alt.y; this.alt = null; this.top = 0; this.bot = this.rows - 1; }
  }
  sgr(p) {
    if (!p.length) p = [0];
    for (let i = 0; i < p.length; i++) {
      const v = p[i];
      if (v === 0) this.pen = { f: null, b: null, a: 0 };
      else if (v === 1) this.pen.a |= 1;
      else if (v === 2) this.pen.a |= 2;
      else if (v === 4) this.pen.a |= 4;
      else if (v === 7) this.pen.a |= 8;
      else if (v === 22) this.pen.a &= ~3;
      else if (v === 24) this.pen.a &= ~4;
      else if (v === 27) this.pen.a &= ~8;
      else if (v >= 30 && v <= 37) this.pen.f = PAL[v - 30];
      else if (v >= 90 && v <= 97) this.pen.f = PAL[v - 90 + 8];
      else if (v >= 40 && v <= 47) this.pen.b = PAL[v - 40];
      else if (v >= 100 && v <= 107) this.pen.b = PAL[v - 100 + 8];
      else if (v === 39) this.pen.f = null;
      else if (v === 49) this.pen.b = null;
      else if (v === 38 || v === 48) {
        const key = v === 38 ? "f" : "b";
        if (p[i + 1] === 5) { this.pen[key] = color256(p[i + 2] || 0); i += 2; }
        else if (p[i + 1] === 2) { this.pen[key] = `rgb(${p[i + 2] || 0},${p[i + 3] || 0},${p[i + 4] || 0})`; i += 4; }
      }
    }
  }
  /** Ảnh màn hình để vẽ: các dòng là mảng đoạn {t, f, b, a}; offset = số dòng cuộn ngược lên lịch sử. */
  snapshot(offset = 0) {
    const sb = this.alt ? [] : this.scrollback;
    const all = sb.concat(this.grid);
    const off = Math.max(0, Math.min(offset, sb.length));
    const view = all.slice(all.length - this.rows - off, all.length - off);
    const rows = view.map((row) => {
      const segs = []; let cur = null;
      for (const c of row) {
        let f = c.f, b = c.b;
        if (c.a & 8) { const t = f; f = b || "#1f1d1a"; b = t || "#e9e1d3"; }
        if (cur && cur.f === f && cur.b === b && cur.a === (c.a & 7)) cur.t += c.c;
        else { cur = { t: c.c, f, b, a: c.a & 7 }; segs.push(cur); }
      }
      return segs;
    });
    return { rows, cx: this.x, cy: this.y + 0, cursor: this.curVis && off === 0, sb: sb.length, off, alt: !!this.alt };
  }
}
