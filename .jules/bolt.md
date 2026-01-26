## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-14 - [Python System Script Optimization]
**Learning:** `subprocess.run(shell=True)` for simple file operations (read/write/ls) has massive overhead compared to native `os` module calls (~138x slower). Also, N+1 patterns where external binaries like `lspci` are called per-item are major bottlenecks.
**Action:** Replace `subprocess` with `os.readlink`, `os.listdir`, and `open()` for filesystem ops. Parse full output of tools like `lspci` once instead of iterating. In `dpdk-devbind.py`, this reduced overhead significantly.
