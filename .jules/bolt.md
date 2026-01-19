## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-19 - [Python Subprocess Overhead]
**Learning:** Using `subprocess.run(shell=True)` for simple filesystem operations (`ls`, `cat`, `readlink`) incurs massive overhead compared to native `os` module calls.
**Action:** Always prefer `os.listdir`, `os.readlink`, and `open()` in Python scripts. In `dpdk-devbind.py`, this pattern yielded a >2000x speedup for file operations in isolation.
