#!/usr/bin/env python3
"""ws-mintlify-drafts.py — PostToolUse hook on the Mintlify connector's `status` and `publish`.

A hook cannot call the connector itself, so it keeps what Claude last saw: `status` on the
deploy branch gives the pages edited but not published, a `publish` empties the list.
ws-session-nag.py shows the count at session start, next to the PRs to review.
Cache: ~/.claude-workspaces/cache/mintlify-drafts.json = {subdomain: {"at", "files"}}.
Event JSON on stdin; prints nothing.
"""
import json, os, sys, time

CACHE = os.path.expanduser("~/.claude-workspaces/cache/mintlify-drafts.json")


def payload(response):
    """The tool's JSON, whether the hook got it as a string, a dict or MCP content blocks."""
    if isinstance(response, dict) and "content" in response:
        response = response["content"]
    if isinstance(response, list):
        response = "".join(b.get("text", "") for b in response if isinstance(b, dict))
    if isinstance(response, str):
        try:
            return json.loads(response)
        except ValueError:
            return None
    return response if isinstance(response, dict) else None


def drafts(tool, response):
    """List of unpublished pages after this call, or None when the call tells nothing."""
    if tool.endswith("__publish"):
        return [] if payload(response) is not None else None
    data = payload(response)
    if not data or "editedFiles" not in data:
        return None
    if data.get("branch") != data.get("baseBranch"):  # a side branch is not what gets published
        return None
    nav = data.get("navDiff") or {}
    files = [f if isinstance(f, str) else f.get("path") or f.get("title") or "?" for f in data["editedFiles"]]
    return files + [f"(navigation) {k}" for k, v in nav.items() if v]


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    args = event.get("tool_input") or {}
    files = drafts(event.get("tool_name", ""), event.get("tool_response"))
    if files is None:
        return
    try:
        cache = json.load(open(CACHE))
    except (OSError, ValueError):
        cache = {}
    cache[args.get("subdomain") or "?"] = {"at": time.time(), "files": files}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + f".tmp{os.getpid()}"
    json.dump(cache, open(tmp, "w"))
    os.replace(tmp, CACHE)


if __name__ == "__main__":
    main()
