"""Tests for ws-mintlify-drafts.py (no network). Run: python3 -m unittest scripts/test_ws_mintlify_drafts.py"""
import importlib.util, json, os, unittest

spec = importlib.util.spec_from_file_location(
    "drafts", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws-mintlify-drafts.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

STATUS = "mcp__claude_ai_Mintlify__status"


def status(branch="main", edited=(), nav=None):
    return json.dumps({"branch": branch, "baseBranch": "main", "editedFiles": list(edited),
                       "navDiff": nav or {"created": [], "deleted": [], "moved": [], "renamed": []}})


class Drafts(unittest.TestCase):
    def test_counts_edited_pages_and_nav_changes(self):
        got = m.drafts(STATUS, status(edited=["a.mdx", {"path": "b.mdx"}], nav={"created": ["c"], "moved": []}))
        self.assertEqual(got, ["a.mdx", "b.mdx", "(navigation) created"])

    def test_reads_mcp_content_blocks(self):
        self.assertEqual(m.drafts(STATUS, [{"type": "text", "text": status(edited=["a.mdx"])}]), ["a.mdx"])

    def test_nothing_edited_is_zero(self):
        self.assertEqual(m.drafts(STATUS, status()), [])

    def test_side_branch_or_error_tells_nothing(self):
        self.assertIsNone(m.drafts(STATUS, status(branch="feat", edited=["a.mdx"])))
        self.assertIsNone(m.drafts(STATUS, "Error: unauthorized"))

    def test_publish_empties(self):
        self.assertEqual(m.drafts("mcp__claude_ai_Mintlify__publish", '{"ok": true}'), [])


if __name__ == "__main__":
    unittest.main()
