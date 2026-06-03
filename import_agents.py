#!/usr/bin/env python3
"""
import_agents.py — Bulk-import agency-agents markdown files into Odysseus.

Verified against:
  • pewdiepie-archdaemon/odysseus  (database.py schema, README data layout)
  • msitarzewski/agency-agents     (folder/filename conventions)

Targets TWO storage layers:
  1. data/presets.json    — system-prompt presets dropdown in chat UI
  2. data/app.db          — crew_members table (full agent personas / Agents tab)

Usage
─────
Dry-run first (default — nothing is written):
    ./venv/bin/python import_agents.py

Commit for real:
    ./venv/bin/python import_agents.py --commit

Target only one layer:
    ./venv/bin/python import_agents.py --commit --json-only
    ./venv/bin/python import_agents.py --commit --db-only

Override default paths:
    ./venv/bin/python import_agents.py --commit \\
        --agents-dir ~/my-agents \\
        --app-dir    ~/odysseus-pewdiepie
"""

import argparse
import json
import os
import re
import shutil
import sqlite3
import sys
import uuid
from datetime import datetime
from pathlib import Path

# ──────────────────────────────────────────────────────────────────────────────
#  Default Paths  (override with CLI flags)
# ──────────────────────────────────────────────────────────────────────────────

DEFAULT_ODYSSEUS_DIR = Path.home() / "odysseus-pewdiepie"
DEFAULT_AGENTS_DIR   = Path.home() / "agency-agents"

# ──────────────────────────────────────────────────────────────────────────────
#  Category Tag Map  (top-level folder → UI tag)
# ──────────────────────────────────────────────────────────────────────────────

CATEGORY_MAP: dict[str, str] = {
    "academic":           "[Academic]",
    "design":             "[Design]",
    "engineering":        "[Developer]",
    "finance":            "[Finance]",
    "game-development":   "[Game Dev]",
    "integrations":       "[Integrations]",
    "marketing":          "[Marketing]",
    "paid-media":         "[Paid Media]",
    "product":            "[Product]",
    "project-management": "[Project Mgmt]",
    "sales":              "[Sales]",
    "spatial-computing":  "[Spatial]",
    "specialized":        "[Specialized]",
    "strategy":           "[Strategy]",
    "support":            "[Support]",
    "testing":            "[Testing]",
}

# Top-level entries that are NOT agent categories
SKIP_TOP_LEVEL: set[str] = {"scripts", "examples", ".github", "integrations"}

# Tokens that should stay UPPERCASE after title-casing
FORCE_UPPER: set[str] = {
    "ui", "ux", "xr", "ar", "vr", "api", "seo", "cms", "mcp", "rtos",
    "erp", "crm", "orm", "ci", "cd", "qa", "sre", "llm", "ml", "ai",
    "pdf", "gtm", "b2b", "ppc", "apm", "sdk", "icp", "ddd", "vp",
    "cto", "ceo", "cfo", "hr", "pr", "roi", "kpi", "zk", "gpt",
}

# ──────────────────────────────────────────────────────────────────────────────
#  Name Formatting
# ──────────────────────────────────────────────────────────────────────────────

def _title_words(slug: str) -> str:
    """Convert a hyphen-slug to a title, uppercasing known abbreviations."""
    words = slug.replace("-", " ").split()
    out = []
    for w in words:
        low = w.lower()
        if low in FORCE_UPPER:
            out.append(w.upper())
        else:
            out.append(w.capitalize())
    return " ".join(out)


def parse_agent_name(md_file: Path, agents_root: Path) -> tuple[str, str]:
    """
    Return (category_tag, clean_title) for a given .md path.

    Strategy:
      - category_tag = CATEGORY_MAP[top_level_folder] or a generated fallback
      - clean_title  = filename stem with the top-level folder prefix stripped
                       (only if it cleanly matches), then title-cased

    Examples
    --------
    engineering/engineering-frontend-developer.md  →  [Developer] Frontend Developer
    design/design-ui-designer.md                   →  [Design] UI Designer
    game-development/unity/unity-architect.md      →  [Game Dev] Unity Architect
    game-development/game-designer.md              →  [Game Dev] Game Designer
    paid-media/paid-media-ppc-strategist.md        →  [Paid Media] PPC Strategist
    specialized/sales-outreach.md                  →  [Specialized] Sales Outreach
    """
    rel_parts = md_file.relative_to(agents_root).parts
    top_folder = rel_parts[0]

    category = CATEGORY_MAP.get(top_folder, f"[{_title_words(top_folder)}]")

    stem = md_file.stem  # filename without .md

    # Try stripping the exact top-level folder name as a hyphen-prefixed slug
    # e.g. folder "engineering" → strip "engineering-" from stem if present
    prefix = top_folder + "-"
    if stem.lower().startswith(prefix.lower()):
        remainder = stem[len(prefix):]
        # Only strip if the remainder is still meaningful (≥ 3 chars)
        if len(remainder) >= 3:
            stem = remainder

    clean_title = _title_words(stem)
    return category, clean_title


def format_display_name(category: str, title: str) -> str:
    return f"{category} {title}"


# ──────────────────────────────────────────────────────────────────────────────
#  Agent Discovery
# ──────────────────────────────────────────────────────────────────────────────

def discover_agents(agents_root: Path) -> list[dict]:
    """
    Walk agents_root, read every relevant .md, and return a list of dicts:
      {name, system_prompt, temperature, source_file}
    """
    agents = []
    warnings = []

    for md_file in sorted(agents_root.rglob("*.md")):
        rel = md_file.relative_to(agents_root)
        parts = rel.parts

        # Skip root-level .md (README, CONTRIBUTING, SECURITY, etc.)
        if len(parts) == 1:
            continue

        top_folder = parts[0]

        # Skip non-agent top-level folders
        if top_folder in SKIP_TOP_LEVEL:
            continue

        # Skip files named like README, CONTRIBUTING, etc. anywhere in tree
        if md_file.stem.upper() in {"README", "CONTRIBUTING", "CONTRIBUTING_ZH-CN",
                                     "SECURITY", "LICENSE", "CHANGELOG"}:
            continue

        try:
            content = md_file.read_text(encoding="utf-8", errors="replace").strip()
        except OSError as exc:
            warnings.append(f"  [WARN] Cannot read {md_file}: {exc}")
            continue

        if not content:
            continue

        category, title = parse_agent_name(md_file, agents_root)
        name = format_display_name(category, title)

        agents.append({
            "name":          name,
            "system_prompt": content,
            "temperature":   1.0,
            "source_file":   str(md_file.relative_to(agents_root)),
        })

    for w in warnings:
        print(w)

    return agents


# ──────────────────────────────────────────────────────────────────────────────
#  Storage Layer 1: presets.json
# ──────────────────────────────────────────────────────────────────────────────

def _load_presets_json(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        raw = path.read_text(encoding="utf-8")
        data = json.loads(raw)
        if isinstance(data, list):
            return data
        print(f"  [WARN] {path.name} is not a JSON array — treating as empty.")
    except Exception as exc:
        print(f"  [WARN] Could not parse {path.name}: {exc}")
    return []


def _save_presets_json(path: Path, presets: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(presets, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _protect_defaults_json(presets: list[dict]) -> tuple[list[dict], int]:
    """Prefix any preset whose name doesn't start with '[' with '[Default] '."""
    count = 0
    result = []
    for p in presets:
        name = p.get("name", "")
        if name and not name.startswith("["):
            p = {**p, "name": f"[Default] {name}"}
            count += 1
        result.append(p)
    return result, count


def import_to_presets_json(
    agents: list[dict],
    json_path: Path,
    dry_run: bool,
) -> dict:
    existing = _load_presets_json(json_path)
    existing_names = {p.get("name", "") for p in existing}

    # Count how many defaults would be protected
    defaults_would_tag = sum(
        1 for p in existing
        if p.get("name", "") and not p.get("name", "").startswith("[")
    )

    new_agents = [a for a in agents if a["name"] not in existing_names]
    skipped    = len(agents) - len(new_agents)

    if dry_run:
        return {
            "added":           len(new_agents),
            "skipped":         skipped,
            "defaults_tagged": defaults_would_tag,
        }

    # ── COMMIT ────────────────────────────────────────────────────────────────
    if json_path.exists():
        ts      = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup  = json_path.with_name(f"presets.bak.{ts}.json")
        shutil.copy2(json_path, backup)
        print(f"  presets.json backed up → {backup.name}")

    protected, defaults_tagged = _protect_defaults_json(existing)

    new_entries = [
        {
            "name":          a["name"],
            "system_prompt": a["system_prompt"],
            "temperature":   a["temperature"],
        }
        for a in new_agents
    ]

    _save_presets_json(json_path, protected + new_entries)

    return {
        "added":           len(new_agents),
        "skipped":         skipped,
        "defaults_tagged": defaults_tagged,
    }


# ──────────────────────────────────────────────────────────────────────────────
#  Storage Layer 2: app.db → crew_members
# ──────────────────────────────────────────────────────────────────────────────

def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone()
    return row is not None


def _get_crew_names(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute("SELECT name FROM crew_members").fetchall()
    return {r[0] for r in rows}


def _read_admin_user(app_dir: Path) -> str:
    """Try to discover the admin username from data/auth.json."""
    auth_path = app_dir / "data" / "auth.json"
    try:
        data = json.loads(auth_path.read_text(encoding="utf-8"))
        users = data if isinstance(data, list) else data.get("users", [])
        # Prefer explicit admin flag
        for u in users:
            if u.get("is_admin") is True:
                return u.get("username") or u.get("name") or "admin"
        # Fallback: first user
        if users:
            first = users[0]
            return first.get("username") or first.get("name") or "admin"
    except Exception:
        pass
    return "admin"


def import_to_crew_members(
    agents: list[dict],
    db_path: Path,
    app_dir: Path,
    dry_run: bool,
) -> dict:
    if not db_path.exists():
        return {
            "error":           f"Database not found: {db_path}",
            "added":           0,
            "skipped":         0,
            "defaults_tagged": 0,
        }

    try:
        conn = sqlite3.connect(str(db_path), timeout=10)
    except Exception as exc:
        return {"error": str(exc), "added": 0, "skipped": 0, "defaults_tagged": 0}

    try:
        if not _table_exists(conn, "crew_members"):
            return {
                "error":           "crew_members table not found in app.db",
                "added":           0,
                "skipped":         0,
                "defaults_tagged": 0,
            }

        existing_names = _get_crew_names(conn)
        new_agents     = [a for a in agents if a["name"] not in existing_names]
        skipped        = len(agents) - len(new_agents)

        # Count defaults that would be tagged
        defaults_would_tag = conn.execute(
            "SELECT COUNT(*) FROM crew_members WHERE name NOT LIKE '[%'"
        ).fetchone()[0]

        if dry_run:
            conn.close()
            return {
                "added":           len(new_agents),
                "skipped":         skipped,
                "defaults_tagged": defaults_would_tag,
            }

        # ── COMMIT ────────────────────────────────────────────────────────────
        ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = db_path.with_name(f"app.bak.{ts}.db")
        shutil.copy2(db_path, backup)
        print(f"  app.db backed up → {backup.name}")

        owner = _read_admin_user(app_dir)
        now   = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S.%f")

        # Protect existing defaults
        stale_rows = conn.execute(
            "SELECT id, name FROM crew_members WHERE name NOT LIKE '[%'"
        ).fetchall()
        defaults_tagged = 0
        for row_id, old_name in stale_rows:
            conn.execute(
                "UPDATE crew_members SET name=?, updated_at=? WHERE id=?",
                (f"[Default] {old_name}", now, row_id),
            )
            defaults_tagged += 1

        # Get current max sort_order
        max_sort = conn.execute(
            "SELECT COALESCE(MAX(sort_order), 0) FROM crew_members"
        ).fetchone()[0]

        # Insert new crew members
        for i, agent in enumerate(new_agents):
            conn.execute(
                """
                INSERT INTO crew_members
                    (id, owner, name, personality,
                     is_active, sort_order, is_default_assistant,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, 1, ?, 0, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    owner,
                    agent["name"],
                    agent["system_prompt"],
                    max_sort + 1 + i,
                    now,
                    now,
                ),
            )

        conn.commit()
        conn.close()

        return {
            "added":           len(new_agents),
            "skipped":         skipped,
            "defaults_tagged": defaults_tagged,
        }

    except Exception as exc:
        try:
            conn.close()
        except Exception:
            pass
        return {"error": str(exc), "added": 0, "skipped": 0, "defaults_tagged": 0}


# ──────────────────────────────────────────────────────────────────────────────
#  Pretty Reporting
# ──────────────────────────────────────────────────────────────────────────────

def _print_result(label: str, result: dict, dry_run: bool) -> None:
    prefix = "[DRY RUN] " if dry_run else ""
    if "error" in result:
        print(f"  {prefix}{label}: ERROR — {result['error']}")
        return
    verb = "Would add" if dry_run else "Added"
    print(
        f"  {prefix}{label}: "
        f"{verb} {result['added']}  |  "
        f"Already present {result['skipped']}  |  "
        f"Defaults re-tagged {result['defaults_tagged']}"
    )


# ──────────────────────────────────────────────────────────────────────────────
#  Entry Point
# ──────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bulk-import agency-agents markdown files into Odysseus.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Safe preview (nothing is written):
  ./venv/bin/python import_agents.py

  # Actually import everything:
  ./venv/bin/python import_agents.py --commit

  # Only update presets.json (skip crew_members):
  ./venv/bin/python import_agents.py --commit --json-only

  # Custom paths:
  ./venv/bin/python import_agents.py --commit \\
      --agents-dir ~/my-agents \\
      --app-dir    ~/odysseus-pewdiepie
""",
    )
    parser.add_argument(
        "--agents-dir",
        default=str(DEFAULT_AGENTS_DIR),
        metavar="PATH",
        help=f"Path to agency-agents directory (default: {DEFAULT_AGENTS_DIR})",
    )
    parser.add_argument(
        "--app-dir",
        default=str(DEFAULT_ODYSSEUS_DIR),
        metavar="PATH",
        help=f"Path to Odysseus app directory (default: {DEFAULT_ODYSSEUS_DIR})",
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        help="Actually write changes to disk. Without this flag the script only previews.",
    )
    parser.add_argument(
        "--json-only",
        action="store_true",
        help="Only update presets.json; skip crew_members in app.db.",
    )
    parser.add_argument(
        "--db-only",
        action="store_true",
        help="Only update crew_members in app.db; skip presets.json.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Print all discovered agent names and exit (implies dry-run).",
    )

    args   = parser.parse_args()
    dry_run = not args.commit

    agents_root = Path(args.agents_dir).expanduser().resolve()
    app_dir     = Path(args.app_dir).expanduser().resolve()
    data_dir    = app_dir / "data"
    json_path   = data_dir / "presets.json"
    db_path     = data_dir / "app.db"

    # ── Header ────────────────────────────────────────────────────────────────
    mode_label = "DRY RUN — nothing will be written" if dry_run else "COMMIT MODE — writing to disk"
    print()
    print("=" * 62)
    print(f"  Odysseus Agent Importer   [{mode_label}]")
    print("=" * 62)
    print()
    print(f"  Agents source : {agents_root}")
    print(f"  Odysseus dir  : {app_dir}")

    # ── Path validation ───────────────────────────────────────────────────────
    errors = []
    if not agents_root.exists():
        errors.append(f"  [ERROR] Agents directory not found: {agents_root}")
    if not app_dir.exists():
        errors.append(f"  [ERROR] Odysseus directory not found: {app_dir}")
    if errors:
        print()
        for e in errors:
            print(e)
        print()
        print("  Fix the paths above and try again.")
        print()
        sys.exit(1)

    print(f"  presets.json  : {'exists' if json_path.exists() else 'will be created'}")
    print(f"  app.db        : {'exists ✓' if db_path.exists() else 'NOT FOUND (skipping DB import)'}")
    print()

    # ── Discover ──────────────────────────────────────────────────────────────
    print("Scanning agent files…")
    agents = discover_agents(agents_root)

    if not agents:
        print("[ERROR] No agent .md files found. Check --agents-dir.")
        sys.exit(1)

    # Group by category for summary
    by_category: dict[str, list[str]] = {}
    for a in agents:
        tag = a["name"].split("]")[0] + "]" if "]" in a["name"] else "[?]"
        by_category.setdefault(tag, []).append(a["name"])

    print(f"Found {len(agents)} agents across {len(by_category)} categories:\n")
    for tag in sorted(by_category):
        print(f"  {tag:20s}  {len(by_category[tag]):3d} agents")
    print()

    # ── --list mode ───────────────────────────────────────────────────────────
    if args.list:
        print("Full agent list:")
        print("-" * 60)
        for a in agents:
            print(f"  {a['name']}")
        print()
        sys.exit(0)

    # ── Import: presets.json ──────────────────────────────────────────────────
    if not args.db_only:
        print(f"{'[DRY RUN] ' if dry_run else ''}Layer 1 — presets.json:")
        result = import_to_presets_json(agents, json_path, dry_run)
        _print_result("presets.json", result, dry_run)
        print()

    # ── Import: app.db → crew_members ────────────────────────────────────────
    if not args.json_only:
        print(f"{'[DRY RUN] ' if dry_run else ''}Layer 2 — crew_members (app.db):")
        if not db_path.exists():
            print("  app.db not found — skipping (start Odysseus once to create it, then re-run).")
        else:
            result = import_to_crew_members(agents, db_path, app_dir, dry_run)
            _print_result("crew_members", result, dry_run)
        print()

    # ── Footer ────────────────────────────────────────────────────────────────
    print("─" * 62)
    if dry_run:
        print("  This was a DRY RUN.  Nothing was written.")
        print("  Inspect the preview above, then re-run with --commit.")
    else:
        print("  Import complete!")
        print("  Restart Odysseus (or reload the page) to see the new agents.")
    print()


if __name__ == "__main__":
    main()
