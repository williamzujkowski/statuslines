#!/usr/bin/env python3
"""Generate the fixtures that contain control characters.

These cannot be written as literal JSON in a shell heredoc, and keeping them
generated makes the intent readable: every string below is something a
repository, branch, or session name could legitimately contain, and none of it
may reach the user's terminal as an escape sequence.

Run: python3 test/fixtures/generate-hostile.py
"""

import json
import os

ESC = "\x1b"
BEL = "\x07"
BS = "\x08"
CR = "\r"
NL = "\n"

HERE = os.path.dirname(os.path.abspath(__file__))


def write(name, obj):
    path = os.path.join(HERE, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
    print("wrote", name)


# Every field here reaches the rendered line. If any of these escapes survives
# to stdout, a repository the user merely opened can repaint their terminal:
# clear the screen, hide text, or forge output above the prompt. This fixture
# is the regression test for docs/CODING-STANDARDS.md section 2.
write(
    "hostile-strings.json",
    {
        "session_id": "hostile",
        "session_name": "name" + ESC + "[31mRED" + ESC + "[0m" + BEL + "bell",
        "cwd": "/home/user/" + ESC + "[2J" + ESC + "[H" + "cleared/proj",
        "workspace": {
            "current_dir": "/home/user/" + ESC + "[2J" + ESC + "[H" + "cleared/proj",
            "git_worktree": "wt" + BS + BS + "back",
        },
        "model": {"id": "m", "display_name": "Opus" + ESC + "[5mBLINK"},
        "agent": {"name": "agent" + CR + "CR"},
        "worktree": {
            "name": "w",
            "branch": "feature/" + ESC + "[41mhighlight" + ESC + "[0m",
            "path": "/x",
        },
        "cost": {
            "total_cost_usd": 1.25,
            "total_duration_ms": 600000,
            "total_lines_added": 10,
            "total_lines_removed": 2,
        },
        "context_window": {"used_percentage": 45, "context_window_size": 200000},
    },
)

# A newline inside a value would desynchronize any newline-delimited parser.
# The engine terminates fields with RS for exactly this reason, and the gsub in
# lib/core.sh strips the newline before it can matter; this fixture keeps both
# defences honest.
write(
    "multiline-values.json",
    {
        "session_name": "first" + NL + "second",
        "workspace": {"current_dir": "/home/user/a" + NL + "b/proj"},
        "model": {"display_name": "Opus" + NL + "Injected"},
        "cost": {"total_cost_usd": 0.5, "total_duration_ms": 300000},
        "context_window": {"used_percentage": 12, "context_window_size": 200000},
    },
)

# Long enough that no terminal fits it, to exercise width fitting.
long_path = "/home/user/" + "/".join("level%d" % i for i in range(1, 15)) + "/statuslines"
write(
    "long-path.json",
    {
        "workspace": {"current_dir": long_path},
        "model": {"display_name": "Opus"},
        "cost": {
            "total_cost_usd": 2.5,
            "total_duration_ms": 3600000,
            "total_api_duration_ms": 1200000,
            "total_lines_added": 999,
            "total_lines_removed": 111,
        },
        "context_window": {
            "used_percentage": 71,
            "context_window_size": 200000,
            "total_input_tokens": 142000,
            "total_output_tokens": 3000,
            "current_usage": {
                "input_tokens": 2000,
                "output_tokens": 3000,
                "cache_read_input_tokens": 140000,
                "cache_creation_input_tokens": 0,
            },
        },
        "rate_limits": {"five_hour": {"used_percentage": 55.0, "resets_at": 1755500000}},
    },
)
