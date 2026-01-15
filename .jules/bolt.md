## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-15 - [Python Subprocess Optimization]
**Learning:** Python `subprocess.run(shell=True)` adds significant overhead and security risks compared to native `os` module calls.
**Action:** Replaced shell commands in `dpdk-devbind.py` with `os` module equivalents. This improves performance (no process spawning) and security (no shell injection).
