#!/usr/bin/env python3
"""
fix_crew_owner.py — Diagnose and fix crew_member visibility in Odysseus.

Run from ~/odysseus-pewdiepie:
    ./venv/bin/python fix_crew_owner.py          # diagnose only
    ./venv/bin/python fix_crew_owner.py --fix    # set owner=NULL on imported agents
"""

import argparse
import sqlite3
import sys
from pathlib import Path

# ── Try to locate the running app's actual database ───────────────────────────
CANDIDATES = [
    Path.home() / "odysseus-pewdiepie" / "data" / "app.db",
    Path("data") / "app.db",                               # cwd
    Path.home() / "Library" / "Application Support" / "Odysseus" / "data" / "app.db",
    Path.home() / ".odysseus" / "data" / "app.db",
]

def find_db() -> Path | None:
    for p in CANDIDATES:
        if p.exists():
            return p.resolve()
    return None


def diagnose(db_path: Path) -> None:
    print(f"\n  Database : {db_path}")
    conn = sqlite3.connect(str(db_path))

    # Crew member count + owner breakdown
    rows = conn.execute(
        "SELECT owner, COUNT(*) FROM crew_members GROUP BY owner ORDER BY COUNT(*) DESC"
    ).fetchall()
    total = conn.execute("SELECT COUNT(*) FROM crew_members").fetchone()[0]

    print(f"  Total crew_members: {total}")
    print()
    print("  Owner value         | Count")
    print("  " + "-" * 38)
    for owner, count in rows:
        label = repr(owner) if owner is not None else "NULL  (visible to all)"
        print(f"  {label:<28} | {count}")

    # Auth users
    print()
    auth_path = db_path.parent / "auth.json"
    if auth_path.exists():
        import json
        try:
            data = json.loads(auth_path.read_text(encoding="utf-8"))
            users = data if isinstance(data, list) else data.get("users", [])
            print("  auth.json users:")
            for u in users:
                name    = u.get("username") or u.get("name", "?")
                is_admin = u.get("is_admin", False) or u.get("role") == "admin"
                print(f"    {name}{'  (admin)' if is_admin else ''}")
        except Exception as e:
            print(f"  Could not read auth.json: {e}")
    else:
        print("  auth.json: not found")

    conn.close()


def fix(db_path: Path) -> None:
    """Set owner=NULL on all crew_members that were imported (have a [tag] name).
    NULL = visible to every user, regardless of who's logged in.
    """
    import shutil
    from datetime import datetime

    ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = db_path.with_name(f"app.fix.{ts}.db")
    shutil.copy2(db_path, backup)
    print(f"  Backed up → {backup.name}")

    conn = sqlite3.connect(str(db_path))
    # Only touch rows whose names start with [ (our imported agents)
    affected = conn.execute(
        "SELECT COUNT(*) FROM crew_members WHERE name LIKE '[%' AND owner IS NOT NULL"
    ).fetchone()[0]

    conn.execute(
        "UPDATE crew_members SET owner = NULL WHERE name LIKE '[%' AND owner IS NOT NULL"
    )
    conn.commit()
    conn.close()

    print(f"  Set owner=NULL on {affected} imported agent rows.")
    print("  These agents are now visible to ALL users in Odysseus.")
    print()
    print("  Restart Odysseus (or reload the page) to see the change.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Diagnose and fix crew_member owner visibility in Odysseus."
    )
    parser.add_argument("--fix",    action="store_true", help="Apply the owner=NULL fix")
    parser.add_argument("--db",     default=None,        help="Explicit path to app.db")
    args = parser.parse_args()

    db_path = Path(args.db).expanduser().resolve() if args.db else find_db()
    if db_path is None or not db_path.exists():
        print("[ERROR] Could not find app.db. Pass --db /path/to/data/app.db explicitly.")
        sys.exit(1)

    print("\n" + "=" * 54)
    print("  Odysseus Crew Owner Diagnostic" + ("  + FIX" if args.fix else ""))
    print("=" * 54)

    diagnose(db_path)

    if args.fix:
        print()
        fix(db_path)
    else:
        print()
        print("  Re-run with --fix to set owner=NULL on imported agents.")
        print("  (NULL = shared / visible to every user)")
    print()


if __name__ == "__main__":
    main()
