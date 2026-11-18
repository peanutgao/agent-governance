import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from skills_store import Store, copy_path, path_key


TARGETS = (
    ".agents/skills", ".claude/skills", ".pi/agent/skills", ".config/opencode/skills",
    ".dsh/skills", ".commandcode/skills", ".omp/agent/skills", ".workbuddy-ai/skills",
)
NAME = "distribution-probe"


class SkillsTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.sandbox = Path(temp.name)
        self.repo = self.sandbox / "repo"
        self.home = self.sandbox / "device"
        self.home.mkdir()
        (self.repo / "scripts").mkdir(parents=True)
        for script in (REPO / "scripts").glob("skills*.py"):
            shutil.copy2(script, self.repo / "scripts")
        self.source = self.repo / "skills" / "local" / NAME
        self.source.mkdir(parents=True)
        self.manifest = self.repo / "skills" / "manifest.json"
        self.manifest.write_text(json.dumps({"skills": {NAME: {"type": "local"}}}))
        self.write_skill(self.source, "Release one")
        (self.source / "reference.md").write_text("Supporting content\n")

    def command(self, *args, code=0):
        result = subprocess.run(
            [sys.executable, str(self.repo / "scripts/skills.py"), *args, "--home", str(self.home)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def write_skill(self, location, body):
        location.mkdir(parents=True, exist_ok=True)
        (location / "SKILL.md").write_text(f"---\nname: {NAME}\ndescription: Distribution probe\n---\n{body}\n")

    def target(self, directory):
        return self.home / directory / NAME

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

    def test_parent_symlink_outside_device_is_rejected_before_writing(self):
        outside = self.sandbox / "outside"
        outside.mkdir()
        (self.home / ".claude").symlink_to(outside, target_is_directory=True)
        self.command("sync", code=1)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse(self.target(".agents/skills").exists())

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


if __name__ == "__main__":
    unittest.main()
