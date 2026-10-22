# VM provisioning

Provider-specific provisioning is intentionally deferred.

The selected VM must provide:

- A maintained Linux distribution
- SSH access from the host
- A full Docker engine inside the VM
- Storage that is not shared with host directories from other trust domains
- Enough CPU, memory, and disk for project containers
- An encrypted backup or snapshot strategy

Do not put private keys or tokens in provisioning files. Once a provider is
selected, record the decision in `docs/decisions/` and make the smallest
repeatable bootstrap needed to install SSH and Docker.

