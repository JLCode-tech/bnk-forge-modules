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

## 2026-05-23 - [CRITICAL] Command Injection in UserData Scripts
**Vulnerability:** The `dpdk-setup.sh` script used unvalidated and unquoted user inputs (`HUGEPAGES_2MI`, `S3_BUCKET`) in `sed` and `aws s3 cp` commands. This allowed arbitrary command execution via "Second Order Injection" (writing to `/etc/default/grub` which is later sourced) and direct shell injection.
**Learning:** Shell scripts running as root (UserData) are high-value targets. Variables expanded in commands (especially `sed` scripts or unquoted arguments) must be strictly validated.
**Prevention:** Implement strict input validation (e.g., regex for integers/alphanumeric) at the start of scripts. Quote all variable expansions. Avoid constructing code/config files dynamically from user input if possible.
