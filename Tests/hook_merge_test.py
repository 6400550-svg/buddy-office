#!/usr/bin/env python3
"""scripts/hook-merge.py 的测试：装两次只有一条、卸载后别人的 hook 原样不动、非法 JSON 拒绝且不留痕迹、权限保留。
运行：python3 Tests/hook_merge_test.py"""
import copy
import glob
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("hook_merge", os.path.join(HERE, "..", "scripts", "hook-merge.py"))
hm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hm)

CCMON = {"type": "command", "command": "$HOME/.claude/monitor/hook.sh", "timeout": 5}
REALISTIC = {
    "model": "opus",
    "theme": "dark",
    "hooks": {
        "SessionStart": [{"hooks": [CCMON]}],
        "SessionEnd": [{"hooks": [CCMON]}],
        "PreToolUse": [{"matcher": "*", "hooks": [CCMON]}],
        "Stop": [{"hooks": [CCMON]}],
    },
    "statusLine": {"type": "command", "command": "sh ~/.claude/statusline.sh 中文"},
}


def run(*args):
    return hm.main(["hook-merge.py", *args])


def rb(path):
    with open(path, "rb") as f:
        return f.read()


class HookMergeTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="hm-test-")
        self.path = os.path.join(self.dir, "settings.json")

    def write(self, obj, mode=0o600):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, ensure_ascii=False)
        os.chmod(self.path, mode)

    def read(self):
        with open(self.path, encoding="utf-8") as f:
            return json.load(f)

    def backups(self):
        return sorted(glob.glob(self.path + ".bak-*"))

    def test_install_creates_file_when_missing(self):
        self.assertEqual(run("install", "--settings", self.path), 0)
        d = self.read()
        self.assertEqual(d["hooks"]["SessionStart"], [hm.GROUP])
        self.assertEqual(self.backups(), [])            # 原来没有文件，没什么可备份的

    def test_install_appends_one_group_and_keeps_everything_else(self):
        self.write(REALISTIC)
        self.assertEqual(run("install", "--settings", self.path), 0)
        d = self.read()
        groups = d["hooks"]["SessionStart"]
        self.assertEqual(len(groups), 2)
        self.assertEqual(groups[0], REALISTIC["hooks"]["SessionStart"][0])       # ccmon 那组原样
        self.assertEqual(groups[1]["matcher"], "startup|resume")
        self.assertEqual(groups[1]["hooks"][0]["command"], "pgrep -xq BuddyOffice || open -g -b local.buddy-office >/dev/null 2>&1; exit 0")
        self.assertEqual(groups[1]["hooks"][0]["timeout"], 5)
        for k in REALISTIC:                                                       # 其他所有键（含中文）不变
            if k != "hooks":
                self.assertEqual(d[k], REALISTIC[k])
        for ev in ("SessionEnd", "PreToolUse", "Stop"):
            self.assertEqual(d["hooks"][ev], REALISTIC["hooks"][ev])
        self.assertEqual(len(self.backups()), 1)

    def test_install_twice_is_idempotent(self):
        self.write(REALISTIC)
        run("install", "--settings", self.path)
        first = self.read()
        self.assertEqual(run("install", "--settings", self.path), 0)
        self.assertEqual(self.read(), first)
        self.assertEqual(len(first["hooks"]["SessionStart"]), 2)
        self.assertEqual(len(self.backups()), 1)         # 第二次什么都没做，也就没有再备份

    def test_uninstall_restores_original(self):
        self.write(REALISTIC)
        run("install", "--settings", self.path)
        self.assertEqual(run("uninstall", "--settings", self.path), 0)
        self.assertEqual(self.read(), REALISTIC)

    def test_install_then_uninstall_is_byte_identical_and_keeps_trailing_newline_state(self):
        for nl in (False, True):
            self.write(REALISTIC)
            if nl:
                with open(self.path, "ab") as f:
                    f.write(b"\n")
            before = rb(self.path)
            self.assertEqual(run("install", "--settings", self.path), 0)
            after = rb(self.path)
            self.assertEqual(after.endswith(b"\n"), nl, "末尾换行的有无要和原文件一致")
            # 唯一的改动 = 多了我们那一个组：把它抠掉就应该和原文件逐字节一致
            self.assertNotEqual(after, before)
            self.assertEqual(run("uninstall", "--settings", self.path), 0)
            self.assertEqual(rb(self.path), before, "装了再卸，文件应该和原来逐字节一致")
            for b in self.backups():
                os.remove(b)

    def test_uninstall_removes_emptied_event_and_hooks(self):
        self.write({"model": "x"})
        run("install", "--settings", self.path)
        self.assertEqual(run("uninstall", "--settings", self.path), 0)
        self.assertEqual(self.read(), {"model": "x"})

    def test_uninstall_when_not_installed_changes_nothing(self):
        self.write(REALISTIC)
        before = rb(self.path)
        self.assertEqual(run("uninstall", "--settings", self.path), 0)
        self.assertEqual(rb(self.path), before)
        self.assertEqual(self.backups(), [])

    def test_uninstall_only_removes_ours_from_a_shared_group(self):
        shared = copy.deepcopy(REALISTIC)
        shared["hooks"]["SessionStart"].append({"matcher": "startup", "hooks": [CCMON, {"type": "command", "command": "x local.buddy-office y"}]})
        self.write(shared)
        run("uninstall", "--settings", self.path)
        d = self.read()
        self.assertEqual(d["hooks"]["SessionStart"][1], {"matcher": "startup", "hooks": [CCMON]})

    def test_refuses_invalid_json_and_leaves_no_trace(self):
        with open(self.path, "w") as f:
            f.write('{"hooks": {oops')
        os.chmod(self.path, 0o600)
        before = rb(self.path)
        self.assertEqual(run("install", "--settings", self.path), 2)
        self.assertEqual(run("uninstall", "--settings", self.path), 2)
        self.assertEqual(rb(self.path), before)
        self.assertEqual(self.backups(), [])
        self.assertEqual([n for n in os.listdir(self.dir) if n.startswith(".settings.json.tmp")], [])

    def test_refuses_non_object_and_bad_hooks_shape(self):
        for bad in ([1, 2, 3], {"hooks": []}, {"hooks": {"SessionStart": {}}}):
            with open(self.path, "w") as f:
                json.dump(bad, f)
            before = rb(self.path)
            self.assertEqual(run("install", "--settings", self.path), 2, bad)
            self.assertEqual(rb(self.path), before)

    def test_file_mode_is_preserved(self):
        self.write(REALISTIC, mode=0o600)
        run("install", "--settings", self.path)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
        self.write(REALISTIC, mode=0o644)
        run("uninstall", "--settings", self.path)         # 没装：不动
        run("install", "--settings", self.path)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o644)
        for b in self.backups():
            self.assertEqual(stat.S_IMODE(os.stat(b).st_mode) & 0o600, 0o600)

    def test_status(self):
        self.write(REALISTIC)
        self.assertEqual(run("status", "--settings", self.path), 1)
        run("install", "--settings", self.path)
        self.assertEqual(run("status", "--settings", self.path), 0)

    # R1a-02：~/.claude/settings.json 常常是指向 dotfiles 仓库的符号链接。改写必须落在链接指向的真实文件上、链接本身保持不变
    # （原来 os.replace 换掉的是链接本身：链接变成普通文件，dotfiles 里真正的那份没有加上 hook）。
    def make_link(self, obj):
        real_dir = os.path.join(self.dir, "dotfiles"); os.makedirs(real_dir)
        self.real = os.path.join(real_dir, "settings.json")
        with open(self.real, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, ensure_ascii=False)
        os.chmod(self.real, 0o600)
        os.symlink(self.real, self.path)

    def test_symlinked_settings_keeps_the_link_and_edits_the_real_file(self):
        self.make_link(REALISTIC)
        before = rb(self.real)
        self.assertEqual(run("install", "--settings", self.path), 0)
        self.assertTrue(os.path.islink(self.path), "install 之后 settings.json 应该还是符号链接")
        self.assertEqual(os.path.realpath(self.path), os.path.realpath(self.real))
        for p in (self.real, self.path):
            data = json.loads(rb(p).decode("utf-8"))
            self.assertEqual(len(data["hooks"]["SessionStart"]), 2, "hook 应该加在链接指向的真实文件里")
        self.assertEqual(stat.S_IMODE(os.stat(self.real).st_mode), 0o600)
        self.assertEqual(len(self.backups()), 1, "备份放在链接旁边（~/.claude 里），不是 dotfiles 仓库里")
        self.assertFalse(glob.glob(os.path.join(os.path.dirname(self.real), "*.bak-*")), "不要往 dotfiles 目录里丢备份")
        self.assertEqual(rb(self.backups()[0]), before, "备份 = 改之前的内容")
        # 装两次只有一条；卸载后链接还在、真实文件和安装前逐字节相同
        self.assertEqual(run("install", "--settings", self.path), 0)
        self.assertEqual(len(json.loads(rb(self.real).decode("utf-8"))["hooks"]["SessionStart"]), 2)
        self.assertEqual(run("uninstall", "--settings", self.path), 0)
        self.assertTrue(os.path.islink(self.path))
        self.assertEqual(rb(self.real), before)
        self.assertEqual(run("status", "--settings", self.path), 1)

    def test_dangling_symlink_is_refused_and_creates_nothing(self):
        os.symlink(os.path.join(self.dir, "no-such-dir", "settings.json"), self.path)
        self.assertEqual(run("install", "--settings", self.path), 2)
        self.assertTrue(os.path.islink(self.path))
        self.assertFalse(os.path.exists(os.path.join(self.dir, "no-such-dir")), "不能替用户凭空建出目录")
        self.assertEqual(self.backups(), [])

    # R1a P3：备份 / 临时文件原来先按默认 umask（0644）创建、写完内容再 chmod，中间有一个极短的窗口里同机其他用户能读到 settings.json 的内容
    # （可能带 env 密钥）。现在直接按原文件的权限创建。这里把 chmod 换成空操作，只看「创建出来就是 0600」。
    def test_backup_and_temp_files_are_created_private_without_relying_on_chmod(self):
        self.write(REALISTIC, mode=0o600)
        old_umask = os.umask(0o022)
        real_chmod = hm.os.chmod
        hm.os.chmod = lambda *a, **k: None
        try:
            self.assertEqual(run("install", "--settings", self.path), 0)
        finally:
            hm.os.chmod = real_chmod
            os.umask(old_umask)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600, "替换之后的 settings.json 应该还是 0600（临时文件创建时就是 0600）")
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(stat.S_IMODE(os.stat(self.backups()[0]).st_mode), 0o600, "备份创建时就该是 0600")

    def test_unicode_survives(self):
        self.write({"note": "中文 ✓ emoji 🙂", "hooks": {}})
        run("install", "--settings", self.path)
        self.assertEqual(self.read()["note"], "中文 ✓ emoji 🙂")
        with open(self.path, encoding="utf-8") as f:
            raw = f.read()
        self.assertIn("中文 ✓ emoji 🙂", raw)             # 不是 \\u 转义


if __name__ == "__main__":
    unittest.main(verbosity=2)
