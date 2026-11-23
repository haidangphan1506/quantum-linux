// Proxy Docker API cho lab: container lab nói chuyện với engine Kiri THẬT của máy qua một socket riêng,
// nhưng chỉ thấy và đụng được những gì của chính lab đó:
//   - container / network / volume tạo ra đều được gắn nhãn quantum-learn.lab=<lab>; danh sách và thao tác lọc theo nhãn
//   - image: chỉ hiện image lab đã dùng/kéo/tạo; xoá image có sẵn trên máy chỉ "ẩn" khỏi lab, không xoá thật
//   - chặn --privileged, --pid/--network/--ipc=host, thiết bị, CAP_SYS_ADMIN (sẽ là root trên máy thật)
//   - cổng publish (-p 8080:80) KHÔNG mở trên máy thật; lab gọi localhost:8080 được nhờ DNAT tới IP container
//     (onPorts), docker ps vẫn hiện đúng cổng đã khai báo
//   - bind mount (-v /đường/dẫn:/x) trỏ tới bản sao của thư mục đó lấy từ container lab (không đụng file máy thật)
import http from "node:http";
import { createHash } from "node:crypto";
import net from "node:net";
import { mkdirSync, rmSync, existsSync, unlinkSync } from "node:fs";
import { spawn } from "node:child_process";
import { join } from "node:path";

const UPSTREAM = process.env.QL_DOCKER_SOCK || "/run/kiri/docker.sock";
export const LAB_LABEL = "quantum-learn.lab";

function up(method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const r = http.request({ socketPath: UPSTREAM, method, path, headers: { Host: "docker", ...headers } }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        let json = null;
        try { json = JSON.parse(buf.toString("utf8")); } catch {}
        resolve({ status: res.statusCode, headers: res.headers, buf, json });
      });
    });
    r.on("error", reject);
    if (body != null) r.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
    else r.end();
  });
}
const sendJson = (res, status, obj, extra = {}) => {
  let text = JSON.stringify(obj);
  if (res.px) text = text.split(res.px).join("");          // tên container/mạng/volume thật có tiền tố lab: ẩn đi
  const b = Buffer.from(text);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": b.length, "Api-Version": "1.47", ...extra });
  res.end(b);
};
const deny = (res, msg) => sendJson(res, 403, { message: "Quantum Learn: " + msg });
const notFound = (res, kind, id) => sendJson(res, 404, { message: `No such ${kind}: ${id}` });

function readBody(req) {
  return new Promise((resolve) => { const c = []; req.on("data", (d) => c.push(d)); req.on("end", () => resolve(Buffer.concat(c))); });
}
function addLabelFilter(url, lab) {
  let f = {};
  try { f = JSON.parse(url.searchParams.get("filters") || "{}"); } catch {}
  if (Array.isArray(f.label)) f.label.push(`${LAB_LABEL}=${lab}`);
  else if (f.label && typeof f.label === "object") f.label[`${LAB_LABEL}=${lab}`] = true;
  else f.label = [`${LAB_LABEL}=${lab}`];
  url.searchParams.set("filters", JSON.stringify(f));
}

export class DockProxy {
  /** lab: tên container lab; sockDir: thư mục chứa docker.sock (gắn vào lab); stage: thư mục bản sao bind mount */
  constructor({ lab, sockDir, stage, labContainer, onPorts }) {
    Object.assign(this, { lab, sockDir, stage, labContainer, onPorts });
    // Tên container/mạng/volume trên engine là TOÀN CỤC: mỗi lab thêm tiền tố riêng, người học luôn thấy tên gốc.
    this.px = "ql" + createHash("sha1").update(lab).digest("hex").slice(0, 6) + "-";
    this.sock = join(sockDir, "docker.sock");
    this.images = new Set();        // tên/ID image lab "biết" (kéo, tag, commit, build, dùng)
    this.hidden = new Set();        // image có sẵn trên máy mà lab đã "xoá" (chỉ ẩn)
    this.protected = new Set();     // ID image có trên máy lúc lab bắt đầu
  }
  async start() {
    mkdirSync(this.sockDir, { recursive: true });
    if (existsSync(this.sock)) unlinkSync(this.sock);
    const imgs = await up("GET", "/images/json").catch(() => ({ json: [] }));
    for (const i of imgs.json ?? []) this.protected.add(i.Id);
    this.server = http.createServer((req, res) => this.handle(req, res).catch((e) => sendJson(res, 500, { message: String(e?.message ?? e) })));
    // Node's http parser nuốt mất thân request của các request "Upgrade" (exec start), nên kết nối nào mở đầu bằng
    // request Upgrade được xử lý thô; còn lại giao cho http server.
    this.raw = net.createServer({ allowHalfOpen: true }, (sock) => {
      let buf = Buffer.alloc(0);
      const onData = (d) => {
        buf = Buffer.concat([buf, d]);
        const end = buf.indexOf("\r\n\r\n");
        if (end < 0 && buf.length < 65536) return;
        sock.removeListener("data", onData);
        sock.pause();
        const headText = buf.slice(0, end).toString("latin1");
        if (/\r\nupgrade:/i.test(headText)) this.rawUpgrade(sock, headText, buf.slice(end + 4)).catch(() => sock.destroy());
        else { sock.unshift(buf); this.server.emit("connection", sock); sock.resume(); }
      };
      sock.on("data", onData);
      sock.on("error", () => {});
    });
    await new Promise((r) => this.raw.listen(this.sock, r));
    try { (await import("node:fs")).chmodSync(this.sock, 0o666); } catch {}
  }
  async stop() {
    try { this.raw?.close(); } catch {}
    try { this.server?.close(); } catch {}
    try { unlinkSync(this.sock); } catch {}
  }

  // -------- quyền sở hữu
  async ownContainer(id) {
    const r = await up("GET", `/containers/${encodeURI(id)}/json`);
    return r.status === 200 && r.json?.Config?.Labels?.[LAB_LABEL] === this.lab ? r.json : null;
  }
  async ownNetwork(id, allowBuiltin) {
    if (allowBuiltin && ["bridge", "host", "none"].includes(id)) return true;
    const r = await up("GET", `/networks/${encodeURIComponent(id)}`);
    return r.status === 200 && (r.json?.Labels?.[LAB_LABEL] === this.lab || (allowBuiltin && ["bridge", "host", "none"].includes(r.json?.Name)));
  }
  async ownVolume(name) {
    const r = await up("GET", `/volumes/${encodeURIComponent(name)}`);
    return r.status === 200 && r.json?.Labels?.[LAB_LABEL] === this.lab;
  }
  async joinNetwork(id) {
    if (!this.labContainer) return;
    await up("POST", `/networks/${encodeURI(id)}/connect`, { Container: this.labContainer }, { "Content-Type": "application/json" }).catch(() => {});
  }
  /** Thêm tiền tố lab vào một tên (không đụng ID hex, mạng dựng sẵn, "container:x"). */
  enc(name) {
    if (!name || /^[0-9a-f]{12,64}$/.test(name) || ["bridge", "host", "none", "default"].includes(name) || name.startsWith(this.px)) return name;
    if (name.startsWith("container:")) return "container:" + this.enc(name.slice(10));
    return this.px + name;
  }
  /** Viết lại phần tên trong URL: /containers/<ref>, /networks/<ref>, /volumes/<ref> và tham số name/container. */
  rewriteUrl(rawUrl) {
    const u = new URL(rawUrl, "http://d");
    const m = /^(\/v[\d.]+)?\/(containers|networks|volumes)\/([^/]+)(.*)$/.exec(u.pathname);
    if (m && !["json", "create", "prune"].includes(m[3])) u.pathname = `${m[1] ?? ""}/${m[2]}/${encodeURIComponent(this.enc(decodeURIComponent(m[3])))}${m[4]}`;
    if (/\/containers\/create$/.test(u.pathname) && u.searchParams.get("name")) u.searchParams.set("name", this.enc(u.searchParams.get("name")));
    if (/\/commit$/.test(u.pathname) && u.searchParams.get("container")) u.searchParams.set("container", this.enc(u.searchParams.get("container")));
    return u.pathname + (u.search || "");
  }
  labelsFor(extra) { return Object.assign({}, extra || {}, { [LAB_LABEL]: this.lab, "quantum-learn": "1" }); }

  // -------- bind mount: chép thư mục/file từ container lab sang thư mục bản sao trên máy
  stageBind(src) {
    // Socket Docker (/var/run/docker.sock): mount chính socket của lab (đã được proxy lọc), không sao chép.
    if (/(^|\/)docker\.sock$/.test(src)) return Promise.resolve(this.sock);
    const dst = join(this.stage, src);
    mkdirSync(join(dst, ".."), { recursive: true });
    return new Promise((resolve) => {
      const rel = src.replace(/^\/+/, "");
      const out = spawn("docker", ["exec", this.labContainer, "tar", "-C", "/", "-cf", "-", rel], { stdio: ["ignore", "pipe", "ignore"] });
      const tar = spawn("tar", ["-C", this.stage, "-xf", "-"], { stdio: ["pipe", "ignore", "ignore"] });
      out.stdout.pipe(tar.stdin);
      tar.on("close", () => { if (!existsSync(dst)) mkdirSync(dst, { recursive: true }); resolve(dst); });
    });
  }

  async rewriteCreate(body) {
    const hc = body.HostConfig ||= {};
    if (hc.Privileged) return "--privileged bị chặn trong lab (container chạy trên engine Kiri của máy thật).";
    for (const [k, v] of [["PidMode", "--pid=host"], ["NetworkMode", "--network=host"], ["IpcMode", "--ipc=host"], ["UTSMode", "--uts=host"], ["UsernsMode", "--userns=host"]]) {
      if (hc[k] === "host") return `${v} bị chặn trong lab.`;
    }
    if ((hc.Devices || []).length) return "--device bị chặn trong lab.";
    if ((hc.CapAdd || []).some((c) => /^(CAP_)?(ALL|SYS_ADMIN|SYS_MODULE|SYS_RAWIO|SYS_PTRACE|NET_ADMIN|DAC_READ_SEARCH)$/i.test(c))) return "--cap-add nguy hiểm bị chặn trong lab.";
    body.Labels = this.labelsFor(body.Labels);
    // mạng / volume / hostname theo tên gốc
    const orig = hc.NetworkMode && !["default", "bridge", "host", "none"].includes(hc.NetworkMode) ? hc.NetworkMode : "";
    if (hc.NetworkMode) hc.NetworkMode = this.enc(hc.NetworkMode);
    const eps = body.NetworkingConfig?.EndpointsConfig;
    if (eps) {
      const fixed = {};
      for (const [k, v] of Object.entries(eps)) fixed[this.enc(k)] = v;
      body.NetworkingConfig.EndpointsConfig = fixed;
    }
    for (const m of hc.Mounts || []) if (m.Type === "volume" && m.Source) m.Source = this.enc(m.Source);
    // cổng publish: KHÔNG mở cổng trên máy thật. Lưu cấu hình gốc trong nhãn; lab gọi localhost:<cổng> được nhờ
    // DNAT thẳng tới IP container (syncPorts); docker ps / inspect vẫn hiện đúng như người học đã gõ.
    if (hc.PublishAllPorts) return "-P (publish tất cả cổng) chưa hỗ trợ trong lab, hãy dùng -p cổng:cổng.";
    const pb = hc.PortBindings || {};
    body.Labels["quantum-learn.ports"] = JSON.stringify(pb);
    body.ExposedPorts = Object.assign({}, body.ExposedPorts || {}, Object.fromEntries(Object.keys(pb).map((k) => [k, {}])));
    delete hc.PortBindings;
    // bind mount
    const binds = [];
    for (const b of hc.Binds || []) {
      const [src, ...rest] = b.split(":");
      if (src.startsWith("/")) binds.push([await this.stageBind(src), ...rest].join(":"));
      else binds.push([this.enc(src), ...rest].join(":"));
    }
    if (hc.Binds) hc.Binds = binds;
    for (const m of hc.Mounts || []) if (m.Type === "bind" && m.Source?.startsWith("/")) m.Source = await this.stageBind(m.Source);
    if (body.Image) this.images.add(body.Image);
    return null;
  }
  static portsOf(c) {
    try { return JSON.parse(c?.Labels?.["quantum-learn.ports"] ?? c?.Config?.Labels?.["quantum-learn.ports"] ?? "{}"); } catch { return {}; }
  }
  /** Hiển thị lại cổng publish như thật (từ nhãn) trong kết quả ps / inspect. */
  fixHostIp(c) {
    if (!c) return c;
    const pb = DockProxy.portsOf(c);
    const running = c.State === "running" || c.State?.Running === true;
    if (Array.isArray(c.Ports)) {
      c.Ports = c.Ports.filter((p) => !p.PublicPort);
      if (running) for (const [cport, arr] of Object.entries(pb)) for (const x of arr || []) {
        const [pp, type] = cport.split("/");
        c.Ports.push({ IP: x.HostIp || "0.0.0.0", PrivatePort: +pp, PublicPort: +x.HostPort, Type: type || "tcp" });
      }
    }
    if (c.HostConfig) c.HostConfig.PortBindings = pb;
    if (c.NetworkSettings && c.Config) {
      const ports = {};
      for (const k of Object.keys(c.Config.ExposedPorts || {})) ports[k] = null;
      if (running) for (const [cport, arr] of Object.entries(pb)) ports[cport] = (arr || []).map((x) => ({ HostIp: x.HostIp || "0.0.0.0", HostPort: String(x.HostPort) }));
      c.NetworkSettings.Ports = ports;
    }
    if (c.NetworkSettings?.Networks && this.labContainer) delete c.NetworkSettings.Networks[this.labContainer];
    return c;
  }
  /** Cổng publish của mọi container lab đang chạy → luật DNAT trong container lab. */
  async syncPorts() {
    const f = encodeURIComponent(JSON.stringify({ label: [`${LAB_LABEL}=${this.lab}`], status: ["running"] }));
    const list = (await up("GET", `/containers/json?filters=${f}`)).json ?? [];
    const rules = [];
    for (const c of list) {
      const j = (await up("GET", `/containers/${c.Id}/json`)).json;
      const ip = Object.values(j?.NetworkSettings?.Networks ?? {}).map((n) => n.IPAddress).find(Boolean);
      if (!ip) continue;
      for (const [cport, arr] of Object.entries(DockProxy.portsOf(j))) for (const x of arr || []) {
        const [pp, type] = cport.split("/");
        rules.push({ port: +x.HostPort, ip, cport: +pp, proto: type || "tcp" });
      }
    }
    await this.onPorts?.(rules);
    return rules;
  }
  /** Docker thật báo "port is already allocated" khi hai container giành một cổng: giữ đúng hành vi đó. */
  async portConflict(id) {
    const me = (await up("GET", `/containers/${encodeURI(id)}/json`)).json;
    const mine = Object.values(DockProxy.portsOf(me)).flat().map((x) => +x.HostPort);
    if (!mine.length) return null;
    const f = encodeURIComponent(JSON.stringify({ label: [`${LAB_LABEL}=${this.lab}`], status: ["running"] }));
    for (const c of (await up("GET", `/containers/json?filters=${f}`)).json ?? []) {
      if (c.Id === me.Id) continue;
      const used = Object.values(DockProxy.portsOf(c)).flat();
      const hit = used.find((x) => mine.includes(+x.HostPort));
      if (hit) return `driver failed programming external connectivity on endpoint ${me.Name.slice(1)}: Bind for ${hit.HostIp || "0.0.0.0"}:${hit.HostPort} failed: port is already allocated`;
    }
    return null;
  }
  async visibleImages() {
    const all = (await up("GET", "/images/json")).json ?? [];
    const cts = (await up("GET", `/containers/json?all=1&filters=${encodeURIComponent(JSON.stringify({ label: [`${LAB_LABEL}=${this.lab}`] }))}`)).json ?? [];
    const used = new Set(cts.map((c) => c.ImageID));
    return all.filter((i) => {
      if (this.hidden.has(i.Id)) return false;
      if (i.Labels?.[LAB_LABEL] === this.lab || used.has(i.Id)) return true;
      return (i.RepoTags || []).some((t) => this.images.has(t) || this.images.has(t.replace(/:latest$/, ""))) || this.images.has(i.Id);
    });
  }

  // -------- xử lý từng request
  async handle(req, res) {
    if (process.env.QL_DEBUG) console.error("dock", req.method, req.url);
    res.px = this.px;
    req.url = this.rewriteUrl(req.url);
    const url = new URL(req.url, "http://d");
    const ver = /^\/v[\d.]+/.exec(url.pathname)?.[0] ?? "";
    const p = url.pathname.slice(ver.length);
    const m = req.method;
    let seg = p.split("/").filter(Boolean).map(decodeURIComponent);

    // containers
    if (seg[0] === "containers") {
      if (seg[1] === "json" && m === "GET") {
        addLabelFilter(url, this.lab);
        const r = await up("GET", ver + "/containers/json?" + url.searchParams);
        return sendJson(res, r.status, Array.isArray(r.json) ? r.json.map((c) => this.fixHostIp(c)) : r.json);
      }
      if (seg[1] === "create" && m === "POST") {
        const body = JSON.parse((await readBody(req)).toString("utf8") || "{}");
        const err = await this.rewriteCreate(body);
        if (err) return deny(res, err);
        const origName = (url.searchParams.get("name") || "").split(this.px).join("");
        const eps = (body.NetworkingConfig ||= {}).EndpointsConfig ||= {};
        const nm = body.HostConfig?.NetworkMode;
        if (nm && !["default", "bridge", "host", "none"].includes(nm) && !nm.startsWith("container:") && !eps[nm]) eps[nm] = {};
        if (origName) for (const e of Object.values(eps)) e.Aliases = [...new Set([...(e.Aliases || []), origName])];
        const r = await up("POST", ver + "/containers/create?" + url.searchParams, body, { "Content-Type": "application/json" });
        return sendJson(res, r.status, r.json ?? {});
      }
      if (seg[1] === "prune" && m === "POST") { addLabelFilter(url, this.lab); return this.pass(req, res, ver + "/containers/prune?" + url.searchParams); }
      if (seg[1]) {
        const c = await this.ownContainer(seg[1]);
        if (!c) return notFound(res, "container", seg[1]);
        if (seg[2] === "json" && m === "GET") { const r = await up("GET", req.url); return sendJson(res, r.status, this.fixHostIp(r.json)); }
        if (["start", "restart", "unpause"].includes(seg[2]) && m === "POST") {
          const err = await this.portConflict(seg[1]);
          if (err) return sendJson(res, 500, { message: err });
          return this.pass(req, res, req.url, () => this.syncPorts().catch(() => {}));
        }
        if (seg[2] === "commit") {}
        return this.pass(req, res);
      }
    }
    if (seg[0] === "commit" && m === "POST") {
      const c = await this.ownContainer(url.searchParams.get("container") || "");
      if (!c) return notFound(res, "container", url.searchParams.get("container"));
      const repo = url.searchParams.get("repo"), tag = url.searchParams.get("tag") || "latest";
      if (repo) this.images.add(`${repo}:${tag}`);
      return this.pass(req, res, req.url, (j) => j?.Id && this.images.add(j.Id));
    }
    // images
    if (seg[0] === "images") {
      if (seg[1] === "json" && m === "GET") return sendJson(res, 200, await this.visibleImages());
      if (seg[1] === "create" && m === "POST") {
        const from = url.searchParams.get("fromImage"), tag = url.searchParams.get("tag");
        if (from) this.images.add(tag ? `${from}:${tag}` : from), this.images.add(from);
        return this.pass(req, res);
      }
      if (seg[1] === "prune" && m === "POST") return sendJson(res, 200, { ImagesDeleted: null, SpaceReclaimed: 0 });
      if (seg[1] === "load" && m === "POST") {      // kết quả của buildx --load: ghi nhận tên image vừa nạp
        return this.pass(req, res, req.url, (_j, text) => { for (const t of String(text).matchAll(/Loaded image(?: ID)?: ([^\\"\s]+)/g)) this.images.add(t[1]); });
      }
      if (seg[1] === "search") return this.pass(req, res);
      const name = seg.slice(1, seg.length - (["json", "history", "push", "tag", "get"].includes(seg.at(-1)) && seg.length > 2 ? 1 : 0)).join("/");
      const action = seg.length > 2 ? seg.at(-1) : (m === "DELETE" ? "delete" : "json");
      if (action === "tag" && m === "POST") { const r = url.searchParams.get("repo"); if (r) this.images.add(`${r}:${url.searchParams.get("tag") || "latest"}`); return this.pass(req, res); }
      if (action === "push" && m === "POST") {
        const host = name.includes("/") && /[.:]/.test(name.split("/")[0]) ? name.split("/")[0] : "docker.io";
        if (!/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host)) return deny(res, `push lên ${host} bị chặn trong lab (chỉ push vào registry cục bộ localhost:5000).`);
        return this.pass(req, res);
      }
      if (action === "delete" || m === "DELETE") {
        const r = await up("GET", `/images/${encodeURI(name)}/json`);
        if (r.status !== 200 || this.hidden.has(r.json?.Id)) return notFound(res, "image", name);
        const known = this.images.has(name) || this.images.has(name + ":latest") || (r.json.RepoTags || []).some((t) => this.images.has(t));
        const own = r.json?.Config?.Labels?.[LAB_LABEL] === this.lab || (known && !this.protected.has(r.json.Id));
        if (!own) {           // image có sẵn của máy: chỉ ẩn khỏi lab
          this.hidden.add(r.json.Id);
          return sendJson(res, 200, [{ Untagged: name }, { Deleted: r.json.Id }]);
        }
        return this.pass(req, res);
      }
      return this.pass(req, res);
    }
    // networks
    if (seg[0] === "networks") {
      if (seg.length === 1 && m === "GET") {
        const r = await up("GET", ver + "/networks?" + url.searchParams);
        return sendJson(res, r.status, (r.json || []).filter((n) => ["bridge", "host", "none"].includes(n.Name) || n.Labels?.[LAB_LABEL] === this.lab));
      }
      if (seg[1] === "create" && m === "POST") {
        const body = JSON.parse((await readBody(req)).toString("utf8") || "{}");
        body.Labels = this.labelsFor(body.Labels);
        if (body.Name) body.Name = this.enc(body.Name);
        const r = await up("POST", req.url, body, { "Content-Type": "application/json" });
        if (r.status < 300 && r.json?.Id) await this.joinNetwork(r.json.Id);
        return sendJson(res, r.status, r.json ?? {});
      }
      if (seg[1] === "prune") { addLabelFilter(url, this.lab); return this.pass(req, res, ver + "/networks/prune?" + url.searchParams); }
      if (seg[1] && m === "GET" && seg.length === 2) {
        if (!(await this.ownNetwork(seg[1], true))) return notFound(res, "network", seg[1]);
        const r = await up("GET", req.url);
        if (r.json?.Containers) for (const [k, v] of Object.entries(r.json.Containers)) if (v.Name === this.labContainer) delete r.json.Containers[k];
        if (r.json?.Containers && ["bridge"].includes(r.json.Name)) for (const [k, v] of Object.entries(r.json.Containers)) if (!(await this.ownContainer(k))) delete r.json.Containers[k];
        return sendJson(res, r.status, r.json);
      }
      if (seg[1] && m === "DELETE" && (await this.ownNetwork(seg[1], false))) {
        await up("POST", `/networks/${encodeURI(seg[1])}/disconnect`, { Container: this.labContainer, Force: true }, { "Content-Type": "application/json" }).catch(() => {});
        return this.pass(req, res);
      }
      if (seg[1] && !(await this.ownNetwork(seg[1], m === "GET" || seg[2] === "connect" || seg[2] === "disconnect"))) return notFound(res, "network", seg[1]);
      if (seg[2] === "connect" || seg[2] === "disconnect") {
        const body = JSON.parse((await readBody(req)).toString("utf8") || "{}");
        body.Container = this.enc(body.Container || "");
        if (!(await this.ownContainer(body.Container))) return notFound(res, "container", body.Container);
        const r = await up("POST", req.url, body, { "Content-Type": "application/json" });
        return r.buf.length ? sendJson(res, r.status, r.json ?? {}) : (res.writeHead(r.status), res.end());
      }
      return this.pass(req, res);
    }
    // volumes
    if (seg[0] === "volumes") {
      if (seg.length === 1 && m === "GET") { addLabelFilter(url, this.lab); const r = await up("GET", ver + "/volumes?" + url.searchParams); return sendJson(res, r.status, r.json); }
      if (seg[1] === "create" && m === "POST") {
        const body = JSON.parse((await readBody(req)).toString("utf8") || "{}");
        body.Labels = this.labelsFor(body.Labels);
        if (body.Name) body.Name = this.enc(body.Name);
        const r = await up("POST", req.url, body, { "Content-Type": "application/json" });
        return sendJson(res, r.status, r.json ?? {});
      }
      if (seg[1] === "prune") { addLabelFilter(url, this.lab); return this.pass(req, res, ver + "/volumes/prune?" + url.searchParams); }
      if (seg[1] && !(await this.ownVolume(seg[1]))) return notFound(res, "volume", seg[1]);
      if (seg[1] && m === "GET") { const r = await up("GET", req.url); return sendJson(res, r.status, r.json); }
      return this.pass(req, res);
    }
    if (seg[0] === "exec" || seg[0] === "_ping" || seg[0] === "version" || seg[0] === "info" || seg[0] === "events" || seg[0] === "auth" || seg[0] === "system" || seg[0] === "distribution") return this.pass(req, res);
    if (seg[0] === "build") {
      url.searchParams.set("labels", JSON.stringify(Object.assign(JSON.parse(url.searchParams.get("labels") || "{}"), this.labelsFor())));
      for (const t of url.searchParams.getAll("t")) this.images.add(t.includes(":") ? t : t + ":latest");
      return this.pass(req, res, ver + "/build?" + url.searchParams);
    }
    if (seg[0] === "build" || seg[0] === "session") return this.pass(req, res);
    return deny(res, `API ${m} ${p} chưa hỗ trợ trong lab.`);
  }

  /** Chuyển nguyên request (stream) tới engine; after(json?) chạy khi xong. */
  pass(req, res, path = req.url, after) {
    return new Promise((resolve) => {
      const headers = { ...req.headers };
      const u = http.request({ socketPath: UPSTREAM, method: req.method, path, headers }, (ur) => {
        if (ur.statusCode >= 400 && /json/.test(ur.headers["content-type"] || "")) {     // lỗi: bỏ tiền tố lab khỏi thông báo
          const eb = [];
          ur.on("data", (d) => eb.push(d));
          ur.on("end", () => { const t = Buffer.concat(eb).toString("utf8").split(this.px).join(""); const hd = { ...ur.headers, "content-length": Buffer.byteLength(t) }; res.writeHead(ur.statusCode, hd); res.end(t); resolve(); });
          return;
        }
        res.writeHead(ur.statusCode, ur.headers);
        res.flushHeaders();
        const chunks = after ? [] : null;
        ur.on("data", (d) => { chunks?.push(d); res.write(d); });
        ur.on("end", () => {
          res.end();
          if (after && ur.statusCode < 300) { let j = null; try { j = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch {} try { after(j, Buffer.concat(chunks).toString("utf8")); } catch {} }
          resolve();
        });
      });
      u.on("error", (e) => { try { sendJson(res, 502, { message: String(e.message) }); } catch {} resolve(); });
      req.pipe(u);
    });
  }

  /** attach / exec start (Upgrade: tcp): kiểm tra quyền rồi nối thẳng hai socket (gửi lại nguyên văn đầu request + thân). */
  async rawUpgrade(sock, headText, rest) {
    const [line0, ...hdrs] = headText.split("\r\n");
    const parts = line0.split(" ");
    parts[1] = this.rewriteUrl(parts[1] || "/");
    const line = parts.join(" ");
    headText = [line, ...hdrs].join("\r\n");
    const path = parts[1];
    if (process.env.QL_DEBUG) console.error("dock-up", line);
    const url = new URL(path, "http://d");
    const ver = /^\/v[\d.]+/.exec(url.pathname)?.[0] ?? "";
    const seg = url.pathname.slice(ver.length).split("/").filter(Boolean).map(decodeURIComponent);
    if (seg[0] === "containers" && !(await this.ownContainer(seg[1] || ""))) {
      sock.end("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 34\r\n\r\n{\"message\":\"No such container\"}\n");
      return;
    }
    const u = net.connect({ path: UPSTREAM, allowHalfOpen: true }, () => {
      u.write(Buffer.concat([Buffer.from(headText + "\r\n\r\n", "latin1"), rest]));
      u.pipe(sock); sock.pipe(u); sock.resume();
      if (seg[0] === "containers" && seg[2] === "attach") setTimeout(() => this.syncPorts().catch(() => {}), 1500);
    });
    u.on("error", () => sock.destroy());
    sock.on("error", () => u.destroy());
    u.on("close", () => sock.end());
  }
}

/** Xoá mọi thứ một lab đã tạo trên engine (container, network, volume, image tự dựng) và thư mục bản sao. */
export async function cleanupLab(lab, stage) {
  const f = encodeURIComponent(JSON.stringify({ label: [`${LAB_LABEL}=${lab}`] }));
  const cts = (await up("GET", `/containers/json?all=1&filters=${f}`).catch(() => ({ json: [] }))).json ?? [];
  await Promise.all(cts.map((c) => up("DELETE", `/containers/${c.Id}?force=1&v=1`).catch(() => {})));
  const nets = (await up("GET", `/networks?filters=${f}`).catch(() => ({ json: [] }))).json ?? [];
  await Promise.all(nets.map((n) => up("DELETE", `/networks/${n.Id}`).catch(() => {})));
  const vols = (await up("GET", `/volumes?filters=${f}`).catch(() => ({ json: {} }))).json?.Volumes ?? [];
  await Promise.all(vols.map((v) => up("DELETE", `/volumes/${encodeURIComponent(v.Name)}?force=1`).catch(() => {})));
  const imgs = (await up("GET", `/images/json?filters=${f}`).catch(() => ({ json: [] }))).json ?? [];
  await Promise.all(imgs.map((i) => up("DELETE", `/images/${i.Id}?force=1`).catch(() => {})));
  if (stage) try { rmSync(stage, { recursive: true, force: true }); } catch {}
}
/** Mọi tài nguyên của mọi lab (dọn khi khởi động lại app). */
export async function cleanupAllLabs() {
  const f = encodeURIComponent(JSON.stringify({ label: [`quantum-learn=1`] }));
  for (const [list, del, pick] of [["/containers/json?all=1&filters=" + f, (x) => `/containers/${x.Id}?force=1&v=1`, (j) => j],
    ["/networks?filters=" + f, (x) => `/networks/${x.Id}`, (j) => j], ["/volumes?filters=" + f, (x) => `/volumes/${encodeURIComponent(x.Name)}?force=1`, (j) => j?.Volumes]]) {
    const items = pick((await up("GET", list).catch(() => ({ json: null }))).json) ?? [];
    await Promise.all(items.map((x) => up("DELETE", del(x)).catch(() => {})));
  }
}
export { up as dockerApi };
