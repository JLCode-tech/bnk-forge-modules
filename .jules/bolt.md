## 2026-01-05 - [Shell Script Optimization]
**Learning:** Parsing files line-by-line using loops of `grep`, `awk`, and `head` is extremely inefficient due to process spawning overhead.
**Action:** Replace multi-process loops with single-pass `awk` parsing or `jq` (if applicable) and store results in Bash associative arrays. In `bnk/far-setup/scripts/parse-versions.sh`, this yielded a ~17x speedup (834ms -> 49ms).

## 2026-01-20 - [Network Interface Matching]
**Learning:** `ls | grep eth` matches substrings (e.g., `veth0`) which can include unwanted virtual interfaces, whereas glob `eth*` strictly matches prefixes. In setup scripts, loose matching can lead to incorrect configuration of virtual interfaces.
**Action:** Always use strict glob patterns (e.g., `eth*` or `eth[0-9]*`) and avoid `ls | grep` for file/interface enumeration to ensure correctness and performance.
