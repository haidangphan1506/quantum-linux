// Docker trong lab (qua engine Kiri thật, giới hạn bởi dockproxy.mjs):
//   provision: dựng các container mà bài mô phỏng có sẵn (postgres, redis, tutor-api…) thành container thật
//   bridge   : trạng thái docker thật → W.containers / W.images / W.volumes / W.dockerGroup / W.dockerLogin
import { execFile } from "node:child_process";
import { dirname, posix } from "node:path";
import { LAB_LABEL, dockerApi } from "./dockproxy.mjs";

const run = (args, { timeout = 600000, sock } = {}) => new Promise((resolve, reject) =>
  execFile("docker", args, { encoding: "utf8", timeout, maxBuffer: 32 * 1024 * 1024, env: sock ? { ...process.env, DOCKER_HOST: "unix://" + sock } : process.env },
    (e, out, err) => (e ? reject(Object.assign(e, { stderr: err })) : resolve(out))));

const STUB_NAMES = /^(tutor-[a-z0-9-]+)(:|$)/;     // image hư cấu của khoá học → image giả nhỏ dựng tại chỗ

async function hasImage(img) { try { await run(["image", "inspect", img], { timeout: 20000 }); return true; } catch { return false; } }

/** Image giả cho ứng dụng của khoá học: busybox httpd trả /, /health, /api/* (hoặc worker chỉ ngủ). */
async function makeStub(img) {
  const worker = /worker/.test(img);
  if (!(await hasImage("alpine:latest"))) await run(["pull", "alpine:latest"]);
  const tmp = "ql-stub-build-" + Date.now().toString(36);
  const prep = "apk add --no-cache -q busybox-extras >/dev/null && adduser -D -h /app node && mkdir -p /app/dist && printf '{\"name\":\"tutor-api\",\"version\":\"1.0.0\"}' > /app/package.json && printf 'console.log(1)' > /app/dist/main.js && chown -R node /app"
    + " && mkdir -p /www/api /www/healthz && printf '{\"status\":\"ok\"}' > /www/health && printf '{\"status\":\"ok\"}' > /www/healthz/index.html"
    + " && printf '<!doctype html><title>Tutor</title><h1>Tutor</h1>' > /www/index.html && printf '{\"ok\":true}' > /www/api/index.html";
  await run(["run", "--name", tmp, "alpine:latest", "sh", "-c", prep]);
  const cmd = worker ? '["sh","-c","echo worker started; while sleep 3600; do :; done"]'
    : '["sh","-c","echo \\"listening on ${PORT}\\"; exec busybox-extras httpd -f -v -p 0.0.0.0:${PORT} -h /www"]';
  await run(["commit", "--change", "LABEL ql.stub=1", "--change", "ENV PORT=3000", "--change", "USER node", "--change", "WORKDIR /app", "--change", `CMD ${cmd}`, tmp, img]);
  await run(["rm", "-f", tmp]).catch(() => {});
}
const imageLocks = new Map();     // nhiều lab cùng dựng/kéo một image ⇒ chỉ làm một lần
export function ensureLabImage(img, note) {
  if (!imageLocks.has(img)) {
    imageLocks.set(img, (async () => {
      if (await hasImage(img)) return;
      if (STUB_NAMES.test(img)) return makeStub(img);
      note?.(`Đang tải image ${img} (lần đầu)…`);
      await run(["pull", img]);
    })().finally(() => imageLocks.delete(img)));
  }
  return imageLocks.get(img);
}

/** Thư mục làm việc của một project compose trong hệ file mô phỏng (thư mục chứa docker-compose.yml). */
function projectDir(simSh, proj) {
  const n = simSh.fs.n;
  const files = Object.keys(n).filter((p) => /\/(docker-)?compose\.ya?ml$/.test(p) && n[p].t === "f");
  return dirname(files.find((p) => posix.basename(dirname(p)) === proj) ?? files[0] ?? simSh.home + "/" + proj);
}

/** Dựng các container có sẵn của bài, đi QUA proxy của lab (nhãn, cổng, bind mount xử lý giống lệnh người học). */
export async function provisionDocker(simSh, ctx) {
  const W = simSh.W;
  const cts = (W?.containers ?? []).filter((c) => c && c.name && c.image);
  if (!cts.length) return;
  const sock = ctx.proxy.sock;
  const d = (args, o = {}) => run(args, { ...o, sock });
  const nets = new Set(), vols = new Set();
  for (const c of cts) await ensureLabImage(c.image, ctx.note);
  for (const c of cts) {
    ctx.proxy.images.add(c.image);
    const proj = c.proj || null;
    const dir = proj ? projectDir(simSh, proj) : null;
    const compose = proj ? ["--label", `com.docker.compose.project=${proj}`, "--label", `com.docker.compose.service=${c.svc || c.name}`,
      "--label", "com.docker.compose.container-number=1", "--label", "com.docker.compose.oneoff=False",
      "--label", `com.docker.compose.project.working_dir=${dir}`, "--label", `com.docker.compose.project.config_files=${dir}/docker-compose.yml`] : [];
    const args = ["run", "-d", "--name", c.name, ...compose];
    if (proj) {
      const net = `${proj}_default`;
      if (!nets.has(net)) {
        nets.add(net);
        await d(["network", "create", "--label", `com.docker.compose.project=${proj}`, "--label", "com.docker.compose.network=default", net]).catch(() => {});
      }
      args.push("--network", net, "--network-alias", c.svc || c.name);
    }
    const env = Object.assign({}, c.env || {});
    const firstCont = (c.ports || [])[0]?.cont;
    if (STUB_NAMES.test(c.image) && !env.PORT) env.PORT = String(firstCont || 3000);
    for (const [k, v] of Object.entries(env)) args.push("-e", `${k}=${v}`);
    for (const p of c.ports || []) if (p.host && p.cont) args.push("-p", `${p.bind && p.bind !== "0.0.0.0" ? p.bind + ":" : ""}${p.host}:${p.cont}`);
    if (c.restartPolicy && c.restartPolicy !== "no") args.push("--restart", c.restartPolicy);
    if (c.memMB) args.push("--memory", `${c.memMB}m`);
    for (const v of c.svcCfg?.volumes ?? []) {
      const parts = String(v).split(":");
      const [src, dst] = parts;
      if (!dst) continue;
      if (/^[A-Za-z0-9][\w.-]*$/.test(src)) {
        const vn = proj ? `${proj}_${src}` : src;
        if (!vols.has(vn)) {
          vols.add(vn);
          await d(["volume", "create", ...(proj ? ["--label", `com.docker.compose.project=${proj}`, "--label", `com.docker.compose.volume=${src}`] : []), vn]).catch(() => {});
        }
        args.push("-v", `${vn}:${dst}`);
      } else {
        parts[0] = posix.resolve(dir ?? simSh.home, src);         // proxy chép thư mục này từ container lab
        args.push("-v", parts.join(":"));
      }
    }
    args.push(c.image);
    try {
      await d(args, { timeout: 120000 });
      if (c.state === "exited" || c.state === "created") await d(["stop", "-t", "1", c.name]).catch(() => {});
    } catch (e) {
      const msg = String(e.stderr || e.message).split("\n").find((x) => /error|failed|denied|conflict/i.test(x)) || e.message;
      ctx.note?.(`Không dựng được container ${c.name}: ${msg.trim().slice(0, 300)}`);
    }
  }
}

/** Trạng thái thật → mô hình docker của khoá học. */
export async function bridgeDocker(simSh, proxy, nodes, user) {
  const W = simSh.W;
  if (!W || !proxy) return;
  const f = encodeURIComponent(JSON.stringify({ label: [`${LAB_LABEL}=${proxy.lab}`] }));
  const list = (await dockerApi("GET", `/containers/json?all=1&filters=${f}`)).json ?? [];
  const old = W.containers ?? [];
  const next = [];
  for (const it of list) {
    const r = await dockerApi("GET", `/containers/${it.Id}/json`);
    const j = r.json;
    if (!j) continue;
    proxy.fixHostIp(j);
    const name = j.Name.replace(/^\//, "").split(proxy.px).join("");
    const prev = old.find((c) => c.name === name) ?? {};
    const env = {};
    for (const e of j.Config?.Env ?? []) { const i = e.indexOf("="); env[e.slice(0, i)] = e.slice(i + 1); }
    const ports = [];
    for (const [cport, arr] of Object.entries(j.HostConfig?.PortBindings ?? {})) {
      for (const b of arr || []) ports.push({ bind: b.HostIp || "0.0.0.0", host: +b.HostPort, cont: parseInt(cport, 10) });
    }
    const L = j.Config?.Labels ?? {};
    const netsObj = j.NetworkSettings?.Networks ?? {};
    next.push(Object.assign({}, prev, {
      id: j.Id.slice(0, 12), name, image: j.Config?.Image, state: j.State?.Status, status: it.Status,
      exitCode: j.State?.ExitCode ?? 0, ports, env,
      restartPolicy: j.HostConfig?.RestartPolicy?.Name || "no",
      memMB: j.HostConfig?.Memory ? Math.round(j.HostConfig.Memory / 1048576) : null,
      proj: L["com.docker.compose.project"] ?? prev.proj, svc: L["com.docker.compose.service"] ?? prev.svc,
      nets: Object.keys(netsObj).map((n) => n.split(proxy.px).join("")), ip: Object.values(netsObj)[0]?.IPAddress ?? prev.ip,
      health: j.State?.Health?.Status ?? null, portErr: null,
    }));
  }
  W.containers = next;
  const imgs = await proxy.visibleImages();
  const prevImgs = Array.isArray(W.images) ? W.images : [];
  W.images = imgs.flatMap((i) => (i.RepoTags?.length ? i.RepoTags : ["<none>:<none>"]).map((t) => {
    const k = t.lastIndexOf(":");
    const repo = t.slice(0, k), tag = t.slice(k + 1);
    const prev = prevImgs.find((x) => x.repo === repo && x.tag === tag) ?? {};
    return Object.assign({}, prev, { repo, tag, id: i.Id.replace(/^sha256:/, "").slice(0, 12), size: Math.round(i.Size / 1e6) + "MB" });
  }));
  const vols = (await dockerApi("GET", `/volumes?filters=${f}`)).json?.Volumes ?? [];
  W.volumes = vols.map((v) => v.Name.split(proxy.px).join(""));
  // nhóm docker và đăng nhập registry: đọc từ hệ file thật của lab
  const grp = String(nodes["/etc/group"]?.c ?? "").split("\n").find((l) => l.startsWith("docker:"));
  if (grp != null) W.dockerGroup = grp.split(":")[3]?.split(",").includes(user) || user === "root";
  const home = user === "root" ? "/root" : "/home/" + user;
  try {
    const cfg = JSON.parse(nodes[home + "/.docker/config.json"]?.c ?? "{}");
    const auths = Object.keys(cfg.auths ?? {});
    if (auths.length) W.dockerLogin = auths[0].replace(/^https?:\/\//, "").replace(/\/v1\/?$/, "").replace(/^index\.docker\.io$/, "docker.io");
  } catch {}
}
