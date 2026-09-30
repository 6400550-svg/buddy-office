#!/usr/bin/env python3
"""replay 长跑的数据发生器（QA ②）：往一个**假的 home 树**里持续写「像真的一样」的会话数据，让开发版 App（`--data-root <root>`）读 30 分钟以上。

和 `buddyctl replay`（虚拟时钟、一次性、逐步断言）互补：这里是真实时钟、持续、带噪声，看的是长时间运行里 CPU / 内存 / 句柄有没有漂。

  假 home 里有：
    .claude/sessions/<pid>.json          活会话登记表（pid 是真的 `sleep` 子进程，杀掉它 = 进程被回收）
    .claude/.monitor/<sid>.events.jsonl  hook 事件流（UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop）
    .claude/projects/-soak/<sid>.jsonl   会话记录（assistant + usage + tool_use、用户 prompt、custom-title）
    Library/Application Support/Claude/claude-code-sessions/acct/org/local_<uuid>.json   桌面 App 的元数据
  会话生命周期：空闲 → 忙（一串工具）→ 偶尔等批准 → 做完 → 空闲…；每个会话活 5–15 分钟后进程被杀（一半留下过期的登记表），
  过一会儿「同一个身份回来」（resume：同一个 hostSessionId）或 `/clear`（同一个 host、新 sessionId）；还有终端会话（没有 hostSessionId）的进出场。
  速率：默认一个忙着的会话每 2–8 秒一次工具调用（接近真实的 Claude）；--stress 是 0.4–3 秒（压力档）。
  噪声：约 1% 的写入是坏数据（写到一半的行、随机字节、非法 UTF-8、空行），偶尔一行 200 KB 的超长行。
  蜜罐（任务书的安全红线：绝不打开 .key、绝不连 .sock）：每个会话在 sessions/ 里放
       ① 名字形如 `<pid>.<sha>.key` 的普通文件（写好之后把 atime 设成等于 mtime；APFS 在「atime ≤ mtime」时第一次读会把 atime 推进——
          所以只要有人读过它，atime > mtime，一次就抓得到），外加大写扩展名的 `.KEY` 一份；
       ② 名字形如 `<pid>.<sha>.fifo.key` 的 FIFO：后台线程每 200 ms 尝试非阻塞地以写方式打开它，只有 App 以读方式（阻塞式 open 会一直等在那里）
          打开了它才会成功；
       ③ 一个 `.sock` 的真 unix socket 监听，有人 connect 就记录。
       任何一项被碰到都记为违规（report.violations）。

用法：python3 QA/tools/replay_soak.py --root /private/tmp/bosoak/home --minutes 35 [--sessions 8] [--seed 1] [--report report.json]
      （root 必须是空目录或不存在的目录，绝不往真实的 home 里写；要在沙箱外跑。）
"""
import argparse, errno, hashlib, json, os, random, shutil, signal, socket, subprocess, sys, threading, time, uuid


def now_ms():
    return int(time.time() * 1000)


def iso(t=None):
    t = time.time() if t is None else t
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.c = {"registry_writes": 0, "hook_events": 0, "transcript_lines": 0, "garbage_lines": 0, "huge_lines": 0,
                  "sessions_started": 0, "sessions_killed": 0, "resumes": 0, "clears": 0, "honeypot_key_opened": 0, "honeypot_sock_connected": 0}
        self.violations = []

    def add(self, k, n=1):
        with self.lock:
            self.c[k] = self.c.get(k, 0) + n

    def violation(self, what):
        with self.lock:
            self.violations.append({"t": time.strftime("%H:%M:%S"), "what": what})


class Honeypots(threading.Thread):
    """FIFO / socket 蜜罐：检测 App 有没有打开 .key、连接 .sock。"""

    def __init__(self, stats):
        super().__init__(daemon=True)
        self.stats = stats
        self.fifos = []
        self.files = {}                 # 路径 -> 是否已经报过
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.socks = []

    def add_file(self, path):
        try:
            with open(path, "w") as f:
                f.write("HONEYPOT-DO-NOT-READ\n")
            st = os.stat(path)
            os.utime(path, (st.st_mtime, st.st_mtime))          # atime = mtime
            with self.lock:
                self.files[path] = False
        except OSError:
            pass

    def add_fifo(self, path):
        try:
            if os.path.exists(path):
                os.unlink(path)
            os.mkfifo(path)
            with self.lock:
                self.fifos.append(path)
        except OSError:
            pass

    def add_socket(self, path):
        try:
            if os.path.exists(path):
                os.unlink(path)
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.bind(path)
            s.listen(4)
            s.settimeout(0.05)
            self.socks.append((path, s))
        except OSError as e:
            self.stats.violation("socket 蜜罐建不起来（路径太长？）：%s %s" % (path, e))

    def run(self):
        while not self.stop.is_set():
            with self.lock:
                fifos = list(self.fifos)
                files = [p for p, seen in self.files.items() if not seen]
            for p in files:
                try:
                    st = os.stat(p)
                    if st.st_atime > st.st_mtime:
                        with self.lock:
                            self.files[p] = True
                        self.stats.add("honeypot_key_opened")
                        self.stats.violation("有人读了 .key 蜜罐文件（atime 被推进）：%s" % p)
                except OSError:
                    pass
            for p in fifos:
                try:
                    fd = os.open(p, os.O_WRONLY | os.O_NONBLOCK)      # 没有读者：ENXIO；有读者（App 打开了它）：成功
                    os.close(fd)
                    self.stats.add("honeypot_key_opened")
                    self.stats.violation("有人以读方式打开了 .key 蜜罐：%s" % p)
                    time.sleep(1)
                except OSError as e:
                    if e.errno not in (errno.ENXIO, errno.ENOENT):
                        pass
            for p, s in self.socks:
                try:
                    c, _ = s.accept()
                    c.close()
                    self.stats.add("honeypot_sock_connected")
                    self.stats.violation("有人连接了 .sock 蜜罐：%s" % p)
                except (socket.timeout, OSError):
                    pass
            time.sleep(0.2)


class Session:
    TOOLS = [("Read", "/soak/src/File{n}.swift"), ("Grep", "TODO{n}"), ("Glob", "**/*.swift"), ("Edit", "/soak/src/Edit{n}.swift"),
             ("Write", "/soak/src/New{n}.swift"), ("Bash", "npm test -- --watch {n}"), ("WebFetch", "https://example.com/p/{n}"),
             ("WebSearch", "soak query {n}"), ("TodoWrite", ""), ("Agent", "research {n}"), ("mcp__notion__search_pages", "")]

    def __init__(self, world, idx, kind="desktop"):
        self.w = world
        self.idx = idx
        self.kind = kind
        self.rng = random.Random(world.seed * 1000 + idx)
        self.host = "local_" + str(uuid.UUID(int=self.rng.getrandbits(128)))
        self.title = "soak-%d" % idx
        self.sid = None
        self.proc = None
        self.pid = None
        self.state = "gone"
        self.next_t = time.time() + self.rng.uniform(0, 5)
        self.busy_until = 0
        self.wait_until = 0
        self.dies_at = 0
        self.n = 0
        self.tool_call = 0
        self.msg = 0
        self.stale = None

    # ---- 文件 ----
    def reg_path(self):
        return os.path.join(self.w.sessions, "%d.json" % self.pid)

    def write_registry(self, status):
        t = now_ms()
        reg = {"pid": self.pid, "sessionId": self.sid, "cwd": "/soak/proj%d" % self.idx, "startedAt": self.started, "version": "2.1.284",
               "kind": "interactive", "entrypoint": "claude-desktop" if self.kind == "desktop" else "cli",
               "name": self.title, "status": status, "updatedAt": t, "statusUpdatedAt": t}
        if self.kind == "desktop":
            reg["hostSessionId"] = self.host
        tmp = self.reg_path() + ".tmp"
        with open(tmp, "w") as f:
            json.dump(reg, f)
        os.replace(tmp, self.reg_path())
        self.w.stats.add("registry_writes")

    def hook(self, ev, tool="", detail="", extra=""):
        line = json.dumps({"ts": now_ms(), "ev": ev, "tool": tool, "detail": detail, "extra": extra})
        self.w.append(os.path.join(self.w.monitor, self.sid + ".events.jsonl"), line + "\n", "hook_events")

    def transcript(self, obj):
        self.w.append(os.path.join(self.w.projects, self.sid + ".jsonl"), json.dumps(obj) + "\n", "transcript_lines")

    def assistant(self, blocks, stop_reason, usage):
        self.msg += 1
        self.transcript({"type": "assistant", "uuid": str(uuid.uuid4()), "timestamp": iso(), "sessionId": self.sid, "isSidechain": False,
                         "message": {"id": "msg_%d_%d" % (self.idx, self.msg), "model": "claude-opus-5-5", "role": "assistant", "type": "message",
                                     "content": blocks, "stop_reason": stop_reason, "usage": usage}})

    def usage(self):
        r = self.rng
        return {"input_tokens": r.randint(1, 30), "output_tokens": r.randint(20, 900), "cache_creation_input_tokens": r.randint(0, 4000),
                "cache_read_input_tokens": r.randint(20000, 120000)}

    def write_desktop_meta(self):
        if self.kind != "desktop":
            return
        p = os.path.join(self.w.meta_dir, self.host + ".json")
        meta = {"sessionId": self.host, "cliSessionId": self.sid, "cwd": "/soak/proj%d" % self.idx, "title": self.title,
                "lastActivityAt": now_ms(), "isArchived": False}
        with open(p, "w") as f:
            json.dump(meta, f)

    # ---- 生命周期 ----
    def start(self, resume=False, clear=False):
        self.proc = subprocess.Popen(["/bin/sleep", "100000"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.pid = self.proc.pid
        if clear or self.sid is None:
            self.sid = str(uuid.UUID(int=self.rng.getrandbits(128)))
            self.msg = 0
        self.started = now_ms()
        self.state = "idle"
        self.next_t = time.time() + self.rng.uniform(2, 15)
        self.dies_at = time.time() + self.rng.uniform(300, 900)
        self.write_registry("idle")
        self.write_desktop_meta()
        self.transcript({"type": "custom-title", "customTitle": self.title, "sessionId": self.sid})
        # 蜜罐：<pid>.<sha>.key（FIFO）、大写扩展名的一份
        sha = hashlib.sha256(("%d" % self.pid).encode()).hexdigest()
        self.w.honey.add_file(os.path.join(self.w.sessions, "%d.%s.key" % (self.pid, sha)))
        self.w.honey.add_file(os.path.join(self.w.sessions, "%d.%s.KEY" % (self.pid, sha[:8])))
        self.w.honey.add_fifo(os.path.join(self.w.sessions, "%d.%s.fifo.key" % (self.pid, sha[:16])))
        self.w.stats.add("sessions_started")
        if resume:
            self.w.stats.add("resumes")
        if clear:
            self.w.stats.add("clears")

    def kill(self):
        if self.proc:
            try:
                self.proc.kill()
                self.proc.wait(timeout=2)
            except Exception:
                pass
        self.w.stats.add("sessions_killed")
        # 一半的会话留下过期的登记表（进程没了但文件还在），一半清理干净
        if self.rng.random() < 0.5:
            try:
                os.unlink(self.reg_path())
            except OSError:
                pass
        self.state = "gone"
        self.next_t = time.time() + self.rng.uniform(20, 90)

    def tick(self):
        t = time.time()
        if t < self.next_t:
            return
        r = self.rng
        if self.state == "gone":
            if self.kind == "terminal" and r.random() < 0.5:
                self.sid = None                            # 终端会话：换一个全新的身份
                self.host = "none"
            self.start(resume=self.sid is not None and self.kind == "desktop", clear=self.kind == "desktop" and r.random() < 0.3)
            return
        if t >= self.dies_at and self.state in ("idle",):
            self.kill()
            return
        if self.state == "idle":
            # 新一轮：用户 prompt
            self.state = "busy"; self.busy_until = t + r.uniform(*self.w.busy_range)
            self.write_registry("busy")
            self.hook("UserPromptSubmit")
            self.transcript({"type": "user", "uuid": str(uuid.uuid4()), "timestamp": iso(), "sessionId": self.sid, "isSidechain": False,
                             "message": {"role": "user", "content": "soak prompt %d" % self.n}})
            self.next_t = t + r.uniform(0.3, 1.5)
        elif self.state == "busy":
            if t >= self.busy_until:
                self.hook("Stop")
                self.assistant([{"type": "text", "text": "done"}], "end_turn", self.usage())
                self.state = "idle"; self.write_registry("idle")
                self.next_t = t + r.uniform(*self.w.idle_range)
                return
            name, detail = r.choice(self.TOOLS)
            detail = detail.format(n=self.n)
            self.n += 1; self.tool_call += 1
            tid = "toolu_%d_%d" % (self.idx, self.tool_call)
            self.assistant([{"type": "tool_use", "id": tid, "name": name, "input": {"command": detail, "file_path": detail}}], "tool_use", self.usage())
            self.hook("PreToolUse", name, detail)
            if r.random() < self.w.wait_prob:              # 等批准
                self.state = "waiting"; self.wait_until = t + r.uniform(4, 25)
                self.hook("Notification", "", "Claude needs your permission to use %s" % name)
                self.write_registry("waiting")
                self.next_t = t + 1
            else:
                self.hook("PostToolUse", name, detail, "len=%d" % r.randint(10, 5000))
                self.next_t = t + r.uniform(*self.w.tool_interval)
        elif self.state == "waiting":
            if t >= self.wait_until:
                self.state = "busy"; self.write_registry("busy")
                self.hook("PostToolUse", "Bash", "approved", "len=10")
            self.next_t = t + 1


class World:
    def __init__(self, root, n, seed, tool_interval=(2.0, 8.0), wait_prob=0.06, calm=False):
        self.root = root; self.seed = seed
        self.busy_range = (60, 300) if calm else (20, 120)   # 一轮忙多久（秒）：真实的一轮常常是 1–5 分钟；默认档压缩了，提醒会密得多
        self.idle_range = (30, 180) if calm else (8, 60)      # 做完之后空闲多久（秒）
        self.wait_prob = wait_prob                     # 每次工具调用有多大概率变成「等批准」（默认 6%：每约 16 秒一次提醒，远比真实用法密）
        self.tool_interval = tool_interval             # 一个忙着的会话两次工具调用之间的间隔（秒）：真实的 Claude 大约每 2–8 秒一次；压力档 0.4–3
        self.sessions = os.path.join(root, ".claude", "sessions")
        self.monitor = os.path.join(root, ".claude", ".monitor")
        self.projects = os.path.join(root, ".claude", "projects", "-soak")
        self.meta_dir = os.path.join(root, "Library", "Application Support", "Claude", "claude-code-sessions", "acct", "org")
        for d in (self.sessions, self.monitor, self.projects, self.meta_dir):
            os.makedirs(d)
        self.stats = Stats()
        self.honey = Honeypots(self.stats)
        self.rng = random.Random(seed)
        self.files = {}
        self.sess = [Session(self, i, "terminal" if i >= n - 2 else "desktop") for i in range(n)]

    def append(self, path, text, counter):
        """追加一行；约 1% 是坏数据。"""
        r = self.rng.random()
        data = text.encode()
        if r < 0.004:
            data = data[: max(1, len(data) // 2)]                        # 写到一半的行（没有换行；下一次写入会和它粘成一行坏数据）
            self.stats.add("garbage_lines")
        elif r < 0.007:
            data = bytes(self.rng.getrandbits(8) for _ in range(self.rng.randint(1, 200))) + b"\n"
            self.stats.add("garbage_lines")
        elif r < 0.009:
            data = b'{"type":"assistant","message":"\xff\xfe\xc3\x28 invalid utf8"}\n'
            self.stats.add("garbage_lines")
        elif r < 0.010:
            data = b"\n"
            self.stats.add("garbage_lines")
        elif r < 0.0102:
            data = b'{"type":"assistant","x":"' + b"A" * 200_000 + b'"}\n'
            self.stats.add("huge_lines")
        try:
            with open(path, "ab") as f:
                f.write(data)
            self.stats.add(counter)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--minutes", type=float, default=35)
    ap.add_argument("--sessions", type=int, default=8)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--report", default=None)
    ap.add_argument("--wait-prob", type=float, default=0.06, help="每次工具调用变成「等批准」的概率（默认 0.06：8 个会话时大约每 16 秒一次提醒 + 提示音，比真实用法密得多）")
    ap.add_argument("--calm", action="store_true", help="接近真实用法的节奏：一轮忙 1–5 分钟、做完空闲 0.5–3 分钟（默认档压缩成 20–120 秒 / 8–60 秒，「做完了」提醒每几秒一次）")
    ap.add_argument("--stress", action="store_true", help="压力档：工具调用间隔 0.4–3 秒（默认 2–8 秒，接近真实的 Claude）")
    a = ap.parse_args()
    if os.path.exists(a.root) and os.listdir(a.root):
        sys.exit("--root 必须是空目录或不存在的目录：%s" % a.root)
    if os.path.realpath(a.root).startswith(os.path.realpath(os.path.expanduser("~/.claude"))):
        sys.exit("拒绝往 ~/.claude 里写")
    w = World(a.root, a.sessions, a.seed, (0.4, 3.0) if a.stress else (2.0, 8.0), a.wait_prob, a.calm)
    sock_path = os.path.join(w.sessions, "9999.sock")
    w.honey.add_socket(sock_path)
    w.honey.start()
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    print("replay_soak 开始 root=%s sessions=%d minutes=%.1f pid=%d" % (a.root, a.sessions, a.minutes, os.getpid()), flush=True)
    t0 = time.time(); last = 0
    try:
        while time.time() - t0 < a.minutes * 60 and not stop.is_set():
            for s in w.sess:
                s.tick()
            time.sleep(0.05)
            if time.time() - last >= 30:
                last = time.time()
                with w.stats.lock:
                    c = dict(w.stats.c)
                print("[%4ds] %s violations=%d" % (last - t0, json.dumps(c, ensure_ascii=False), len(w.stats.violations)), flush=True)
    finally:
        w.honey.stop.set()
        for s in w.sess:
            if s.proc:
                try:
                    s.proc.kill()
                except Exception:
                    pass
        report = {"seconds": time.time() - t0, "counters": w.stats.c, "violations": w.stats.violations}
        print("replay_soak 结束：" + json.dumps(report, ensure_ascii=False), flush=True)
        if a.report:
            with open(a.report, "w") as f:
                json.dump(report, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
