#!/usr/bin/env python3
"""ws-mail-promises.py — what we promised clients by mail, so the client stops being the reminder.

  ws-mail-promises.py add --thread T --subject S --who W --promise P --due YYYY-MM-DD [--card URL]
  ws-mail-promises.py close --thread T     a new reply in that thread keeps or settles its promises
  ws-mail-promises.py due [--days N]       open promises due within N days (default 0), JSON

Per user, local: ~/.claude-workspaces/mail-promises.jsonl (one line per event, never in a repo).
Written by the `mail` skill when a draft is created; read by ws-session-nag.py.
"""
import argparse, datetime, json, os, sys

LEDGER = os.path.expanduser("~/.claude-workspaces/mail-promises.jsonl")


def events():
    try:
        return [json.loads(l) for l in open(LEDGER) if l.strip()]
    except OSError:
        return []


def open_promises():
    out = []
    for e in events():  # file order, not timestamps: close then add in the same second must keep the add
        if e["type"] == "close":
            out = [p for p in out if p["thread"] != e["thread"]]
        else:
            out.append(e)
    return out


def append(e):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "a") as f:
        f.write(json.dumps(e | {"at": datetime.datetime.now().isoformat(timespec="seconds")}, ensure_ascii=False) + "\n")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    for k in ("--thread", "--subject", "--who", "--promise", "--due"):
        a.add_argument(k, required=True)
    a.add_argument("--card")
    sub.add_parser("close").add_argument("--thread", required=True)
    sub.add_parser("due").add_argument("--days", type=int, default=0)
    o = ap.parse_args()
    if o.cmd == "add":
        datetime.date.fromisoformat(o.due)
        append({"type": "add", **{k: v for k, v in vars(o).items() if k != "cmd" and v}})
    elif o.cmd == "close":
        append({"type": "close", "thread": o.thread})
    else:
        limit = (datetime.date.today() + datetime.timedelta(days=o.days)).isoformat()
        print(json.dumps(sorted((p for p in open_promises() if p["due"] <= limit), key=lambda p: p["due"]),
                         ensure_ascii=False))


if __name__ == "__main__":
    if os.environ.get("WS_MAIL_PROMISES_SELFTEST"):  # python3 ws-mail-promises.py with the env var set
        import tempfile
        LEDGER = os.path.join(tempfile.mkdtemp(), "l.jsonl")
        append({"type": "add", "thread": "t1", "subject": "s", "who": "w", "promise": "p", "due": "2000-01-01"})
        append({"type": "add", "thread": "t2", "subject": "s", "who": "w", "promise": "p", "due": "2999-01-01"})
        assert [p["thread"] for p in open_promises()] == ["t1", "t2"]
        append({"type": "close", "thread": "t1"})
        assert [p["thread"] for p in open_promises()] == ["t2"]
        append({"type": "add", "thread": "t1", "subject": "s", "who": "w", "promise": "p2", "due": "2000-01-02"})
        assert [p["promise"] for p in open_promises() if p["thread"] == "t1"] == ["p2"]
        print("ok")
        sys.exit()
    main()
