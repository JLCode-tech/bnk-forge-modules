## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-05 - [Python Subprocess Optimization]
**Learning:** For infrastructure scripts, replacing `subprocess.run` with native `os` module calls (`readlink`, `listdir`, file I/O) avoids expensive process forking overhead.
**Action:** In `infra/aws/high-performance-nodes/scripts/dpdk-devbind.py`, this pattern improved performance by removing multiple subshells. Always prefer `os` calls for file system interactions.
