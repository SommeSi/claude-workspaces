"""Tests for ws-knowledge.py (no claude call). Run: python3 -m unittest scripts/test_ws_knowledge.py"""
import contextlib, importlib.util, io, json, os, tempfile, unittest

spec = importlib.util.spec_from_file_location(
    "ws_knowledge", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws-knowledge.py"))
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)


def line(type_, content):
    return json.dumps({"type": type_, "message": {"content": content}}) + "\n"


class Test(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        k.INBOX, k.FRICTIONS = f"{self.dir}/knowledge-inbox", f"{self.dir}/friction-inbox"

    def test_condense_keeps_failed_tool_calls_but_not_as_user_turns(self):
        path = f"{self.dir}/t.jsonl"
        with open(path, "w") as f:
            f.write(line("user", "ouvre le workspace"))
            f.write(line("assistant", [{"type": "tool_use", "id": "t1", "name": "Bash",
                                        "input": {"command": "bin/worktree-open w14"}}]))
            f.write(line("user", [{"type": "tool_result", "tool_use_id": "t1", "is_error": True,
                                   "content": "zsh: command not found: bin/worktree-open"}]))
            f.write(line("user", [{"type": "tool_result", "tool_use_id": "t2", "content": "ok"}]))
        body, turns, _, _, errors = k.condense(path)
        self.assertEqual((turns, errors), (1, 1))
        self.assertIn("TOOL ERROR (Bash bin/worktree-open w14): zsh: command not found", body)
        self.assertNotIn("ok", body.split("TOOL ERROR")[1])

    def test_frictions_grouped_by_target_then_consumed(self):
        for sid, target in (("aaaaaaaa-1", "workspace:open"), ("bbbbbbbb-2", "/workspace:open"), ("cccccccc-3", "ports")):
            k.save(k.FRICTIONS, "frictions", {"session_id": sid, "date": "2026-10-29T10:00:00"},
                   [{"target": target, "symptom": f"s {sid}", "suggestion": "x", "id": f"{sid[:8]}-f0"}])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            k.frictions_report()
        self.assertTrue(out.getvalue().startswith("2 session(s)  workspace:open"))
        with contextlib.redirect_stdout(io.StringIO()):
            k.consume(["aaaaaaaa-f0", "bbbbbbbb-f0"])
        self.assertEqual([f["target"] for f in k.pending(k.FRICTIONS, "frictions")], ["ports"])


if __name__ == "__main__":
    unittest.main()
