## 2024-05-23 - [CRITICAL] Private Key Injection in User Data
**Vulnerability:** The infrastructure private key was being passed to the Jumphost's User Data and written to the filesystem. This exposed the key in the instance metadata (accessible to anyone on the instance) and on the disk.
**Learning:** Never pass sensitive data like private keys into `user_data`. Instance metadata is not a secure storage mechanism for long-lived secrets.
**Prevention:** Use SSH Agent Forwarding for accessing other instances from a bastion/jumphost. The private key should remain on the operator's machine.
