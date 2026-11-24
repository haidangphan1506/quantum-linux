// Chấm bài theo KẾT QUẢ (không bắt gõ đúng từng ký tự lệnh).
// Với mỗi câu lab: chạy lệnh gợi ý trên bản sao phiên làm việc (replay các lệnh người học đã gõ) rồi so
//   - trạng thái hệ thống sau cùng (file, quyền, tiến trình, dịch vụ…) và thư mục hiện tại;
//   - nếu gợi ý chỉ đọc (không đổi trạng thái): đầu ra của lệnh người học phải chứa/khớp đầu ra của gợi ý.
// Bổ sung cho check() gốc và engine.equiv(); cách nào đạt thì câu đó được tính.

const SKIPW = new Set(["now", "boot", "nextPid", "jr", "cronRuns", "t", "locDb"]);
const FAKE = new Set(["echo", "printf", "true", ":", "false"]);

const normP = (p) => {
  const o = [];
  for (const x of p.split("/")) { if (!x || x === ".") continue; if (x === "..") o.pop(); else o.push(x); }
  return "/" + o.join("/");
};
const rtrim = (s) => String(s).split("\n").map((l) => l.replace(/\s+$/, "")).join("\n").replace(/\n+$/, "");

/** Chữ ký trạng thái (như engine.gradeSig nhưng bỏ qua khác biệt khoảng trắng cuối dòng/cuối file). */
export function sigLoose(sh) {
  const n = (sh.fs && sh.fs.n) || {};
  const o = [];
  for (const k of Object.keys(n).sort()) {
    if (/^\/(proc|sys|dev)(\/|$)/.test(k)) continue;
    const x = n[k];
    const tgt = x.t === "l" ? normP((x.target || "").charAt(0) === "/" ? x.target : k.replace(/\/[^/]*$/, "/") + x.target) : (x.target || "");
    const c = x.c == null ? "" : rtrim(typeof x.c === "string" ? x.c : JSON.stringify(x.c));
    o.push([k, x.t, x.mode, x.owner, x.group || "", tgt, c, x.size || ""].join("|"));
  }
  let w = "", env = "";
  try { w = JSON.stringify(sh.W, (k, v) => (typeof v === "function" || SKIPW.has(k) ? undefined : v)); } catch {}
  try { env = JSON.stringify([sh.vars, sh.env, sh.user]); } catch {}
  return o.join("\n") + "\n#" + w + "\n#" + env;
}

const lines = (s) => String(s || "").split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter(Boolean);
const toks = (s) => String(s || "").split(/\s+/).filter(Boolean);

/** Đầu ra người học "đủ" so với đầu ra gợi ý: giống hệt, khác thứ tự, đủ mọi dòng (thêm cờ), hoặc cùng các con số. */
export function outMatch(hintOut, userOut) {
  const H = lines(hintOut), U = lines(userOut);
  if (!H.length || !U.length) return false;
  if (H.join("\n") === U.join("\n")) return true;
  if ([...H].sort().join("\n") === [...U].sort().join("\n")) return true;
  const set = new Set(U);
  if (H.every((x) => set.has(x)) && U.length <= H.length * 4 + 8) return true;
  // vd `wc -l < f` so với `wc -l f`: chỉ cần các token là con của gợi ý và có đủ mọi số
  const h = toks(hintOut), u = toks(userOut);
  if (h.length <= 12 && H.length <= 3) {
    const nums = h.filter((x) => /^\d+$/.test(x));
    if (nums.length) {
      const pool = h.slice();
      for (const t of u) { const i = pool.indexOf(t); if (i < 0) return false; pool.splice(i, 1); }
      return nums.every((x) => u.includes(x));
    }
  }
  return false;
}

function verbs(t) {
  const out = new Set();
  for (const seg of String(t || "").split(/\|\||&&|[|;\n]/)) {
    const w = seg.trim().split(/\s+/);
    let i = 0;
    while (i < w.length && (/^[A-Za-z_]\w*=/.test(w[i]) || /^(sudo|time|!|\(|\{|nohup|command)$/.test(w[i]))) i++;
    if (w[i]) out.add(w[i].replace(/^.*\//, "").replace(/^[({]+/, ""));
  }
  return out;
}

function replay(engine, l, log, upto) {
  const sh = new engine.Shell({ host: l.lab.host, user: l.lab.user, setup: l.lab.setup });
  for (let i = 0; i < upto; i++) { try { sh.run(log[i].t); } catch {} }
  return sh;
}

/**
 * sh: phiên có cmdLog [{t,out,code}] (mô phỏng, hoặc bản replay từ lịch sử lệnh của container thật).
 * Xét 1–5 lệnh gần nhất (người học có thể làm một câu bằng vài lệnh).
 */
export function lenientEquiv(engine, l, sh, it, budget) {
  const log = sh.cmdLog || [], n = log.length;
  if (!n || !it.hint) return false;
  const last = log[n - 1];
  const cur = sigLoose(sh);
  for (let w = 1; w <= Math.min(5, n); w++) {
    if (budget && Date.now() - budget.t0 > budget.ms) return false;
    const win = log.slice(n - w);
    const shd = replay(engine, l, log, n - w);
    const before = sigLoose(shd), cwd0 = shd.cwd;
    let o;
    try { o = shd.run(it.hint); } catch { return false; }
    if (!!o.code !== !!last.code) continue;
    const after = sigLoose(shd);
    const out = String(o.out || "").replace(/\s+$/, "");
    const changed = before !== after, moved = shd.cwd !== cwd0;
    if (!changed && !moved && out === "") continue;           // gợi ý không có tác dụng nhìn thấy
    if (after !== cur) continue;                              // trạng thái cuối khác
    if (moved && shd.cwd !== sh.cwd) continue;
    if (changed || moved) return true;                        // kết quả (trạng thái) trùng: đạt
    // gợi ý chỉ đọc: so đầu ra, và không cho "echo" giả đầu ra
    const hv = verbs(it.hint);
    const uv = win.flatMap((x) => [...verbs(x.t)]);
    if (uv.length && uv.every((v) => FAKE.has(v)) && ![...hv].some((v) => FAKE.has(v))) continue;
    if (outMatch(out, last.out)) return true;
  }
  return false;
}

/** Dựng phiên mô phỏng từ các dòng lệnh đã gõ (cho terminal thật, vốn không có đầu ra của từng lệnh). */
export function feedShadow(engine, l, holder, rows) {
  let sd = holder.shadow;
  const sameHead = sd && rows.length >= sd.n && (sd.n === 0 || rows[sd.n - 1].cmd === sd.lastCmd);
  if (!sd || !sameHead) {
    sd = holder.shadow = { sh: new engine.Shell({ host: l.lab.host, user: l.lab.user, setup: l.lab.setup }), n: 0, lastCmd: "" };
    sd.sh.cmdLog = [];
  }
  for (; sd.n < rows.length; sd.n++) {
    const text = rows[sd.n].cmd;
    let r;
    try { r = sd.sh.run(text); } catch (e) { r = { out: "", code: 1 }; }
    if (r.needMore) continue;
    sd.sh.cmdLog.push({ t: text, out: r.out ?? "", code: r.code ?? 0 });
    sd.lastCmd = text;
  }
  return sd.sh;
}
