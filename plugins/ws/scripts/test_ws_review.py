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

    def test_same_size_edit_in_index_second_is_not_missed(self):
        # git's racy-index guard needs the temp index to keep the real index mtime
        git(self.back, "config", "core.trustctime", "false")
        git(self.back, "config", "core.checkStat", "minimal")
        f, t0 = os.path.join(self.back, "a.txt"), time.time() - 100
        os.utime(f, (t0, t0))
        git(self.back, "update-index", "--refresh")
        idx = os.path.join(git(self.back, "rev-parse", "--absolute-git-dir"), "index")
        os.utime(idx, (t0, t0))
        self.write(self.back, "a.txt", "b")  # same size as "a"
        os.utime(f, (t0, t0))
        r.snapshot(self.back)
        self.assertEqual(git(self.back, "show", r.REF + ":a.txt"), "b")

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


class MidOperation(Base):
    """The temp index makes the snapshot work while the real index is locked or mid-merge."""

    def check_succeeds(self, repo):
        head = git(repo, "rev-parse", "HEAD")
        idx = os.path.join(git(repo, "rev-parse", "--absolute-git-dir"), "index")
        with open(idx, "rb") as f:
            index_before = f.read()
        self.prompt()
        self.assertTrue(baseline(repo))
        self.assertEqual(git(repo, "rev-parse", "HEAD"), head)
        with open(idx, "rb") as f:
            self.assertEqual(f.read(), index_before)
        self.assertFalse(os.path.exists(self.failed("back")))
        self.assertFalse(os.path.exists(self.failed("front")))

    def test_real_index_lock_present(self):
        lock = os.path.join(git(self.back, "rev-parse", "--absolute-git-dir"), "index.lock")
        open(lock, "w").close()
        self.write(self.back, "n.txt", "x")
        self.check_succeeds(self.back)
        self.assertTrue(os.path.exists(lock))
        self.assertIn("n.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))

    def test_merge_with_unmerged_entries(self):
        git(self.back, "checkout", "-q", "-b", "other")
        self.write(self.back, "a.txt", "other")
        git(self.back, "commit", "-qam", "other")
        git(self.back, "checkout", "-q", "main")
        self.write(self.back, "a.txt", "main")
        git(self.back, "commit", "-qam", "main")
        subprocess.run(["git", "merge", "other"], cwd=self.back, capture_output=True)
        self.assertIn("a.txt", git(self.back, "diff", "--name-only", "--diff-filter=U"))
        self.check_succeeds(self.back)
        self.assertIn("a.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))

    def test_rebase_stopped_midway(self):
        git(self.back, "checkout", "-q", "-b", "other")
        self.write(self.back, "a.txt", "other")
        git(self.back, "commit", "-qam", "other")
        git(self.back, "checkout", "-q", "main")
        self.write(self.back, "a.txt", "main")
        git(self.back, "commit", "-qam", "main")
        git(self.back, "checkout", "-q", "other")
        subprocess.run(["git", "rebase", "main"], cwd=self.back, capture_output=True,
                       env={**os.environ, "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})
        self.assertTrue(os.path.isdir(os.path.join(git(self.back, "rev-parse", "--absolute-git-dir"), "rebase-merge")))
        self.check_succeeds(self.back)

    def test_git_timeout_is_recorded_as_failed(self):
        real = r.subprocess.run

        def hang(cmd, **kw):
            if kw.get("cwd") == self.back:
                raise subprocess.TimeoutExpired(cmd, 4)
            return real(cmd, **kw)
        with mock.patch.object(r.subprocess, "run", side_effect=hang):
            self.prompt()
        self.assertTrue(os.path.exists(self.failed("back")))
        self.assertTrue(baseline(self.front))


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

    def test_kept_baseline_keeps_previous_failed(self):
        self.prompt()
        _ = self.pending("back"), self.alive()
        r._write_json(self.failed("back"), {"reason": "earlier", "at": "t"})
        self.prompt()
        with open(self.failed("back")) as f:
            self.assertEqual(json.load(f)["reason"], "earlier")

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


def parent(repo):
    return git(repo, "log", "-1", "--format=%P", r.REF)


class HeadLink(Base):
    """I1: the baseline records HEAD as its parent; a moved HEAD restarts the review."""

    def moved(self, name):
        return os.path.join(self.state, "moved", name + ".json")

    def commit_upstream(self, repo, name="up.txt"):
        # what a pull, rebase or checkout does: HEAD moves and brings files with it
        self.write(repo, name, "upstream")
        git(repo, "add", name)
        git(repo, "commit", "-q", "-m", "upstream")

    def test_snapshot_parent_is_head(self):
        r.snapshot(self.back)
        self.assertEqual(parent(self.back), git(self.back, "rev-parse", "HEAD"))

    def test_unborn_branch_snapshot_has_no_parent(self):
        repo = os.path.join(self.root, "unborn")
        os.makedirs(repo)
        git(repo, "init", "-q", "-b", "main")
        self.write(repo, "f.txt", "x")
        r.snapshot(repo)
        self.assertEqual(parent(repo), "")
        self.assertIn("f.txt", git(repo, "ls-tree", "-r", "--name-only", r.REF))

    def test_head_change_advances_despite_fresh_pending(self):
        self.prompt()
        old = baseline(self.back)
        self.pending("back")
        self.alive()
        self.commit_upstream(self.back)
        self.prompt()
        self.assertNotEqual(baseline(self.back), old)
        head = git(self.back, "rev-parse", "HEAD")
        self.assertEqual(parent(self.back), head)
        self.assertIn("up.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))
        with open(self.moved("back")) as f:
            info = json.load(f)
        self.assertEqual((info["to"], bool(info["from"]), bool(info["at"])), (head, True, True))
        self.assertFalse(os.path.exists(self.moved("front")))

    def test_same_head_keeps_baseline_and_writes_no_marker(self):
        self.prompt()
        old = baseline(self.back)
        self.pending("back")
        self.alive()
        self.write(self.back, "n.txt", "x")
        self.prompt()
        self.assertEqual(baseline(self.back), old)
        self.assertFalse(os.path.exists(self.moved("back")))

    def test_head_change_without_pending_writes_no_marker(self):
        self.prompt()
        self.commit_upstream(self.back)
        self.prompt()
        self.assertEqual(parent(self.back), git(self.back, "rev-parse", "HEAD"))
        self.assertFalse(os.path.exists(self.moved("back")))


class Interrupted(Base):
    """I2: a hook killed mid-snapshot leaves a failed marker; git calls share one deadline."""

    def test_failed_marker_is_written_before_the_snapshot(self):
        seen = {}
        real = r.snapshot

        def spy(path, *a, **kw):
            name = os.path.basename(path)
            try:
                with open(self.failed(name)) as f:
                    seen[name] = json.load(f)["reason"]
            except OSError:
                seen[name] = None
            return real(path, *a, **kw)
        with mock.patch.object(r, "snapshot", side_effect=spy):
            self.prompt()
        self.assertEqual(seen, {"back": "instantané interrompu", "front": "instantané interrompu"})
        self.assertFalse(os.path.exists(self.failed("back")))
        self.assertFalse(os.path.exists(self.failed("front")))

    def test_slow_git_shares_one_deadline_per_prompt(self):
        import shutil
        real_git = shutil.which("git")
        bin_dir = os.path.join(self.root, "bin")
        os.makedirs(bin_dir)
        with open(os.path.join(bin_dir, "git"), "w") as f:
            f.write('#!/bin/sh\ncase "$PWD" in "$SLOW_DIR"*) sleep 1;; esac\nexec "%s" "$@"\n' % real_git)
        os.chmod(os.path.join(bin_dir, "git"), 0o755)
        env = {"PATH": bin_dir + os.pathsep + os.environ["PATH"], "SLOW_DIR": self.back}
        t0 = time.monotonic()
        with mock.patch.dict(os.environ, env):
            self.prompt()
        elapsed = time.monotonic() - t0
        self.assertLess(elapsed, r.DEADLINE + 0.8)
        self.assertTrue(os.path.exists(self.failed("back")))
        self.assertTrue(baseline(self.front))


class Registry(Base):
    """Same filter as the extension's workspace.ts: unusable entries are skipped, never fatal."""

    def write_registry(self, entries):
        with open(os.path.join(self.home, "registry.json"), "w") as f:
            json.dump({"workspaces": entries}, f)

    def test_entry_without_slug_is_skipped_and_hook_still_snapshots(self):
        self.write_registry({"1": {"workspace_path": self.ws, "repos": [{"name": "back", "path": self.back}]}})
        self.prompt(cwd=self.back)
        self.assertTrue(baseline(self.back))
        slug = r.re.sub(r"[^A-Za-z0-9]", "-", self.back)
        self.assertTrue(os.path.exists(os.path.join(self.home, "review", slug, "running", "s1")))

    def test_entry_with_non_list_repos_is_skipped(self):
        self.write_registry({"1": {"slug": "feat", "workspace_path": self.ws, "repos": {"back": self.back}}})
        self.prompt(cwd=self.back)
        self.assertTrue(baseline(self.back))
        self.assertFalse(os.path.exists(os.path.join(self.state, "running", "s1")))

    def test_list_registry_and_repo_without_name_are_tolerated(self):
        self.write_registry([{"slug": "feat", "workspace_path": self.ws,
                              "repos": [{"path": self.front}, {"name": "back", "path": self.back}]}])
        self.prompt()
        self.assertTrue(baseline(self.back))
        self.assertTrue(os.path.exists(os.path.join(self.state, "running", "s1")))


class Cleanup(Base):
    def touch(self, *parts, age=0):
        p = os.path.join(self.state, *parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").close()
        t = time.time() - age
        os.utime(p, (t, t))
        return p

    def test_old_state_files_are_removed(self):
        sessions = os.path.join(self.root, "sessions")
        os.makedirs(sessions)
        for sid, pid in (("dead", 99999999), ("live", os.getpid())):
            with open(os.path.join(sessions, sid + ".json"), "w") as f:
                json.dump({"sessionId": sid, "pid": pid}, f)
        old_alive = self.touch("alive", "old", age=2 * 86400)
        new_alive = self.touch("alive", "new", age=120)
        dead = self.touch("running", "dead")
        live = self.touch("running", "live", age=3 * 86400)
        unknown_old = self.touch("running", "unknown-old", age=2 * 86400)
        unknown_new = self.touch("running", "unknown-new", age=60)
        tmp_old = self.touch("pending", ".back.123.tmp", age=2 * 3600)
        tmp_new = self.touch("pending", ".front.456.tmp", age=60)
        with mock.patch.dict(os.environ, {"CLAUDE_REVIEW_SESSIONS_DIR": sessions}):
            self.prompt(sid="s1")
        gone = [p for p in (old_alive, dead, unknown_old, tmp_old) if os.path.exists(p)]
        kept = [p for p in (new_alive, live, unknown_new, tmp_new, os.path.join(self.state, "running", "s1")) if not os.path.exists(p)]
        self.assertEqual((gone, kept), ([], []))


class LargeFiles(Base):
    def test_large_untracked_file_is_left_out_and_recorded(self):
        self.write(self.back, "small.txt", "x")
        self.write(self.back, "huge.bin", "y" * 100)
        os.makedirs(os.path.join(self.back, "sub dir"))
        self.write(self.back, "sub dir/big [1].bin", "z" * 100)
        with mock.patch.object(r, "MAX_UNTRACKED", 50):
            self.prompt()
        files = git(self.back, "ls-tree", "-r", "--name-only", r.REF).splitlines()
        self.assertIn("small.txt", files)
        self.assertNotIn("huge.bin", files)
        self.assertNotIn("sub dir/big [1].bin", files)
        with open(self.failed("back")) as f:
            reason = json.load(f)["reason"]
        self.assertTrue(reason.startswith("fichiers trop gros ignorés : "), reason)
        self.assertIn("huge.bin", reason)
        self.assertIn("sub dir/big [1].bin", reason)
        self.assertFalse(os.path.exists(self.failed("front")))

    def test_large_tracked_file_stays_in_snapshot(self):
        self.write(self.back, "big.txt", "y" * 100)
        git(self.back, "add", "big.txt")
        git(self.back, "commit", "-q", "-m", "big")
        with mock.patch.object(r, "MAX_UNTRACKED", 50):
            self.prompt()
        self.assertIn("big.txt", git(self.back, "ls-tree", "-r", "--name-only", r.REF))
        self.assertFalse(os.path.exists(self.failed("back")))


class FindWorkspace(unittest.TestCase):
    def test_longest_prefix_wins(self):
        reg = {"workspaces": {"1": {"slug": "outer", "workspace_path": "/nonexistent/a", "repos": []},
                              "2": {"slug": "inner", "workspace_path": "/nonexistent/a/b", "repos": []}}}
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
