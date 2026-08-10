#!/usr/bin/env python3
"""Build the living Gherkin catalogue: every .feature in the estate, as ONE markdown page.

The owner's documentation verdict (2026-07-14): instead of the Ubiquitous-Language
generator's interactive site (hand-maintained Nouns/Verbs legends in every feature file),
the documentation is a small set of plain, versionable documents — generated javadoc,
the Allure summary that aggregate_allure.py already renders, and THIS: the specifications
themselves, collected and readable in one place.

The page groups features by workspace and repo, shows each feature's title, its free-text
description (with the old glossary legend blocks stripped — they die with the generator),
and its scenarios as a scannable list. Steps stay in the repos: this is the table of
contents of the system's behavior, not a copy of the spec suite.

Output: docs/features.md (versioned — reviewing a PR shows the spec surface changing).
"""

import os
import re
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACES = [("shared", HERE),
              ("portal", os.path.join(HERE, "..", "portal")),
              ("formula", os.path.join(HERE, "..", "formula"))]
SKIP_DIRS = {"target", "node_modules", ".git", "site"}
# the retired glossary generator's per-feature legends: strip them from descriptions
LEGEND_RE = re.compile(r"^\s*(Nouns|Verbs)\s*:\s*$", re.IGNORECASE)


def parse_feature(path):
    """The feature's surface: title, description lines, scenarios (keyword + name), tags."""
    title, description, scenarios = None, [], []
    in_description = False
    in_legend = False
    pending_tags = []
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if line.startswith("#"):
            continue
        if line.startswith("@"):
            pending_tags = line.split()
            continue
        m = re.match(r"(Feature)\s*:\s*(.*)", line)
        if m:
            title = m.group(2).strip()
            in_description = True
            continue
        m = re.match(r"(Scenario Outline|Scenario|Example|Rule|Background)\s*:\s*(.*)", line)
        if m:
            in_description = False
            in_legend = False
            # unnamed entries (the anonymous "Example:" under a Rule) carry no words of their
            # own — the Rule's title stands for them, so listing them would be pure noise
            if m.group(1) != "Background" and m.group(2).strip():
                scenarios.append((m.group(1), m.group(2).strip(), pending_tags))
            pending_tags = []
            continue
        if in_description:
            if LEGEND_RE.match(line):
                in_legend = True
                continue
            if in_legend:
                # legend entries are indented "SURFACE -> Identifier" mappings; a blank
                # line (or any non-mapping prose) ends the block
                if "->" in line or not line:
                    continue
                in_legend = False
            if line:
                description.append(line)
    return title, description, scenarios


def find_features(root):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in sorted(files):
            if f.endswith(".feature"):
                yield os.path.join(dirpath, f)


def main():
    out = ["# The estate's behavior, in its own words",
           "",
           f"Every `.feature` across the three workspaces — collected {date.today()} by",
           "`build_features.py`. Titles and scenario names only: the steps live with",
           "their repos, this page is the spec surface you can diff in one glance.",
           ""]
    grand = 0
    for ws_name, ws_root in WORKSPACES:
        ws_root = os.path.abspath(ws_root)
        if not os.path.isdir(ws_root):
            continue
        by_repo = {}
        for path in find_features(ws_root):
            rel = os.path.relpath(path, ws_root)
            repo = rel.split(os.sep)[0]
            by_repo.setdefault(repo, []).append(path)
        if not by_repo:
            continue
        out.append(f"## {ws_name}")
        out.append("")
        for repo in sorted(by_repo):
            out.append(f"### {repo}")
            out.append("")
            for path in by_repo[repo]:
                title, description, scenarios = parse_feature(path)
                rel = os.path.relpath(path, os.path.join(HERE, ".."))
                out.append(f"**{title or os.path.basename(path)}** — `{rel}`")
                out.append("")
                if description:
                    out.append("> " + " ".join(description))
                    out.append("")
                for kind, name, tags in scenarios:
                    tag_note = f" *({' '.join(tags)})*" if tags else ""
                    out.append(f"- {name}{tag_note}")
                grand += len(scenarios)
                out.append("")
    out.append(f"*{grand} scenarios in total.*")
    dest = os.path.join(HERE, "docs", "features.md")
    with open(dest, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"features catalogue: {dest} ({grand} scenarios)")


if __name__ == "__main__":
    main()
