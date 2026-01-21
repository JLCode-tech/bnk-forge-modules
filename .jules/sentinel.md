# Sentinel Journal

## 2024-05-23 - Python Subprocess Command Injection
**Vulnerability:** The `dpdk-devbind.py` script used `subprocess.run(shell=True)` with unvalidated user input, allowing for root-level command injection via CLI arguments.
**Learning:** Even internal utility scripts can be attack vectors if they process external input (arguments, file contents) insecurely. `shell=True` is almost always a security smell.
**Prevention:**
1. Avoid `shell=True` in Python `subprocess` calls.
2. Use native Python libraries (`os`, `shutil`) for file I/O instead of shelling out to `cat`, `echo`, `ls`.
3. Validate all inputs against a strict allowlist (regex) before use.
