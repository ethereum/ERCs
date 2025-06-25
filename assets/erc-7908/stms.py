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
        entity_index = int.from_bytes(entity_hash[:4], 'big') | 0x80000000

        # Department hash (chained)
        dept_input = f"DEPT:{entity_hash.hex()}:{department}".encode()
        dept_hash = hashlib.sha256(dept_input).digest()
        dept_index = int.from_bytes(dept_hash[:4], 'big') | 0x80000000
        
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
        # 获取部门层扩展私钥
        dept_xprv = treasury.get_audit_xpub("GroupA", "Finance").replace('xpub', 'xprv')  # 实际应通过专用方法获取
        print(f"Fiance xprv: {dept_xprv}")
        # 从扩展私钥派生账户私钥
        dept_key = BIP32Key.fromExtendedKey(dept_xprv)
        derived_acc0_key = dept_key.ChildKey(0).PrivateKey().hex()
        derived_acc1_key = dept_key.ChildKey(1).PrivateKey().hex()
        print(f"Fiance derived_acc0_key: {derived_acc0_key}")
        print(f"Fiance derived_acc1_key: {derived_acc1_key}")
        # 验证私钥派生能力
        assert derived_acc0_key == finance_acc1['private_key'], \
            "Account 0 private key derivation failed"
        assert derived_acc1_key == finance_acc2['private_key'], \
            "Account 1 private key derivation failed"
        print("✅ Private key derivation from department xprv successful")

    except Exception as e:
        logger.error("System error: %s", e, exc_info=True)
