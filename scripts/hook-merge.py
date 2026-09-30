#!/usr/bin/env python3
"""Buddy 办公室：往 ~/.claude/settings.json 里加 / 删「跟着 Claude 自动打开」的那一条 SessionStart hook。

这是整个项目里唯一会修改 settings.json 的地方，而且只做这一件事：
  install    追加一个 matcher 组（startup|resume），命令是 `pgrep -xq BuddyOffice || open -g -b local.buddy-office …`
  uninstall  只删 command 里带 local.buddy-office 的 hook（组空了连组一起删），别的（比如 ccmon 的 hook）原样保留
  status     看看装没装（退出码 0 = 装了，1 = 没装）

每次改动之前：备份成 settings.json.bak-YYYYmmdd-HHMMSS；写到同目录的临时文件 → 重新读一遍校验 → os.replace 原子替换，保留原来的权限。
原文件不是合法 JSON：拒绝改，退出码 2。装两次不会有第二条。
用法：hook-merge.py install|uninstall|status [--settings 路径]（--settings 只给测试用）
"""
import json
import os
import sys
import time

MARK = "local.buddy-office"
COMMAND = "pgrep -xq BuddyOffice || open -g -b local.buddy-office >/dev/null 2>&1; exit 0"
GROUP = {"matcher": "startup|resume", "hooks": [{"type": "command", "command": COMMAND, "timeout": 5}]}


class Refuse(Exception):
    pass


def resolve(path):
    """~/.claude/settings.json 常常是指向 dotfiles 仓库的符号链接：改写必须落在链接指向的真实文件上（链接本身保持不变），
    否则 os.replace 换掉的是链接：链接变成普通文件，dotfiles 里真正的那份没加上 hook。
    链接指向的目录不存在就拒绝：不替用户凭空建出目录。"""
    if not os.path.islink(path):
        return path
    real = os.path.realpath(path)
    if not os.path.isdir(os.path.dirname(real)):
        raise Refuse("%s 是符号链接，但它指向的目录不存在（%s）。为了不弄乱你的目录结构，什么都没改。" % (path, real))
    return real


def load(path):
    """读 settings.json；不存在 = {}；不是合法 JSON 或不是对象 = 拒绝。"""
    if not os.path.exists(path):
        return {}, False
    with open(path, "rb") as f:
        raw = f.read()
    if not raw.strip():
        return {}, True
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e:
        raise Refuse("%s 不是合法的 JSON（%s）。为了不弄坏它，什么都没改。" % (path, e))
    if not isinstance(data, dict):
        raise Refuse("%s 的顶层不是一个 JSON 对象。为了不弄坏它，什么都没改。" % path)
    return data, True


def trailing_newline(path):
    """原文件末尾有没有换行：改写时保持原样（用户的 settings.json 没有末尾换行，我们也不该凭空加一个），新建的文件加一个。"""
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except OSError:
        return True
    return raw.endswith(b"\n") if raw.strip() else True


def has_mark(hook):
    return isinstance(hook, dict) and MARK in str(hook.get("command", ""))


def find_ours(data):
    """所有 command 里带 MARK 的 hook 的位置 [(事件名, 组下标, hook 下标)]。"""
    out = []
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return out
    for ev, groups in hooks.items():
        if not isinstance(groups, list):
            continue
        for gi, g in enumerate(groups):
            if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                for hi, h in enumerate(g["hooks"]):
                    if has_mark(h):
                        out.append((ev, gi, hi))
    return out


def create_private(path, mode, how):
    """按 mode 直接创建新文件（O_EXCL：不跟随已有的文件 / 链接；创建出来就是这个权限，不先按默认 umask 建成 0644 再 chmod）。"""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    return os.fdopen(fd, how, encoding="utf-8") if "b" not in how else os.fdopen(fd, how)


def backup(path, near=None):
    """备份成 <near>.bak-时间戳（near 默认就是 path 自己；path 是符号链接时 near 是链接，备份放在链接旁边，不往 dotfiles 仓库里丢文件）。"""
    if not os.path.exists(path):
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    base = near or path
    dst = "%s.bak-%s" % (base, stamp)
    n = 1
    while os.path.exists(dst):
        dst = "%s.bak-%s-%d" % (base, stamp, n)
        n += 1
    mode = os.stat(path).st_mode & 0o777
    with open(path, "rb") as s, create_private(dst, mode, "wb") as d:     # 直接按原文件的权限创建：不经过默认 umask 的 0644 中间状态（settings.json 里可能有 env 密钥）
        d.write(s.read())
    try:
        os.chmod(dst, mode)
    except OSError:
        pass
    return dst


def write_atomic(path, data, newline=True):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, ".%s.tmp-%d" % (os.path.basename(path), os.getpid()))
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600
    try:
        if os.path.lexists(tmp):
            os.remove(tmp)                                   # 上一次被打断留下的同名临时文件
        with create_private(tmp, mode, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            if newline:
                f.write("\n")
        os.chmod(tmp, mode)
        with open(tmp, "r", encoding="utf-8") as f:       # 重新读一遍校验
            again = json.load(f)
        if again != data:
            raise Refuse("写出的临时文件读回来和预期不一致，没有替换原文件。")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def install(link):
    path = resolve(link)
    data, existed = load(path)
    if find_ours(data):
        print("已经装过了（settings.json 里有 %s 的 hook），什么都没改。" % MARK)
        return 0
    hooks = data.setdefault("hooks", {}) if isinstance(data.get("hooks", {}), dict) else None
    if hooks is None:
        raise Refuse("settings.json 里的 hooks 不是对象，为了不弄坏它，什么都没改。")
    groups = hooks.setdefault("SessionStart", [])
    if not isinstance(groups, list):
        raise Refuse("settings.json 里的 hooks.SessionStart 不是数组，为了不弄坏它，什么都没改。")
    nl = trailing_newline(path)
    b = backup(path, near=link)
    groups.append(json.loads(json.dumps(GROUP)))
    write_atomic(path, data, nl)
    print("已添加 SessionStart hook。" + ("备份：%s" % b if b else "（原来没有 settings.json，是新建的）"))
    return 0


def uninstall(link):
    path = resolve(link)
    data, existed = load(path)
    locs = find_ours(data)
    if not locs:
        print("settings.json 里没有 %s 的 hook，什么都没改。" % MARK)
        return 0
    nl = trailing_newline(path)
    b = backup(path, near=link)
    hooks = data["hooks"]
    touched = set()
    for ev in {l[0] for l in locs}:
        new_groups = []
        for g in hooks[ev]:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                kept = [h for h in g["hooks"] if not has_mark(h)]
                if len(kept) != len(g["hooks"]):
                    touched.add(ev)
                    if not kept:
                        continue                       # 组空了：连组一起删
                    g = dict(g); g["hooks"] = kept
            new_groups.append(g)
        hooks[ev] = new_groups
        if not new_groups:
            del hooks[ev]                               # 事件下面一个组都不剩：这一项是我们加的，一起清掉
    if not hooks:
        del data["hooks"]
    write_atomic(path, data, nl)
    print("已删除 SessionStart hook。备份：%s" % b)
    return 0


def status(link):
    data, _ = load(resolve(link))
    ok = bool(find_ours(data))
    print("已安装" if ok else "未安装")
    return 0 if ok else 1


def main(argv):
    args = list(argv[1:])
    path = os.path.expanduser("~/.claude/settings.json")
    if "--settings" in args:
        i = args.index("--settings")
        path = args[i + 1]
        del args[i:i + 2]
    if not args or args[0] not in ("install", "uninstall", "status"):
        print(__doc__)
        return 64
    try:
        return {"install": install, "uninstall": uninstall, "status": status}[args[0]](path)
    except Refuse as e:
        print("拒绝：%s" % e, file=sys.stderr)
        return 2
    except OSError as e:
        print("出错：%s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
