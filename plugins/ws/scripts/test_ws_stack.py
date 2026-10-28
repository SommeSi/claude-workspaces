"""Tests for ws-stack.py on a throwaway git repo (no gh). Run: python3 -m unittest scripts/test_ws_stack.py"""
import json, os, shutil, subprocess, tempfile, unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws-stack.py")
WORKFLOW = """name: PR Size Limit
jobs:
    check-meet-requirement:
        steps:
            - env:
                MAX_FILES: '3'
                MAX_LINES: '40'
                EXCLUDE_REGEX: '^spec/|_spec[.]rb$|^db/schema[.]rb$'
"""


def text(n, tag):
    return "".join(f"{tag} line {i}\n" for i in range(n))


def layer(branch, *files):
    return {"branch": branch, "title": f"feat(x): {branch}", "body": f"## Resume\n- {branch}", "files": list(files)}


MODELS = ["app/models/a.rb", "app/models/b.rb", "spec/models/a_spec.rb", "db/schema.rb"]
SERVICES = ["app/services/s.rb", "app/new.rb", "app/gone.rb"]
FRONT = ["web/page.tsx"]


class StackRepo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="test-ws-stack-")
        self.env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
        self.dir = os.path.join(self.tmp, "work")
        self.git("init", "-q", "--bare", "-b", "develop", "remote.git", cwd=self.tmp)
        self.git("clone", "-q", "remote.git", "work", cwd=self.tmp)
        self.write(".github/workflows/pr-size-limit.yml", WORKFLOW)
        self.write("app/models/b.rb", text(5, "b"))
        self.write("app/old.rb", text(20, "old"))
        self.write("app/gone.rb", text(6, "gone"))
        self.write("db/schema.rb", text(3, "schema"))
        self.git("add", "-A")
        self.git("commit", "-qm", "base")
        self.git("push", "-q", "origin", "HEAD:develop")
        self.git("fetch", "-q", "origin")
        self.git("checkout", "-qb", "feat/x")
        self.write("app/models/a.rb", text(10, "a"))                       # +10
        self.write("app/models/b.rb", text(7, "b"))                        # +2
        self.write("spec/models/a_spec.rb", text(30, "spec"))              # excluded
        self.write("app/services/s.rb", text(12, "s"))                     # +12
        os.rename(self.path("app/old.rb"), self.path("app/new.rb"))
        self.write("app/new.rb", text(19, "old") + "changed\n")            # rename, +1 -1
        os.remove(self.path("app/gone.rb"))                                # -6
        self.write("db/schema.rb", text(50, "schema"))                     # excluded
        self.write("web/page.tsx", text(8, "page"))                        # +8
        self.git("add", "-A")
        self.git("commit", "-qm", "big feature")
        self.head = self.git("rev-parse", "HEAD")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # helpers
    def path(self, rel):
        return os.path.join(self.dir, rel)

    def write(self, rel, content):
        os.makedirs(os.path.dirname(self.path(rel)), exist_ok=True)
        with open(self.path(rel), "w") as f:
            f.write(content)

    def git(self, *args, cwd=None):
        r = subprocess.run(["git", *args], cwd=cwd or self.dir, env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def run_script(self, *args, input=None, cwd=None):
        return subprocess.run(["python3", SCRIPT, *args], cwd=cwd or self.dir, env=self.env,
                              input=input, capture_output=True, text=True)

    def split(self, layers, *flags):
        plan = os.path.join(self.tmp, "plan.json")
        with open(plan, "w") as f:
            json.dump({"base": "origin/develop", "assignee": "Uozak218", "layers": layers}, f)
        return self.run_script("split", plan, *flags)

    def stack_branches(self):
        return self.git("branch", "--list", "feat/x-*", "--format=%(refname:short)").split()

    def assert_refused(self, r, message):
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(message, r.stderr)
        self.assertEqual(self.stack_branches(), [])

    def good_layers(self):
        return [layer("feat/x-1-models", *MODELS), layer("feat/x-2-services", *SERVICES),
                layer("feat/x-3-front", *FRONT)]

    # size
    def test_size_counts_like_the_workflow(self):
        r = self.run_script("size")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = r.stdout.splitlines()
        self.assertEqual(out[0], "FILES=6 LINES=40 MAX_FILES=3 MAX_LINES=40 OVER=1")
        self.assertIn("- spec/models/a_spec.rb", out)
        self.assertIn("- db/schema.rb", out)
        self.assertIn("2 app/new.rb (renamed from app/old.rb)", out)
        self.assertIn("6 app/gone.rb", out)
        self.assertIn("10 app/models/a.rb", out)

    def test_size_defaults_without_workflow(self):
        os.remove(self.path(".github/workflows/pr-size-limit.yml"))
        r = self.run_script("size", "--base", "origin/develop")
        self.assertEqual(r.stdout.strip(), "FILES=6 LINES=40 MAX_FILES=20 MAX_LINES=500 OVER=0")

    # split: refusals, nothing written
    def test_split_refuses_missing_file(self):
        self.assert_refused(self.split([layer("feat/x-1-models", *MODELS), layer("feat/x-2-services", *SERVICES)]),
                            "web/page.tsx n'est dans aucune couche")

    def test_split_refuses_duplicate_file(self):
        layers = self.good_layers()
        layers[1]["files"].append("app/models/a.rb")
        self.assert_refused(self.split(layers), "app/models/a.rb est dans les couches 1 et 2")

    def test_split_refuses_unchanged_file(self):
        layers = self.good_layers()
        layers[2]["files"].append("README.md")
        self.assert_refused(self.split(layers), "README.md n'est pas modifié")

    def test_split_refuses_oversized_layer(self):
        layers = [layer("feat/x-1-back", *MODELS, *SERVICES), layer("feat/x-2-front", *FRONT)]
        self.assert_refused(self.split(layers), "couche 1 (feat/x-1-back) : 5 fichiers / 32 lignes, max 3 / 40")

    def test_split_ref_conflict_writes_nothing(self):
        # feat/x exists, so feat/x/1 cannot be created: the atomic update-ref must leave no branch behind.
        layers = self.good_layers()
        for i, l in enumerate(layers, 1):
            l["branch"] = f"feat/x/{i}"
        r = self.split(layers)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.git("branch", "--list", "feat/x/*"), "")

    # split: success
    def test_split_builds_the_stack_without_touching_the_user_checkout(self):
        self.write("app/models/a.rb", "staged edit\n")
        self.git("add", "app/models/a.rb")
        self.write("web/page.tsx", "unstaged edit\n")
        self.write("notes.txt", "untracked\n")
        before = [self.git(*c) for c in (["status", "--porcelain"], ["ls-files", "-s"], ["diff"], ["diff", "--cached"],
                                         ["symbolic-ref", "HEAD"], ["rev-parse", "feat/x"])]

        r = self.split(self.good_layers())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("LAYER=2 BRANCH=feat/x-2-services FILES=3 LINES=20", r.stdout)

        after = [self.git(*c) for c in (["status", "--porcelain"], ["ls-files", "-s"], ["diff"], ["diff", "--cached"],
                                        ["symbolic-ref", "HEAD"], ["rev-parse", "feat/x"])]
        self.assertEqual(before, after)
        self.assertEqual(after[-1], self.head)
        # chain: merge-base <- 1 <- 2 <- 3, last tree == HEAD tree
        self.assertEqual(self.git("rev-parse", "feat/x-1-models^"), self.git("merge-base", "origin/develop", "feat/x"))
        self.assertEqual(self.git("rev-parse", "feat/x-2-services^"), self.git("rev-parse", "feat/x-1-models"))
        self.assertEqual(self.git("rev-parse", "feat/x-3-front^"), self.git("rev-parse", "feat/x-2-services"))
        self.assertEqual(self.git("rev-parse", "feat/x-3-front^{tree}"), self.git("rev-parse", "feat/x^{tree}"))
        # layer 2 carries the rename and the deletion, layer 1 only its files
        status = self.git("diff", "--name-status", "-M", "feat/x-1-models", "feat/x-2-services").splitlines()
        self.assertIn("D\tapp/gone.rb", status)
        self.assertTrue(any(s.startswith("R") and s.endswith("app/old.rb\tapp/new.rb") for s in status), status)
        self.assertEqual(sorted(self.git("diff", "--name-only", "origin/develop", "feat/x-1-models").split()),
                         sorted(MODELS))
        self.assertEqual(self.git("log", "-1", "--format=%s", "feat/x-1-models"), "feat(x): feat/x-1-models")

    def test_split_existing_branch_needs_force_and_never_overwrites_checked_out(self):
        self.assertEqual(self.split(self.good_layers()).returncode, 0)
        self.assertIn("existe déjà", self.split(self.good_layers()).stderr)
        self.assertEqual(self.split(self.good_layers(), "--force").returncode, 0)
        layers = self.good_layers()
        layers[2]["branch"] = "feat/x"
        r = self.split(layers, "--force")
        self.assertIn("feat/x est checkée dans un worktree", r.stderr)
        self.assertEqual(self.git("rev-parse", "feat/x"), self.head)

    def test_split_accepts_old_rename_path_stdin_and_subdirectory(self):
        layers = self.good_layers()
        layers[1]["files"] = ["app/services/s.rb", "app/old.rb", "app/gone.rb"]
        plan = json.dumps({"layers": layers})
        r = self.run_script("split", "-", input=plan, cwd=self.path("app"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.git("rev-parse", "feat/x-3-front^{tree}"), self.git("rev-parse", "feat/x^{tree}"))


if __name__ == "__main__":
    unittest.main()
