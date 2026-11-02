"""Tests for ws-review.py with real temp git repos. Run: python3 -m unittest plugins/ws/scripts/test_ws_review.py"""
import importlib.util, io, json, os, subprocess, sys, tempfile, time, unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("ws_review", os.path.join(HERE, "ws-review.py"))
r = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r)


def git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, check=True,
                          env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}).stdout.strip()


def make_repo(path):
    os.makedirs(path)
    git(path, "init", "-q", "-b", "main")
    with open(os.path.join(path, "a.txt"), "w") as f:
        f.write("a")
    git(path, "add", "-A")
    git(path, "commit", "-q", "-m", "init")
    return path


def baseline(repo):
    return git(repo, "rev-parse", "--verify", "-q", r.REF)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.realpath(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.home = os.path.join(self.root, "home")
        self.ws = os.path.join(self.root, "ws")
        self.back = make_repo(os.path.join(self.ws, "back"))
        self.front = make_repo(os.path.join(self.ws, "front"))
        self.state = os.path.join(self.home, "review", "feat")
        self.registry({"back": self.back, "front": self.front})

    def registry(self, repos):
        os.makedirs(self.home, exist_ok=True)
        with open(os.path.join(self.home, "registry.json"), "w") as f:
            json.dump({"workspaces": {"1": {"slug": "feat", "workspace_path": self.ws,
                       "repos": [{"name": n, "path": p, "port": None} for n, p in repos.items()]}}}, f)

    def prompt(self, cwd=None, sid="s1"):
        r.on_prompt({"cwd": cwd or self.ws, "session_id": sid}, self.home)

    def write(self, repo, name, text):
        with open(os.path.join(repo, name), "w") as f:
            f.write(text)

    def pending(self, name, count=1):
        os.makedirs(os.path.join(self.state, "pending"), exist_ok=True)
        with open(os.path.join(self.state, "pending", name + ".json"), "w") as f:
            json.dump({"count": count}, f)

    def alive(self, age=0):
        os.makedirs(os.path.join(self.state, "alive"), exist_ok=True)
        p = os.path.join(self.state, "alive", "win1")
        open(p, "w").close()
        t = time.time() - age
        os.utime(p, (t, t))

    def failed(self, name):
        return os.path.join(self.state, "failed", name + ".json")


class Snapshot(Base):
    def test_snapshot_keeps_branch_and_index(self):
        head, status = git(self.back, "rev-parse", "HEAD"), git(self.back, "status", "--porcelain")
        self.write(self.back, "new.txt", "x")
        r.snapshot(self.back)
        self.assertEqual(git(self.back, "rev-parse", "HEAD"), head)
        self.assertEqual(git(self.back, "status", "--porcelain"), status + "?? new.txt")
        self.assertIn("new.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))

    def test_worktrees_of_one_repo_keep_distinct_baselines(self):
        wt = os.path.join(self.root, "linked")
        git(self.back, "worktree", "add", "-q", "-b", "other", wt)
        self.write(self.back, "only-main.txt", "1")
        self.write(wt, "only-linked.txt", "2")
        r.snapshot(self.back)
        r.snapshot(wt)
        self.assertNotEqual(baseline(self.back), baseline(wt))
        self.assertIn("only-main.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))
        self.assertNotIn("only-linked.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))
        self.assertIn("only-linked.txt", git(wt, "ls-tree", "-r", "--name-only", r.REF))


class Prompt(Base):
    def test_prompt_covers_each_repo_in_parallel(self):
        self.prompt()
        self.assertTrue(baseline(self.back))
        self.assertTrue(baseline(self.front))

    def test_pending_keeps_baseline_when_window_alive(self):
        self.prompt()
        old = baseline(self.back)
        self.pending("back")
        self.alive()
        self.write(self.back, "n.txt", "x")
        self.prompt()
        self.assertEqual(baseline(self.back), old)

    def test_stale_alive_ignores_pending_and_moves_baseline(self):
        self.prompt()
        old = baseline(self.back)
        self.pending("back")
        self.alive(age=120)
        self.write(self.back, "n.txt", "x")
        self.prompt()
        self.assertNotEqual(baseline(self.back), old)

    def test_repo_without_pending_moves_while_other_keeps(self):
        self.prompt()
        ob, of = baseline(self.back), baseline(self.front)
        self.pending("back")
        self.alive()
        self.write(self.back, "n.txt", "x")
        self.write(self.front, "n.txt", "x")
        self.prompt()
        self.assertEqual(baseline(self.back), ob)
        self.assertNotEqual(baseline(self.front), of)

    def test_missing_optional_repo_is_skipped(self):
        self.registry({"back": self.back, "gone": os.path.join(self.ws, "gone")})
        self.prompt()
        self.assertTrue(baseline(self.back))
        self.assertFalse(os.path.exists(self.failed("gone")))

    def test_git_failure_writes_failed_and_other_repo_succeeds(self):
        # a stale lock on the ref makes update-ref fail for back only
        ref_lock = os.path.join(git(self.back, "rev-parse", "--absolute-git-dir"), r.REF + ".lock")
        os.makedirs(os.path.dirname(ref_lock))
        open(ref_lock, "w").close()
        self.prompt()
        with open(self.failed("back")) as f:
            info = json.load(f)
        self.assertTrue(info["reason"] and info["at"])
        self.assertTrue(baseline(self.front))
        self.assertFalse(os.path.exists(self.failed("front")))

    def test_success_clears_previous_failed(self):
        os.makedirs(os.path.join(self.state, "failed"))
        for n in ("back", "front"):
            with open(self.failed(n), "w") as f:
                f.write("{}")
        self.prompt()
        self.assertFalse(os.path.exists(self.failed("back")))
        self.assertFalse(os.path.exists(self.failed("front")))

    def test_running_created_then_removed_by_session_id(self):
        run = os.path.join(self.state, "running", "s1")
        self.prompt(sid="s1")
        self.assertTrue(os.path.exists(run))
        r.on_stop({"cwd": self.ws, "session_id": "s1"}, self.home)
        self.assertFalse(os.path.exists(run))

    def test_cwd_outside_registry_uses_git_toplevel(self):
        solo = make_repo(os.path.join(self.root, "solo"))
        self.prompt(cwd=solo)
        slug = r.re.sub(r"[^A-Za-z0-9]", "-", solo)
        self.assertTrue(os.path.exists(os.path.join(self.home, "review", slug, "running", "s1")))
        self.assertTrue(baseline(solo))


class FindWorkspace(unittest.TestCase):
    def test_longest_prefix_wins(self):
        reg = {"workspaces": {"1": {"slug": "outer", "workspace_path": "/nonexistent/a"},
                              "2": {"slug": "inner", "workspace_path": "/nonexistent/a/b"}}}
        self.assertEqual(r.find_workspace("/nonexistent/a/b/back", reg)["slug"], "inner")
        self.assertEqual(r.find_workspace("/nonexistent/a/c", reg)["slug"], "outer")
        self.assertIsNone(r.find_workspace("/nonexistent/ab", reg))


class Cli(Base):
    def run_cli(self, cmd, stdin):
        return subprocess.run([sys.executable, os.path.join(HERE, "ws-review.py"), cmd], input=stdin,
                              capture_output=True, text=True, env={**os.environ, "WS_HOME": self.home})

    def test_never_raises_on_invalid_json(self):
        for cmd, stdin in (("prompt", "not json"), ("stop", ""), ("bogus", "{}"), ("prompt", '{"cwd": "/nonexistent"}')):
            p = self.run_cli(cmd, stdin)
            self.assertEqual((p.returncode, p.stdout, p.stderr), (0, "", ""))

    def test_cli_prompt_snapshots_silently(self):
        p = self.run_cli("prompt", json.dumps({"cwd": self.ws, "session_id": "s1"}))
        self.assertEqual((p.returncode, p.stdout, p.stderr), (0, "", ""))
        self.assertTrue(baseline(self.back))


if __name__ == "__main__":
    unittest.main()
