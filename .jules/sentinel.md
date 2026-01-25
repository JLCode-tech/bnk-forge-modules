## 2024-05-23 - [CRITICAL] Private Key Injection in User Data
**Vulnerability:** The infrastructure private key was being passed to the Jumphost's User Data and written to the filesystem. This exposed the key in the instance metadata (accessible to anyone on the instance) and on the disk.
**Learning:** Never pass sensitive data like private keys into `user_data`. Instance metadata is not a secure storage mechanism for long-lived secrets.
**Prevention:** Use SSH Agent Forwarding for accessing other instances from a bastion/jumphost. The private key should remain on the operator's machine.

## 2026-01-06 - [HIGH] Insecure Binary Download in Shell Scripts
**Vulnerability:** The `dpdk-setup.sh` script attempted to download `sriov-cni` binary from GitHub Releases using the `latest` tag without checksum verification. This introduced supply chain risk (mutable tag) and broke when the project stopped publishing binaries.
**Learning:** External dependencies in shell scripts must be pinned to specific versions and checksummed. Reliance on `latest` is fragile and insecure.
**Prevention:** Pin container image versions in Kubernetes manifests (e.g., `sriov-cni:v2.8.0`) and use DaemonSets for installation instead of ad-hoc binary downloads in UserData.

## 2026-01-06 - [HIGH] Unpinned Git Clone in Scripts
**Vulnerability:** Shell scripts were cloning Git repositories (`git clone`) without checking out a specific commit or tag. This exposed the infrastructure to immediate breakage or compromise if the upstream repository changed.
**Learning:** `git clone` pulls the default branch (usually main/master) which is mutable. Always pin to a specific immutable commit hash for reproducibility and security.
**Prevention:** Immediately after `git clone`, enter the directory and run `git checkout <commit-hash>`. Do not rely on tags as they can be moved.

## 2026-02-14 - [CRITICAL] Command Injection in Helper Scripts
**Vulnerability:** `dpdk-devbind.py` used `subprocess.run(shell=True)` with unvalidated user input (`pci_addr` and `driver`). This allowed arbitrary command execution via crafted arguments (e.g., `; rm -rf /`).
**Learning:** Helper scripts, even those intended for internal use, must treat arguments as untrusted. Python's `shell=True` is a dangerous default when combined with string interpolation.
**Prevention:** Always use `shell=False` (the default) and pass arguments as a list. Validate all inputs against strict allowlists (e.g., regex for PCI addresses). Use native language features (like `open()` or `os` module) instead of shelling out to `echo`, `ls`, or `readlink`.
