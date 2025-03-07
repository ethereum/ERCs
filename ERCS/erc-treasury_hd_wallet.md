---

eip: -1
title: Deterministic Account Hierarchy In Treasury Management
description: A standardized hierarchical deterministic (HD) wallet structure within the treasury management system, enforcing strict isolation between entities and departments through cryptographic key derivation paths.
author:
discussions-to: https://ethereum-magicians.org/t/new-erc-deterministic-account-hierarchy-in-treasury-management/23073
status: Draft
type: Standards Track
category: ERC
created: 2025-03-07
---

# Abstract

This proposal aims to provide a standardized method for on-chain treasury management of institutional assets, ensuring
secure private key generation, hierarchical management, and departmental permission isolation while supporting asset
security and transaction efficiency in multi-chain environments. By defining a unified derivation path and security
mechanisms, this proposal offers an efficient and secure solution for treasury management.

# Motivation

With the rapid development of blockchain and DeFi, secure management of on-chain assets has become critical. Traditional
private key management struggles to meet the security demands of large organizations in complex scenarios, where
hierarchical key management, permission controls, and multi-signature mechanisms are essential. This proposal provides a
standardized solution for institutional treasury management, ensuring asset security and transaction efficiency.

# Specification

### Derivation Path

We define the following derivation path to enable secure generation and management of on-chain account private keys for
treasury systems:

```latex
m/44'/60'/entity_id' / department_id' / account_index
```

Where:

- `**m**`: Master Private Key (root of the HD wallet).
- `**44'**`: Fixed value indicating BIP-44 compliance.
- `**60'**`: Coin type (60 for Ethereum).
- `**entity_id'**`: Hash of the subsidiary name, isolating keys between subsidiaries via hardened derivation.
- `**department_id'**`: Hash of the department name, isolating keys between departments via hardened derivation.
  *Note: Since Ethereum and EVM chains use an account model (not UTXO), the "change" layer in BIP-44 is omitted.*
- `**account_index**`: Account index under a department, using non-hardened derivation for unified management.

### Hash Conversion

entity_id and department_id are derived by hashing entity/department names into integers within 2^31 to 2^32-1:

```python
def hierarchical_hash_to_index(entity: str, department: str) -> tuple[int, int]:
# entity layer
entity_hash = sha256(f"ENTITY:{entity}".encode()).digest()
entity_index = int.from_bytes(entity_hash[:4], "big") % 2**31 + 2**31

# department layer
dept_hash = sha256(f"DEPT:{entity_hash}:{department}".encode()).digest()
dept_index = int.from_bytes(dept_hash[:4], "big") % 2**31 + 2**31

return entity_index, dept_index
```

### Extended Path for Role-Based Access

For finer access control (e.g., roles within departments):

```latex
m/60'/entity_id' / department_id' /role_id'/ account_index
```

- `**role_id'**`: Role identifier (hardened), isolating keys between roles.
  *Note: Omitting* `*44'*` *may cause incompatibility with wallets like MetaMask, requiring custom plugins.*

### Simplified Path for Smaller Entities

For entities without subsidiaries:

```latex
m/44'/60' / department_id' /0/ account_index
```

This path ensures compatibility with mainstream wallets (e.g., MetaMask).

### Key Derivation Algorithm

```latex
E = Map<entity, List<Department>>
n = Layer2 curve order
path = m/44'/60'/entity_id' / department_id' / account_index
BIP32() = Official BIP-0032 derivation function on secp256k1
hash = SHA256
root_key = BIP32(path)
for each E:
key = hash(root_key|hierarchical_hash_to_index(entity,department))
return key
```

p.s. This path is inspired by the path specification defined in BIP44, BIP0044 specifies a structure that contains 5
predefined hierarchical levels:

```text
`m / purpose' / coin' / account' / change / address_index`
```

# Rationale

The scenarios for which the proposal applies are:

1. **Company and Department Isolation**: Different subsidiaries within the group, as well as different departments
   within each subsidiary, can create isolated on-chain accounts. Enhanced derivation is used to isolate exposure risks.
2. **Group Unified Management Authority**: The group administrator holds the master private key, which can derive all
   subsidiary private keys, granting the highest authority to view and initiate transactions across the entire group,
   facilitating unified management by the group administrator.
3. **Shared Department Private Key**: If subsidiary A's administrator, Alice, needs to share accounts under subsidiary A
   with a new administrator, Bob, she only needs to share the master private key of subsidiary A. Accounts from various
   departments can then be derived from this key.
4. **Shared Audit Public Key**: If the audit department needs to audit transactions under a specific department, the
   extended public key of the specified department can be shared with the audit department. Through this extended public
   key, all subordinate public keys under the department can be derived, allowing the audit department to track all
   transactions associated with these public key addresses.

# Reference Implementation

```python
"""
Secure Treasury Management System
Enterprise-grade hierarchical deterministic wallet implementation compliant with BIP-44
"""

import hashlib
import logging
from typing import Tuple, Dict
from bip32utils import BIP32Key
from eth_account import Account
from mnemonic import Mnemonic  # Add BIP39 support

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("TreasurySystem")

class TreasurySystem:
def __init__(self, mnemonic: str):
"""
Initialize the treasury system
:param mnemonic: BIP-39 mnemonic (12/24 words)
"""
if not Mnemonic("english").check(mnemonic):
raise ValueError("Invalid BIP-39 mnemonic")

# Generate seed using standard BIP-39
self.seed = Mnemonic.to_seed(mnemonic, passphrase="")
self.root_key = BIP32Key.fromEntropy(self.seed)

logger.info("Treasury system initialized. Master key fingerprint: %s",
self.root_key.Fingerprint().hex())

@staticmethod
def _hierarchical_hash(entity: str, department: str) -> Tuple[int, int]:
"""
Hierarchical hash calculation (compliant with proposal spec)
Returns: (entity_index, department_index)
"""
# Entity hash
entity_hash = hashlib.sha256(f"ENTITY:{entity}".encode()).digest()
entity_index = int.from_bytes(entity_hash[:4], 'big') % 2**31 + 2**31

# Department hash (chained)
dept_input = f"DEPT:{entity_hash.hex()}:{department}".encode()
dept_hash = hashlib.sha256(dept_input).digest()
dept_index = int.from_bytes(dept_hash[:4], 'big') % 2**31 + 2**31

return entity_index, dept_index

def _derive_key(self, path: list) -> BIP32Key:
"""General key derivation method"""
current_key = self.root_key
for index in path:
if not isinstance(index, int):
raise TypeError(f"Invalid derivation index type: {type(index)}")
current_key = current_key.ChildKey(index)
return current_key

def generate_account(self, entity: str, department: str,
account_idx: int = 0) -> Dict[str, str]:
"""
Generate department account (BIP44 5-layer structure)
Path: m/44'/60'/entity'/dept'/account_idx
"""
e_idx, d_idx = self._hierarchical_hash(entity, department)

# BIP-44 standard path
derivation_path = [
0x8000002C,  # 44' (hardened)
0x8000003C,  # 60' (Ethereum)
e_idx,       # entity_index (hardened)
d_idx,       # department_index (hardened)
account_idx  # address index
]

key = self._derive_key(derivation_path)
priv_key = key.PrivateKey().hex()

return {
'path': f"m/44'/60'/{e_idx}'/{d_idx}'/{account_idx}",
'private_key': priv_key,  # Warning: Never expose this in production
'address': Account.from_key(priv_key).address
}

def get_audit_xpub(self, entity: str, department: str) -> str:
"""
Retrieve department-level extended public key (for auditing)
Path: m/44'/60'/entity'/dept'
"""
e_idx, d_idx = self._hierarchical_hash(entity, department)
path = [
0x8000002C,  # 44'
0x8000003C,  # 60'
e_idx,       # entity'
d_idx        # dept'
]
return self._derive_key(path).ExtendedKey()

def get_dept_xprv(self, entity: str, department: str) -> str:
"""
Get department-level extended private key (strictly controlled)
Path: m/44'/60'/entity'/dept'
"""
e_idx, d_idx = self._hierarchical_hash(entity, department)
path = [
0x8000002C,  # 44'
0x8000003C,  # 60'
e_idx,       # entity'
d_idx        # dept'
]
return self._derive_key(path).ExtendedKey()


@staticmethod
def derive_addresses_from_xpub(xpub: str, count: int = 20) -> list:
"""Derive addresses from extended public key (audit use)"""
audit_key = BIP32Key.fromExtendedKey(xpub)
return [
Account.from_key(
audit_key
.ChildKey(i)   # Address index
.PrivateKey()
).address
for i in range(count)
]


if __name__ == "__main__":
# Example usage (remove private key printing in production)
try:
# Use standard mnemonic
mnemo = Mnemonic("english")
mnemonic = mnemo.generate(strength=256)
treasury = TreasurySystem(mnemonic)
print(f"mnemonic: {mnemonic}")

print("\n=== Finance Department Account Generation ===")
finance_acc1 = treasury.generate_account("GroupA", "Finance", 0)
finance_acc2 = treasury.generate_account("GroupA", "Finance", 1)
print(f"Account1 path: {finance_acc1['path']}")
print(f"Account1 address: {finance_acc1['address']}")
print(f"Account1 private key: {finance_acc1['private_key']}")
print(f"Account2 path: {finance_acc2['path']}")
print(f"Account2 address: {finance_acc2['address']}")
print(f"Account2 private key: {finance_acc2['private_key']}")

print("\n=== Audit Verification Test===")
audit_xpub = treasury.get_audit_xpub("GroupA", "Finance")
print(f"Audit xpub: {audit_xpub}")
audit_addresses = TreasurySystem.derive_addresses_from_xpub(audit_xpub, 2)
print(f"Audit-derived addresses: {audit_addresses}")

assert finance_acc1['address'] in audit_addresses, "Audit verification failed"
assert finance_acc2['address'] in audit_addresses, "Audit verification failed"
print("✅ Audit verification successful")

print("\n=== Department Isolation Test ===")
other_dept_acc = treasury.generate_account("GroupA", "Audit", 0)
print(f"Account3 path: {other_dept_acc['path']}")
print(f"Account3 address: {other_dept_acc['address']}")
assert other_dept_acc['address'] not in audit_addresses, "Isolation breach"
print("✅ Department isolation effective")


print("\n=== Department Private Key Sharing Test ===")
# Gets the department layer extension private key
dept_xprv = treasury.get_audit_xpub("GroupA", "Finance").replace('xpub', 'xprv')  # 实际应通过专用方法获取
print(f"Fiance xprv: {dept_xprv}")
# Derive the account private key from the extension private key
dept_key = BIP32Key.fromExtendedKey(dept_xprv)
derived_acc0_key = dept_key.ChildKey(0).PrivateKey().hex()
derived_acc1_key = dept_key.ChildKey(1).PrivateKey().hex()
print(f"Fiance derived_acc0_key: {derived_acc0_key}")
print(f"Fiance derived_acc1_key: {derived_acc1_key}")
# Verify the private key derivation capability
assert derived_acc0_key == finance_acc1['private_key'], \
"Account 0 private key derivation failed"
assert derived_acc1_key == finance_acc2['private_key'], \
"Account 1 private key derivation failed"
print("✅ Private key derivation from department xprv successful")

except Exception as e:
logger.error("System error: %s", e, exc_info=True)
```

run script:

```shell
pip install bip32utils eth_account

python stms.py
```

output：

![img](https://intranetproxy.alipay.com/skylark/lark/0/2025/png/180109/1741141841059-ad7f8218-c2f4-4853-be2d-ebe7d03f47cb.png)

# Security Considerations

For treasury managers, hierarchical deterministic wallet management is more convenient, but it requires additional
consideration of protective measures for the master key, such as schemes for splitting and storing mnemonic phrases or
master keys.

# Backwards Compatibility

This standard complies with BIP39、BIP32、BIP44.

# Copyright

Copyright and related rights waived via CC0.