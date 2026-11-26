import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts" / "internal"))
import skills as skills_mod
from skills_store import Store, copy_path, path_key, write_json


TARGETS = (
    ".agents/skills", ".claude/skills", ".pi/agent/skills", ".config/opencode/skills",
    ".dsh/skills", ".commandcode/skills", ".omp/agent/skills", ".workbuddy-ai/skills",
)
NAME = "distribution-probe"


def _can_create_symlinks():
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src"
        src.mkdir()
        link = Path(tmp) / "link"
        try:
            link.symlink_to(src, target_is_directory=True)
            return True
        except OSError:
            return False


SYMLINKS_SUPPORTED = _can_create_symlinks()


class SkillsTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.sandbox = Path(temp.name).resolve()
        self.repo = self.sandbox / "repo"
        self.home = self.sandbox / "device"
        self.home.mkdir()
        (self.repo / "scripts" / "internal").mkdir(parents=True)
        for script in (REPO / "scripts" / "internal").glob("skills*.py"):
            shutil.copy2(script, self.repo / "scripts" / "internal")
        self.source = self.repo / "skills" / "local" / NAME
        self.source.mkdir(parents=True)
        self.manifest = self.repo / "skills" / "manifest.json"
        self.manifest.write_text(json.dumps({"skills": {NAME: {"type": "local"}}}))
        self.write_skill(self.source, "Release one")
        (self.source / "reference.md").write_text("Supporting content\n")

    def command(self, *args, code=0, env_extra=None):
        env = dict(os.environ)
        for key in (
            "CLAUDE_CONFIG_DIR", "PI_CODING_AGENT_DIR", "XDG_CONFIG_HOME",
            "OPENCODE_CONFIG_DIR", "DSH_HOME", "WORKBUDDY_CONFIG_DIR",
            "OMP_PROFILE", "PI_PROFILE", "PI_CONFIG_DIR",
            "AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS", "AGENT_GOVERNANCE_SKILLS_BACKUP_KEEP",
        ):
            env.pop(key, None)
        if env_extra:
            env.update(env_extra)
        result = subprocess.run(
            [sys.executable, str(self.repo / "scripts/internal/skills.py"), *args, "--home", str(self.home)],
            capture_output=True, text=True, check=False, env=env,
        )
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def write_skill(self, location, body, name=NAME):
        location.mkdir(parents=True, exist_ok=True)
        (location / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Distribution probe\n---\n{body}\n",
            encoding="utf-8",
        )

    def target(self, directory, name=NAME):
        return self.home / directory / name

    def test_real_manifest_and_local_skills_are_valid(self):
        loaded, cli = skills_mod.load_skills()
        names = {skill.name for skill in loaded}
        self.assertRegex(cli, r"^\d+\.\d+\.\d+$")
        self.assertIn("grilling", names)
        self.assertIn("ai-change-flow", names)
        self.assertIn("new-project-bootstrap", names)
        self.assertIn("superpowers", names)
        self.assertNotIn("grill-me", names)
        self.assertNotIn("karpathy-guidelines", names)
        manifest = json.loads((REPO / "skills/manifest.json").read_text(encoding="utf-8"))
        self.assertIn("windowsDigest", manifest["skills"]["impeccable"])
        self.assertNotEqual(
            manifest["skills"]["impeccable"]["digest"],
            manifest["skills"]["impeccable"]["windowsDigest"],
        )

    def test_preview_and_status_are_read_only(self):
        self.assertIn("install", self.command("plan"))
        self.command("status", code=1)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_repeated_sync_and_version_rollback(self):
        self.command("sync")
        for target in TARGETS:
            path = self.target(target)
            self.assertIn("Release one", (path / "SKILL.md").read_text())
            self.assertEqual((path / "reference.md").read_text(), "Supporting content\n")
        self.command("status")
        self.write_skill(self.source, "Release two")
        self.command("sync")
        self.command("sync")
        self.command("rollback")
        for target in TARGETS:
            self.assertIn("Release one", (self.target(target) / "SKILL.md").read_text())
        self.command("rollback")
        self.assertTrue(all(not self.target(target).exists() for target in TARGETS))

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_conflicting_link_requires_exact_adoption_and_is_restored(self):
        source = self.sandbox / "independent"
        self.write_skill(source, "User version")
        clash = self.target(".claude/skills")
        clash.parent.mkdir(parents=True)
        clash.symlink_to(source, target_is_directory=True)
        self.assertIn(f"claude-code:{NAME}", self.command("plan"))
        self.command("sync", code=1)
        self.assertTrue(clash.is_symlink())
        self.command("sync", "--adopt", "claude-code:wrong-name", code=1)
        self.command("sync", "--adopt", f"claude-code:{NAME}")
        self.assertFalse(clash.is_symlink())
        self.assertIn("Release one", (clash / "SKILL.md").read_text())
        self.assertIn("User version", (source / "SKILL.md").read_text())
        self.command("rollback")
        self.assertTrue(clash.is_symlink())
        self.assertEqual(clash.readlink(), source)

    def test_identical_external_path_is_reused_and_drift_is_reported(self):
        reused = self.target(".claude/skills")
        shutil.copytree(self.source, reused)
        self.command("sync")
        self.command("rollback")
        self.assertTrue(reused.is_dir())
        self.command("sync")
        path = self.target(".dsh/skills")
        self.write_skill(path, "Manual edit")
        self.command("sync", code=1)
        self.command("rollback", code=1)
        self.assertIn("Manual edit", (path / "SKILL.md").read_text())
        self.assertTrue(self.target(".omp/agent/skills").is_dir())

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_parent_symlink_outside_device_is_rejected_before_writing(self):
        outside = self.sandbox / "outside"
        outside.mkdir()
        (self.home / ".claude").symlink_to(outside, target_is_directory=True)
        self.command("sync", code=1)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse(self.target(".agents/skills").exists())

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_parent_symlink_inside_device_is_rejected(self):
        inner = self.home / "real-claude"
        inner.mkdir()
        (self.home / ".claude").symlink_to(inner, target_is_directory=True)
        self.command("sync", code=1)
        self.assertEqual(list(inner.iterdir()), [])

    def test_path_changed_during_payload_staging_preserves_manual_edit(self):
        self.command("sync")
        target = self.target(".claude/skills")
        store = Store(self.home / ".local/state/agent-governance/skills", self.home.resolve())
        expected = path_key(target)

        def edit_during_copy(source, staging):
            copy_path(source, staging)
            self.write_skill(target, "Manual edit during staging")

        target = target.resolve()
        with patch("skills_store.copy_path", side_effect=edit_during_copy):
            with self.assertRaisesRegex(ValueError, "路径发生变化"):
                store.replace(target, self.source, expected, target.parent / ".stage")
        self.assertIn("Manual edit during staging", (target / "SKILL.md").read_text())

    def test_prune_retained_skills_handles_intact_deleted_and_modified_and_rolls_back(self):
        extra = "retired-probe"
        extra_src = self.repo / "skills" / "local" / extra
        self.write_skill(extra_src, "Extra v1", name=extra)
        self.manifest.write_text(json.dumps({
            "skills": {NAME: {"type": "local"}, extra: {"type": "local"}}
        }))
        self.command("sync")
        self.assertTrue(self.target(".agents/skills", extra).is_dir())

        # 从清单移除 extra，使其全部变为 retained。
        self.manifest.write_text(json.dumps({"skills": {NAME: {"type": "local"}}}))
        # 模拟三种现场：1) 手动删掉其中一个；2) 手动改过其中一个；3) 其余保持原样。
        shutil.rmtree(self.target(".dsh/skills", extra))
        modified = self.target(".claude/skills", extra)
        self.write_skill(modified, "User kept edit", name=extra)

        output = self.command("prune", code=1)
        self.assertIn("prune-ref", output)
        self.assertIn("conflict", output)
        # 完好项被清理，用户手改项保留，已删项从 state["managed"] 移除且无 None 残留。
        self.assertFalse(self.target(".agents/skills", extra).exists())
        self.assertTrue(modified.is_dir())
        state = json.loads((self.home / ".local/state/agent-governance/skills/state.json").read_text())
        self.assertNotIn(str(self.target(".agents/skills", extra)), state["managed"])
        self.assertNotIn(str(self.target(".dsh/skills", extra)), state["managed"])
        self.assertTrue(all(v is not None for v in state["managed"].values()))

        # rollback 恢复刚清理的完好项。
        self.command("rollback")
        self.assertTrue(self.target(".agents/skills", extra).is_dir())

    def test_snapshot_retention_truncates_chain_cleanly(self):
        for step in range(1, 5):
            self.write_skill(self.source, f"Release {step}")
            self.command("sync", env_extra={"AGENT_GOVERNANCE_SKILLS_BACKUP_KEEP": "2"})
        state_root = self.home / ".local/state/agent-governance/skills"
        snaps = [p for p in state_root.iterdir() if p.is_dir() and len(p.name) == 32]
        self.assertEqual(len(snaps), 2)
        # 连续两次 rollback 正常回退，第三次因链尾已被安全截断返回明确错误而非 FileNotFoundError。
        self.command("rollback")
        self.assertIn("Release 3", (self.target(".agents/skills") / "SKILL.md").read_text())
        self.command("rollback")
        self.assertIn("Release 2", (self.target(".agents/skills") / "SKILL.md").read_text())
        out = self.command("rollback", code=1)
        self.assertIn("没有可回退", out)

    def test_codex_legacy_only_managed_when_present(self):
        legacy = self.target(".codex/skills")
        self.command("sync")
        self.assertFalse(legacy.exists())
        shutil.copytree(self.source, legacy)
        self.assertIn("reuse", self.command("plan"))
        self.write_skill(self.source, "Release two")
        self.assertIn("codex-legacy:" + NAME, self.command("plan"))
        self.command("sync", "--adopt", f"codex-legacy:{NAME}")
        self.assertIn("Release two", (legacy / "SKILL.md").read_text())

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_linked_target_follows_primary_update(self):
        self.command("sync")
        claude_path = self.target(".claude/skills")
        shutil.rmtree(claude_path)
        claude_path.symlink_to(self.target(".agents/skills"), target_is_directory=True)
        self.write_skill(self.source, "Release two")
        plan_out = self.command("plan")
        self.assertIn(f"linked    claude-code:{NAME}", plan_out)
        self.command("sync")
        self.assertTrue(claude_path.is_symlink())
        self.assertIn("Release two", (claude_path / "SKILL.md").read_text())

    def test_extract_archive_security_and_rename_skill(self):
        commit = "a" * 40
        repo = "owner/sample"
        prefix = f"sample-{commit}"

        def make_tar(tar_path, entries):
            with tarfile.open(tar_path, "w:gz") as bundle:
                for member_name, kind, payload in entries:
                    info = tarfile.TarInfo(member_name)
                    if kind == "file":
                        data = payload.encode("utf-8")
                        info.size = len(data)
                        info.mode = 0o644
                        bundle.addfile(info, io.BytesIO(data))
                    elif kind == "symlink":
                        info.type = tarfile.SYMTYPE
                        info.linkname = payload
                        bundle.addfile(info)

        good_tar = self.sandbox / "good.tar.gz"
        make_tar(good_tar, [(f"{prefix}/skills/demo/SKILL.md", "file", "---\nname: old-name\n---\nbody\n")])
        checkout = self.sandbox / "out-good"
        skills_mod.extract_archive(good_tar, repo, commit, {"skills/demo"}, checkout)
        skill_md = checkout / "skills/demo/SKILL.md"
        self.assertTrue(skill_md.is_file())
        skills_mod.rename_skill(skill_md, "old-name", "new-name")
        self.assertIn("name: new-name\n", skill_md.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(ValueError, "无法核对上游"):
            skills_mod.rename_skill(skill_md, "wrong-name", "other")

        traversal_tar = self.sandbox / "traversal.tar.gz"
        make_tar(traversal_tar, [(f"{prefix}/skills/demo/../../evil.txt", "file", "boom")])
        with self.assertRaisesRegex(ValueError, "无效的归档路径"):
            skills_mod.extract_archive(traversal_tar, repo, commit, {"skills/demo"}, self.sandbox / "out-trav")

        symlink_tar = self.sandbox / "symlink.tar.gz"
        make_tar(symlink_tar, [(f"{prefix}/skills/demo/link", "symlink", "/etc/passwd")])
        with self.assertRaisesRegex(ValueError, "无效的归档文件类型"):
            skills_mod.extract_archive(symlink_tar, repo, commit, {"skills/demo"}, self.sandbox / "out-sym")

    def test_recover_interrupted_transaction(self):
        self.command("sync")
        state_root = self.home / ".local/state/agent-governance/skills"
        store = Store(state_root, self.home.resolve())
        state = store.state()
        target = self.target(".claude/skills").resolve()
        before_key = path_key(target)
        # 构造中断事务：target 已被改为新内容且 pending.json 残留，recover 须自动恢复到 before。
        tx = "1" * 32
        snap = store.snapshot(tx)
        snap.mkdir()
        copy_path(target, snap / "0")
        self.write_skill(target, "Interrupted half-write")
        after_key = path_key(target)
        write_json(snap / "record.json", {
            "state": state,
            "entries": [{"path": str(target), "before": before_key, "after": after_key}],
        })
        write_json(store.pending, tx)
        self.command("plan", code=1)
        store.recover()
        self.assertFalse(store.pending.exists())
        self.assertIn("Release one", (target / "SKILL.md").read_text())

    def test_env_roots_for_pi_config_and_omp_profile(self):
        with patch.dict(os.environ, {
            "PI_CONFIG_DIR": ".custom-omp",
            "OMP_PROFILE": "work",
            "OPENCODE_CONFIG_DIR": str(self.home / ".my-opencode"),
        }, clear=False):
            roots = dict(skills_mod.roots_for(self.home, isolated=False))
        self.assertEqual(roots["omp"], self.home / ".custom-omp/profiles/work/agent/skills")
        self.assertEqual(roots["opencode"], self.home / ".my-opencode/skills")

        with patch.dict(os.environ, {"PI_CONFIG_DIR": "../escape"}, clear=False):
            with self.assertRaisesRegex(ValueError, "路径跳转"):
                list(skills_mod.roots_for(self.home, isolated=False))

    def test_adopt_all_overwrites_conflicts_and_rolls_back(self):
        # 1) 未受管冲突目录；2) 指向外部目录的软链；3) 先同步再手工修改的受管目录。
        self.command("sync")
        edited = self.target(".dsh/skills")
        self.write_skill(edited, "Manual local edit")

        manual_dir = self.target(".agents/skills")
        shutil.rmtree(manual_dir)
        self.write_skill(manual_dir, "Old manual install")

        external = self.sandbox / "external-skill"
        self.write_skill(external, "External version")
        claude_path = self.target(".claude/skills")
        shutil.rmtree(claude_path)
        if SYMLINKS_SUPPORTED:
            claude_path.symlink_to(external, target_is_directory=True)
        else:
            self.write_skill(claude_path, "External copy")

        # 不带 --adopt-all 仍按冲突拒绝。
        self.command("sync", code=1)
        # CLI 校验：非 sync 拒绝 --adopt-all，且不能与 --adopt 混用。
        self.command("plan", "--adopt-all", code=2)
        self.command("sync", "--adopt-all", "--adopt", f"codex:{NAME}", code=2)

        output = self.command("sync", "--adopt-all")
        self.assertIn(f"adopt     codex:{NAME}", output)
        self.assertIn(f"adopt     dsh:{NAME}", output)
        self.assertIn("Release one", (manual_dir / "SKILL.md").read_text())
        self.assertIn("Release one", (edited / "SKILL.md").read_text())
        self.assertIn("Release one", (claude_path / "SKILL.md").read_text())
        self.assertFalse(claude_path.is_symlink())
        self.assertIn("External version", (external / "SKILL.md").read_text())
        self.command("status")

        # 回滚恢复覆盖前的全部现场（含外部软链）。
        self.command("rollback")
        self.assertIn("Old manual install", (manual_dir / "SKILL.md").read_text())
        self.assertIn("Manual local edit", (edited / "SKILL.md").read_text())
        if SYMLINKS_SUPPORTED:
            self.assertTrue(claude_path.is_symlink())
            self.assertEqual(claude_path.readlink(), external)

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_adopt_all_preserves_internal_linked_symlinks_both_directions(self):
        # 正向：claude-code -> codex（stale dir）；反向：pi -> omp（stale dir）。
        codex_path = self.target(".agents/skills")
        self.write_skill(codex_path, "Stale codex")
        claude_path = self.target(".claude/skills")
        claude_path.parent.mkdir(parents=True, exist_ok=True)
        claude_path.symlink_to(codex_path, target_is_directory=True)

        omp_path = self.target(".omp/agent/skills")
        self.write_skill(omp_path, "Stale omp")
        pi_path = self.target(".pi/agent/skills")
        pi_path.parent.mkdir(parents=True, exist_ok=True)
        pi_path.symlink_to(omp_path, target_is_directory=True)

        output = self.command("sync", "--adopt-all")
        self.assertIn(f"linked    claude-code:{NAME}", output)
        self.assertIn(f"linked    pi:{NAME}", output)
        self.assertTrue(claude_path.is_symlink())
        self.assertTrue(pi_path.is_symlink())
        self.assertIn("Release one", (claude_path / "SKILL.md").read_text())
        self.assertIn("Release one", (pi_path / "SKILL.md").read_text())

    @unittest.skipUnless(SYMLINKS_SUPPORTED, "requires symlink privilege")
    def test_adopt_all_handles_symlink_loop_without_crashing(self):
        loop_a = self.target(".claude/skills")
        loop_b = self.sandbox / "loop-b"
        loop_a.parent.mkdir(parents=True, exist_ok=True)
        loop_a.symlink_to(loop_b)
        loop_b.symlink_to(loop_a)

        self.assertIn(f"conflict  claude-code:{NAME}", self.command("plan"))
        self.command("sync", "--adopt-all")
        self.assertFalse(loop_a.is_symlink())
        self.assertIn("Release one", (loop_a / "SKILL.md").read_text())
        self.command("rollback")
        self.assertTrue(loop_a.is_symlink())
        self.assertEqual(loop_a.readlink(), loop_b)

    def test_adopt_all_handles_readonly_files_and_dirs_and_rolls_back(self):
        # 模拟 git clone 留下的 0444 只读文件与 0555 只读子目录（含目录内软链）。
        conflict_dir = self.target(".claude/skills")
        self.write_skill(conflict_dir, "Cloned skill")
        ro_dir = conflict_dir / "pack"
        ro_dir.mkdir()
        ro_file = ro_dir / "obj.pack"
        ro_file.write_text("immutable pack\n", encoding="utf-8")
        if SYMLINKS_SUPPORTED:
            (ro_dir / "dangling").symlink_to("missing-target")
        os.chmod(ro_file, 0o444)
        if os.name != "nt":
            os.chmod(ro_dir, 0o555)
        self.addCleanup(
            lambda: (
                os.chmod(ro_dir, 0o700) if ro_dir.exists() and os.name != "nt" else None,
                os.chmod(ro_file, 0o600) if ro_file.exists() else None,
            )
        )

        self.command("sync", "--adopt-all")
        state_root = self.home / ".local/state/agent-governance/skills"
        self.assertFalse((state_root / "pending.json").exists())
        self.assertIn("Release one", (conflict_dir / "SKILL.md").read_text())

        self.command("rollback")
        self.assertFalse((state_root / "pending.json").exists())
        self.assertIn("Cloned skill", (conflict_dir / "SKILL.md").read_text())
        self.assertEqual((conflict_dir / "pack/obj.pack").read_text(encoding="utf-8"), "immutable pack\n")


if __name__ == "__main__":
    unittest.main()
