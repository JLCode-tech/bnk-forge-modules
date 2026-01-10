## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-05 - [Python Script Optimization]
**Learning:** Python scripts invoking shell commands (via `subprocess` or `os.system`) for filesystem operations (`ls`, `readlink`) or redundant queries (`lspci`) create significant overhead due to process forking, especially in loops.
**Action:** Replace shell commands with native Python `os` and `sys` module functions (`os.listdir`, `os.readlink`) and batch hardware queries (e.g., parse full `lspci` output once) to achieve measurable speedups (e.g., ~2x faster device binding checks).
