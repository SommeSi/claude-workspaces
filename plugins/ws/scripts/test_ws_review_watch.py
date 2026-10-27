"""Unit tests for ws-review-watch.py's decision. Run: python3 -m unittest scripts/test_ws_review_watch.py"""
import importlib.util, os, unittest

_spec = importlib.util.spec_from_file_location(
    "ws_review_watch", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws-review-watch.py"))
w = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(w)

ME, HEAD, OLD = "SebSusini", "a" * 40, "b" * 40


def review(id, by, state, commit=HEAD, body="", bot=False, at=None):
    return {"id": id, "by": by, "bot": bot, "state": state, "body": body, "commit": commit,
            "at": at or f"2026-10-27T10:{id:02d}:00Z"}


def thread(*authors, resolved=False, start=100):
    return {"resolved": resolved, "comments": [{"id": start + i, "by": a, "bot": False} for i, a in enumerate(authors)]}


def pr(**kw):
    base = {"repo": "SommeSi/sommesi-backend", "number": 1617, "title": "t", "url": "u", "draft": False,
            "labels": [], "base": "develop", "head": "feat/x", "head_sha": HEAD, "assignees": ["Uozak218"],
            "reviews": [], "threads": [], "comments": []}
    base.update(kw)
    return base


def decide(p, mode="ask", since=None, **kw):
    return w.decide(p, ME, mode, new=w.activity(p, ME, since or {}), **kw)


class Decide(unittest.TestCase):
    def test_approved_clean_green_auto_merges(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "merge")

    def test_approved_clean_green_ask_only_notifies(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "ask", checks="pass")[0], "ready")

    def test_approved_pending_checks_waits(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="pending")[0], "wait")

    def test_approved_failing_check_never_merges(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="fail")[0], "blocked")

    def test_approval_on_old_commit_is_not_mergeable(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED", commit=OLD)])
        calls = []
        action, _ = decide(p, "auto", checks=lambda: calls.append(1) or "pass")
        self.assertEqual(action, "stale")
        self.assertEqual(calls, [])  # checks not even looked at

    def test_changes_requested_fixes(self):
        p = pr(reviews=[review(1, "Uozak218", "CHANGES_REQUESTED", body="Renomme ce service")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "fix")

    def test_approved_with_unresolved_thread_fixes(self):
        p = pr(reviews=[review(1, "Uozak218", "APPROVED")], threads=[thread("Uozak218")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "fix")

    def test_codex_thread_fixes(self):
        p = pr(reviews=[review(1, "chatgpt-codex-connector", "COMMENTED", body="<!-- receipt -->", bot=True)],
               threads=[thread("chatgpt-codex-connector")])
        self.assertEqual(decide(p)[0], "fix")

    def test_already_handled_waits_for_reviewer(self):
        p = pr(reviews=[review(1, "Uozak218", "CHANGES_REQUESTED", body="x")], threads=[thread("Uozak218", ME)])
        since = {"review": 1, "comment": 101}
        self.assertEqual(decide(p, since=since)[0], "waiting")

    def test_new_reply_in_thread_fixes_again(self):
        p = pr(reviews=[review(1, "Uozak218", "CHANGES_REQUESTED", body="x")], threads=[thread("Uozak218", ME, "Uozak218")])
        self.assertEqual(decide(p, since={"review": 1, "comment": 101})[0], "fix")

    def test_fix_agent_running_does_nothing(self):
        p = pr(reviews=[review(1, "Uozak218", "CHANGES_REQUESTED", body="x")])
        self.assertEqual(decide(p, running=True)[0], "running")

    def test_approval_by_non_assignee_does_not_count(self):
        p = pr(reviews=[review(1, "someone", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "none")

    def test_later_changes_requested_blocks_merge(self):
        p = pr(assignees=[], reviews=[review(1, "Uozak218", "APPROVED"), review(2, "florian", "CHANGES_REQUESTED", body="non")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "fix")

    def test_base_main_skipped(self):
        p = pr(base="main", reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "skip")

    def test_no_autofix_label_skipped(self):
        p = pr(labels=["no-autofix"], reviews=[review(1, "Uozak218", "CHANGES_REQUESTED", body="x")])
        self.assertEqual(decide(p)[0], "skip")

    def test_draft_skipped(self):
        p = pr(draft=True, reviews=[review(1, "Uozak218", "APPROVED")])
        self.assertEqual(decide(p, "auto", checks="pass")[0], "skip")


class Activity(unittest.TestCase):
    def test_ignores_me_and_bot_pr_comments(self):
        p = pr(comments=[{"id": 1, "by": ME, "bot": False, "body": "x"},
                         {"id": 2, "by": "chatgpt-codex-connector", "bot": True, "body": "summary"},
                         {"id": 3, "by": "Uozak218", "bot": False, "body": "question"}],
               threads=[thread(ME, "Uozak218")])
        a = w.activity(p, ME, {})
        self.assertEqual([c["id"] for c in a["issue"]], [3])
        self.assertEqual([c["id"] for c in a["comments"]], [101])

    def test_summary_text(self):
        p = pr(reviews=[review(1, "Uozak218", "CHANGES_REQUESTED")], threads=[thread("Uozak218"), thread("Uozak218", start=200)])
        self.assertEqual(w.summary(p, w.activity(p, ME, {})), "#1617 relue par Uozak218 : changements demandés, 2 commentaires")


if __name__ == "__main__":
    unittest.main()
