// SPDX-License-Identifier: CC0-1.0
// solhint-disable one-contract-per-file, avoid-low-level-calls, no-inline-assembly

pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Test} from "forge-std/src/Test.sol";

interface IStorageAwareBeacon is IBeacon {
    function implementationAndStorageId() external view returns (bytes32);
    function beaconProxyUpgrader() external view returns (address);
}

interface IBeaconProxyUpgrader {
    function fallbackImplForStorageId(bytes12 storageId) external view returns (address);
    function upgradeStorage(bytes12 fromStorageId, bytes12 toStorageId, bytes calldata data) external;
}

// Packs a 12-byte storage layout id into the high bytes and an address into the low 20 bytes.
// This mirrors the proposed slot-compatible layout-aware beacon/proxy encoding.
library StorageAwareBeaconEncoding {
    bytes12 internal constant SINGLE_OWNER_STORAGE_ID = bytes12(keccak256("example.single-owner.v1"));
    bytes12 internal constant MULTI_OWNER_STORAGE_ID = bytes12(keccak256("example.multi-owner.v2"));

    function pack(bytes12 storageId, address account) internal pure returns (bytes32) {
        return bytes32(storageId) | bytes32(uint256(uint160(account)));
    }
}

// Deliberately tiny ERC-1271-like signature format used to make implementation routing visible in tests.
// Single-owner and multi-owner implementations accept different "signature kinds".
library ToySignatureEncoding {
    bytes4 internal constant EIP1271_VALID_SIGNATURE = 0x1626ba7e;
    bytes4 internal constant EIP1271_INVALID_SIGNATURE = 0xffffffff;
    bytes4 internal constant SINGLE_OWNER_SIGNATURE_KIND = 0x11111111;
    bytes4 internal constant MULTI_OWNER_SIGNATURE_KIND = 0x22222222;

    function decode(bytes memory signature) internal pure returns (bytes4 kind, address signer, bytes32 signedHash) {
        if (signature.length != 96) {
            return (bytes4(0), address(0), bytes32(0));
        }
        return abi.decode(signature, (bytes4, address, bytes32));
    }
}

// Minimal beacon that exposes both ERC-1967-compatible implementation() and a packed
// implementation/storage-id word for layout-aware proxies.
contract StorageAwareBeacon is IStorageAwareBeacon, Ownable {
    bytes32 internal implementationAndStorage;
    address internal beaconProxyUpgraderAddress;

    error BeaconInvalidImplementation(address implementation);
    error BeaconInvalidUpgrader(address upgrader);

    event Upgraded(address indexed implementation, bytes12 indexed storageId);

    constructor(address implementation_, bytes12 storageId_, address beaconProxyUpgraderAddress_, address owner_)
        Ownable(owner_)
    {
        if (beaconProxyUpgraderAddress_.code.length == 0) {
            revert BeaconInvalidUpgrader(beaconProxyUpgraderAddress_);
        }
        beaconProxyUpgraderAddress = beaconProxyUpgraderAddress_;
        _setImplementationAndStorageId(implementation_, storageId_);
    }

    function implementation() external view returns (address) {
        return address(uint160(uint256(implementationAndStorage)));
    }

    function implementationAndStorageId() external view returns (bytes32) {
        return implementationAndStorage;
    }

    function beaconProxyUpgrader() external view returns (address) {
        return beaconProxyUpgraderAddress;
    }

    function upgradeTo(address implementation_, bytes12 storageId_) external onlyOwner {
        _setImplementationAndStorageId(implementation_, storageId_);
    }

    function _setImplementationAndStorageId(address implementation_, bytes12 storageId_) private {
        if (implementation_.code.length == 0) {
            revert BeaconInvalidImplementation(implementation_);
        }
        implementationAndStorage = StorageAwareBeaconEncoding.pack(storageId_, implementation_);
        emit Upgraded(implementation_, storageId_);
    }
}

// Minimal upgrade manager. It stores storage-compatible fallback implementations and
// performs the one supported toy storage upgrade: single-owner slot 0 -> multi-owner array/set.
contract BeaconProxyUpgrader is IBeaconProxyUpgrader {
    mapping(bytes12 storageId => address implementation) internal fallbackImplementations;
    address internal managerOwner;

    error InvalidFallbackImplementation();
    error NotOwner();
    error UnsupportedUpgrade(bytes12 fromStorageId, bytes12 toStorageId);

    constructor(address owner_) {
        managerOwner = owner_;
    }

    function setFallbackImplementation(bytes12 storageId, address implementation_) external {
        if (msg.sender != managerOwner) {
            revert NotOwner();
        }
        if (implementation_.code.length == 0) {
            revert InvalidFallbackImplementation();
        }
        fallbackImplementations[storageId] = implementation_;
    }

    function fallbackImplForStorageId(bytes12 storageId) external view returns (address) {
        return fallbackImplementations[storageId];
    }

    function upgradeStorage(bytes12 fromStorageId, bytes12 toStorageId, bytes calldata) external virtual {
        if (
            fromStorageId != StorageAwareBeaconEncoding.SINGLE_OWNER_STORAGE_ID
                || toStorageId != StorageAwareBeaconEncoding.MULTI_OWNER_STORAGE_ID
        ) {
            revert UnsupportedUpgrade(fromStorageId, toStorageId);
        }

        // Toy storage upgrade:
        // - old layout: slot 0 stores nativeOwner
        // - new layout: slot 0 stores nativeOwners.length
        // - new layout: nativeOwners[0] stores old owner
        // - new layout: nativeOwnerSet[old owner] stores true
        assembly {
            let owner_ := sload(0)
            sstore(0, 1)
            mstore(0, 0)
            sstore(keccak256(0, 32), owner_)
            mstore(0, owner_)
            mstore(32, 1)
            sstore(keccak256(0, 64), 1)
        }
    }
}

// Reference layout-aware beacon proxy. It stores the beacon address in the low 20 bytes of
// the ERC-1967 beacon slot and its current storage layout id in the high 12 bytes.
contract StorageAwareBeaconProxy is Proxy {
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    event BeaconUpgraded(address indexed beacon);
    event StorageUpgradeCompleted(bytes12 indexed fromStorageId, bytes12 indexed toStorageId);

    error ERC1967InvalidBeacon(address beacon);
    error InvalidFallbackImplementation();
    error ERC1967InvalidImplementation(address implementation);
    error ERC1967NonPayable();

    constructor(address beacon_, bytes12 initialStorageId_, bytes memory data) payable {
        if (beacon_.code.length == 0) {
            revert ERC1967InvalidBeacon(beacon_);
        }

        address implementation = IStorageAwareBeacon(beacon_).implementation();
        if (implementation.code.length == 0) {
            revert ERC1967InvalidImplementation(implementation);
        }

        _storeBeaconWord(StorageAwareBeaconEncoding.pack(initialStorageId_, beacon_));
        emit BeaconUpgraded(beacon_);

        if (data.length != 0) {
            Address.functionDelegateCall(implementation, data);
        } else if (msg.value != 0) {
            revert ERC1967NonPayable();
        }
    }

    function _implementation() internal view override returns (address) {
        return address(uint160(uint256(IStorageAwareBeacon(_getBeacon()).implementationAndStorageId())));
    }

    function _fallback() internal override {
        bytes32 beaconWord = _loadBeaconWord();
        bytes12 currentStorageId = bytes12(beaconWord);
        address beacon = address(uint160(uint256(beaconWord)));
        bytes32 targetWord = IStorageAwareBeacon(beacon).implementationAndStorageId();
        bytes12 targetStorageId = bytes12(targetWord);
        address targetImplementation = address(uint160(uint256(targetWord)));

        if (currentStorageId == targetStorageId) {
            _delegate(targetImplementation);
        }

        // Only touch the manager when the proxy's initialized layout differs from the beacon target.
        address manager = IStorageAwareBeacon(beacon).beaconProxyUpgrader();
        (bool upgraded,) = manager.delegatecall(
            abi.encodeCall(IBeaconProxyUpgrader.upgradeStorage, (currentStorageId, targetStorageId, ""))
        );

        if (upgraded) {
            // The proxy only marks the target layout initialized after the storage upgrade succeeds.
            _storeBeaconWord(StorageAwareBeaconEncoding.pack(targetStorageId, beacon));
            emit StorageUpgradeCompleted(currentStorageId, targetStorageId);
            _delegate(targetImplementation);
        }

        // If the storage upgrade is unavailable or fails, keep the old layout id and route to code that
        // understands the proxy's current storage layout.
        address fallbackImplementation = IBeaconProxyUpgrader(manager).fallbackImplForStorageId(currentStorageId);
        if (fallbackImplementation == address(0)) {
            revert InvalidFallbackImplementation();
        }
        _delegate(fallbackImplementation);
    }

    function _getBeacon() internal view returns (address) {
        return address(uint160(uint256(_loadBeaconWord())));
    }

    function _loadBeaconWord() internal view returns (bytes32 beaconWord) {
        bytes32 slot = BEACON_SLOT;
        assembly {
            beaconWord := sload(slot)
        }
    }

    function _storeBeaconWord(bytes32 beaconWord) internal {
        bytes32 slot = BEACON_SLOT;
        assembly {
            sstore(slot, beaconWord)
        }
    }
}

// Layout v1: a single owner stored directly in slot 0.
contract ToySingleOwnerAccount is IERC1271 {
    address internal nativeOwner;

    error AlreadyInitialized();
    error NativeTransferFailed();
    error NotOwner();

    function initialize(address owner_) external {
        if (nativeOwner != address(0)) {
            revert AlreadyInitialized();
        }
        nativeOwner = owner_;
    }

    function owner() external view returns (address) {
        return nativeOwner;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (bytes4 kind, address signer, bytes32 signedHash) = ToySignatureEncoding.decode(signature);
        if (kind == ToySignatureEncoding.SINGLE_OWNER_SIGNATURE_KIND && signer == nativeOwner && signedHash == hash) {
            return ToySignatureEncoding.EIP1271_VALID_SIGNATURE;
        }
        return ToySignatureEncoding.EIP1271_INVALID_SIGNATURE;
    }

    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != nativeOwner) {
            revert NotOwner();
        }

        bool success;
        (success, result) = target.call{value: value}(data);
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    receive() external payable {}
}

// Layout v2: owners move to an array plus membership mapping.
contract ToyMultiOwnerAccount is IERC1271 {
    address[] internal nativeOwners;
    mapping(address owner => bool isOwner_) internal nativeOwnerSet;

    error AlreadyInitialized();
    error NativeTransferFailed();
    error NotOwner();

    function initialize(address[] calldata owners_) external {
        if (nativeOwners.length != 0) {
            revert AlreadyInitialized();
        }
        for (uint256 i = 0; i < owners_.length; ++i) {
            nativeOwners.push(owners_[i]);
            nativeOwnerSet[owners_[i]] = true;
        }
    }

    function owners() external view returns (address[] memory) {
        return nativeOwners;
    }

    function isOwner(address owner_) external view returns (bool) {
        return nativeOwnerSet[owner_];
    }

    function ownerCount() external view returns (uint256) {
        return nativeOwners.length;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (bytes4 kind, address signer, bytes32 signedHash) = ToySignatureEncoding.decode(signature);
        if (kind == ToySignatureEncoding.MULTI_OWNER_SIGNATURE_KIND && nativeOwnerSet[signer] && signedHash == hash) {
            return ToySignatureEncoding.EIP1271_VALID_SIGNATURE;
        }
        return ToySignatureEncoding.EIP1271_INVALID_SIGNATURE;
    }

    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result) {
        if (!nativeOwnerSet[msg.sender]) {
            revert NotOwner();
        }

        bool success;
        (success, result) = target.call{value: value}(data);
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    receive() external payable {}
}

// Test manager that does not support the requested upgrade path.
contract UnsupportedBeaconProxyUpgrader is BeaconProxyUpgrader {
    error UpgradeUnsupported();

    constructor(address owner_) BeaconProxyUpgrader(owner_) {}

    function upgradeStorage(bytes12, bytes12, bytes calldata) external pure override {
        revert UpgradeUnsupported();
    }
}

// Test manager whose upgrade path fails during execution.
contract RevertingBeaconProxyUpgrader is BeaconProxyUpgrader {
    error UpgradeFailed();

    constructor(address owner_) BeaconProxyUpgrader(owner_) {}

    function upgradeStorage(bytes12, bytes12, bytes calldata) external pure override {
        revert UpgradeFailed();
    }
}

contract StorageAwareBeaconReferenceTest is Test {
    event StorageUpgradeCompleted(bytes12 indexed fromStorageId, bytes12 indexed toStorageId);

    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    bytes12 public constant SINGLE_OWNER_STORAGE_ID = StorageAwareBeaconEncoding.SINGLE_OWNER_STORAGE_ID;
    bytes12 public constant MULTI_OWNER_STORAGE_ID = StorageAwareBeaconEncoding.MULTI_OWNER_STORAGE_ID;

    StorageAwareBeacon internal beacon;
    address internal beaconOwner;
    BeaconProxyUpgrader internal upgrader;
    ToyMultiOwnerAccount internal multiOwnerImplementation;
    ToySingleOwnerAccount internal singleOwnerImplementation;

    function setUp() public {
        beaconOwner = makeAddr("beaconOwner");
        singleOwnerImplementation = new ToySingleOwnerAccount();
        multiOwnerImplementation = new ToyMultiOwnerAccount();
        upgrader = new BeaconProxyUpgrader(address(this));

        // Both layouts need fallback implementations so old-storage proxies always have a safe target.
        upgrader.setFallbackImplementation(SINGLE_OWNER_STORAGE_ID, address(singleOwnerImplementation));
        upgrader.setFallbackImplementation(MULTI_OWNER_STORAGE_ID, address(multiOwnerImplementation));

        beacon = new StorageAwareBeacon(
            address(singleOwnerImplementation), SINGLE_OWNER_STORAGE_ID, address(upgrader), beaconOwner
        );
    }

    function testFleetUpgradesFromSingleOwnerToMultiOwnerLazily() public {
        // Two proxies start in the same fleet and share one beacon, but each owns independent storage.
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        ToySingleOwnerAccount aliceWallet = _deploySingleOwnerWallet(alice);
        ToySingleOwnerAccount bobWallet = _deploySingleOwnerWallet(bob);

        assertEq(aliceWallet.owner(), alice);
        assertEq(bobWallet.owner(), bob);
        _sendEthAsSingleOwner(aliceWallet, alice, 0.1 ether);
        _sendEthAsSingleOwner(bobWallet, bob, 0.2 ether);

        // The beacon moves the whole fleet to the multi-owner implementation/layout target.
        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        ToyMultiOwnerAccount aliceMultiOwnerWallet = ToyMultiOwnerAccount(payable(address(aliceWallet)));
        ToyMultiOwnerAccount bobMultiOwnerWallet = ToyMultiOwnerAccount(payable(address(bobWallet)));

        // Alice upgrades storage on first non-static execution against the new layout.
        _sendEthAsMultiOwner(aliceMultiOwnerWallet, alice, 0.3 ether);
        address[] memory aliceOwners = aliceMultiOwnerWallet.owners();
        assertEq(aliceOwners.length, 1);
        assertEq(aliceOwners[0], alice);
        assertTrue(aliceMultiOwnerWallet.isOwner(alice));
        assertEq(_currentStorageId(address(aliceWallet)), MULTI_OWNER_STORAGE_ID);

        // Bob remains on the old storage id until Bob's own proxy executes.
        assertEq(_currentStorageId(address(bobWallet)), SINGLE_OWNER_STORAGE_ID);

        // Bob then upgrades storage independently when his proxy first needs the new layout.
        _sendEthAsMultiOwner(bobMultiOwnerWallet, bob, 0.4 ether);
        address[] memory bobOwners = bobMultiOwnerWallet.owners();
        assertEq(bobOwners.length, 1);
        assertEq(bobOwners[0], bob);
        assertTrue(bobMultiOwnerWallet.isOwner(bob));
        assertEq(_currentStorageId(address(bobWallet)), MULTI_OWNER_STORAGE_ID);
    }

    function testPackedBeaconWordPreservesLow20ByteAddressDecoding() public view {
        // Tooling that decodes the low 20 bytes as an address still finds the implementation.
        bytes32 packed = beacon.implementationAndStorageId();

        assertEq(bytes12(packed), SINGLE_OWNER_STORAGE_ID);
        assertEq(address(uint160(uint256(packed))), address(singleOwnerImplementation));
    }

    function testSuccessfulMigrationEmitsEventFromProxy() public {
        address alice = makeAddr("eventOwner");
        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        vm.expectEmit(true, true, false, false, address(wallet));
        emit StorageUpgradeCompleted(SINGLE_OWNER_STORAGE_ID, MULTI_OWNER_STORAGE_ID);
        _sendEthAsMultiOwner(ToyMultiOwnerAccount(payable(address(wallet))), alice, 0.1 ether);

        assertEq(_currentStorageId(address(wallet)), MULTI_OWNER_STORAGE_ID);
    }

    function testMigrationFailureDoesNotEmitCompletionEvent() public {
        address alice = makeAddr("failedEventOwner");
        UnsupportedBeaconProxyUpgrader unsupportedUpgrader = new UnsupportedBeaconProxyUpgrader(address(this));
        unsupportedUpgrader.setFallbackImplementation(SINGLE_OWNER_STORAGE_ID, address(singleOwnerImplementation));
        beacon = new StorageAwareBeacon(
            address(singleOwnerImplementation), SINGLE_OWNER_STORAGE_ID, address(unsupportedUpgrader), beaconOwner
        );
        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        vm.recordLogs();
        _sendEthAsSingleOwner(wallet, alice, 0.1 ether);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
    }

    function testProxyFallsBackToCurrentStorageImplementationWhenUpgradeIsUnsupported() public {
        // If the manager has no upgrade path, the proxy must not run the target implementation
        // against old storage. It falls back to code registered for the current layout.
        address alice = makeAddr("fallbackOwner");
        UnsupportedBeaconProxyUpgrader unsupportedUpgrader = new UnsupportedBeaconProxyUpgrader(address(this));

        unsupportedUpgrader.setFallbackImplementation(SINGLE_OWNER_STORAGE_ID, address(singleOwnerImplementation));
        unsupportedUpgrader.setFallbackImplementation(MULTI_OWNER_STORAGE_ID, address(multiOwnerImplementation));

        beacon = new StorageAwareBeacon(
            address(singleOwnerImplementation), SINGLE_OWNER_STORAGE_ID, address(unsupportedUpgrader), beaconOwner
        );

        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        assertEq(wallet.owner(), alice);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
        _sendEthAsSingleOwner(wallet, alice, 0.1 ether);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
    }

    function testProxyFallsBackToCurrentStorageImplementationWhenUpgraderReverts() public {
        // A failed upgrader is treated like an incomplete storage upgrade: keep the old layout id and
        // continue routing to the current-layout fallback implementation.
        address alice = makeAddr("revertingUpgradeOwner");
        RevertingBeaconProxyUpgrader revertingUpgrader = new RevertingBeaconProxyUpgrader(address(this));

        revertingUpgrader.setFallbackImplementation(SINGLE_OWNER_STORAGE_ID, address(singleOwnerImplementation));
        revertingUpgrader.setFallbackImplementation(MULTI_OWNER_STORAGE_ID, address(multiOwnerImplementation));

        beacon = new StorageAwareBeacon(
            address(singleOwnerImplementation), SINGLE_OWNER_STORAGE_ID, address(revertingUpgrader), beaconOwner
        );

        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        assertEq(wallet.owner(), alice);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
        _sendEthAsSingleOwner(wallet, alice, 0.1 ether);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
    }

    function testStaticReadFallsBackToCurrentStorageImplementationBeforeUpgrade() public {
        // STATICCALL cannot complete a storage-writing upgrade. The proxy therefore serves a
        // read through the current-layout fallback and leaves its layout id unchanged.
        address alice = makeAddr("staticOwner");
        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        (bool success, bytes memory returnData) =
            address(wallet).staticcall(abi.encodeCall(ToySingleOwnerAccount.owner, ()));

        assertTrue(success);
        assertEq(abi.decode(returnData, (address)), alice);
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
    }

    function testStaticIsValidSignatureUsesCurrentStorageFallbackUntilUpgrade() public {
        // isValidSignature is a realistic static/read-only integration point. The toy signature
        // kind tells us whether the single-owner or multi-owner implementation answered.
        address alice = makeAddr("staticSignatureOwner");
        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);
        bytes32 hash = keccak256("toy signature hash");
        bytes memory singleOwnerSignature = _toySignature(ToySignatureEncoding.SINGLE_OWNER_SIGNATURE_KIND, alice, hash);
        bytes memory multiOwnerSignature = _toySignature(ToySignatureEncoding.MULTI_OWNER_SIGNATURE_KIND, alice, hash);

        assertEq(_staticIsValidSignature(address(wallet), hash, singleOwnerSignature), _validSignatureMagic());
        assertEq(_staticIsValidSignature(address(wallet), hash, multiOwnerSignature), _invalidSignatureMagic());

        // After the beacon upgrade, a strict static call cannot upgrade proxy storage, so the old
        // single-owner 1271 behavior remains active for this old-storage proxy.
        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        assertEq(_staticIsValidSignature(address(wallet), hash, singleOwnerSignature), _validSignatureMagic());
        assertEq(_staticIsValidSignature(address(wallet), hash, multiOwnerSignature), _invalidSignatureMagic());
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);

        // A later non-static call can upgrade proxy storage. After that, static reads use the new
        // multi-owner implementation behavior.
        ToyMultiOwnerAccount upgradedWallet = ToyMultiOwnerAccount(payable(address(wallet)));
        _sendEthAsMultiOwner(upgradedWallet, alice, 0.1 ether);

        assertEq(_staticIsValidSignature(address(wallet), hash, singleOwnerSignature), _invalidSignatureMagic());
        assertEq(_staticIsValidSignature(address(wallet), hash, multiOwnerSignature), _validSignatureMagic());
        assertEq(_currentStorageId(address(wallet)), MULTI_OWNER_STORAGE_ID);
    }

    function testStaticIsValidSignatureKeepsUsingFallbackWhenUpgradeIsUnsupported() public {
        // If no upgrade path is configured, static 1271 reads continue to use the old
        // current-layout implementation until an explicit upgrade path exists.
        address alice = makeAddr("staticSignatureFallbackOwner");
        UnsupportedBeaconProxyUpgrader unsupportedUpgrader = new UnsupportedBeaconProxyUpgrader(address(this));

        unsupportedUpgrader.setFallbackImplementation(SINGLE_OWNER_STORAGE_ID, address(singleOwnerImplementation));
        unsupportedUpgrader.setFallbackImplementation(MULTI_OWNER_STORAGE_ID, address(multiOwnerImplementation));

        beacon = new StorageAwareBeacon(
            address(singleOwnerImplementation), SINGLE_OWNER_STORAGE_ID, address(unsupportedUpgrader), beaconOwner
        );

        ToySingleOwnerAccount wallet = _deploySingleOwnerWallet(alice);
        bytes32 hash = keccak256("toy fallback signature hash");
        bytes memory singleOwnerSignature = _toySignature(ToySignatureEncoding.SINGLE_OWNER_SIGNATURE_KIND, alice, hash);
        bytes memory multiOwnerSignature = _toySignature(ToySignatureEncoding.MULTI_OWNER_SIGNATURE_KIND, alice, hash);

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(multiOwnerImplementation), MULTI_OWNER_STORAGE_ID);

        assertEq(_staticIsValidSignature(address(wallet), hash, singleOwnerSignature), _validSignatureMagic());
        assertEq(_staticIsValidSignature(address(wallet), hash, multiOwnerSignature), _invalidSignatureMagic());
        assertEq(_currentStorageId(address(wallet)), SINGLE_OWNER_STORAGE_ID);
    }

    function _deploySingleOwnerWallet(address owner_) internal returns (ToySingleOwnerAccount wallet) {
        // Deploy a proxy initialized through the current beacon implementation.
        wallet = ToySingleOwnerAccount(
            payable(
                new StorageAwareBeaconProxy(
                    address(beacon), SINGLE_OWNER_STORAGE_ID, abi.encodeCall(ToySingleOwnerAccount.initialize, (owner_))
                )
            )
        );
        vm.deal(address(wallet), 1 ether);
    }

    function _sendEthAsSingleOwner(ToySingleOwnerAccount wallet, address owner_, uint256 value) internal {
        // A successful execute call proves that single-owner storage is still interpreted correctly.
        address recipient = makeAddr(string.concat("singleOwnerRecipient", vm.toString(value)));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner_);
        wallet.execute(recipient, value, "");

        assertEq(recipient.balance, recipientBalanceBefore + value);
    }

    function _sendEthAsMultiOwner(ToyMultiOwnerAccount wallet, address owner_, uint256 value) internal {
        // A successful execute call proves that multi-owner storage was initialized correctly.
        address recipient = makeAddr(string.concat("multiOwnerRecipient", vm.toString(value)));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner_);
        wallet.execute(recipient, value, "");

        assertEq(recipient.balance, recipientBalanceBefore + value);
    }

    function _currentStorageId(address proxy) internal view returns (bytes12) {
        // Read the high 12 bytes of the ERC-1967 beacon slot, where this toy proxy stores its layout id.
        return bytes12(vm.load(proxy, BEACON_SLOT));
    }

    function _staticIsValidSignature(address wallet, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bytes4)
    {
        // Use a real EVM STATICCALL so storage upgrade attempts cannot persist or perform SSTORE.
        (bool success, bytes memory returnData) =
            wallet.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));

        assertTrue(success);
        return abi.decode(returnData, (bytes4));
    }

    function _toySignature(bytes4 kind, address signer, bytes32 hash) internal pure returns (bytes memory) {
        return abi.encode(kind, signer, hash);
    }

    function _validSignatureMagic() internal pure returns (bytes4) {
        return ToySignatureEncoding.EIP1271_VALID_SIGNATURE;
    }

    function _invalidSignatureMagic() internal pure returns (bytes4) {
        return ToySignatureEncoding.EIP1271_INVALID_SIGNATURE;
    }
}
