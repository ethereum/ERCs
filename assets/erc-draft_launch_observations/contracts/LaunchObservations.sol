// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ILaunchObservations} from "./ILaunchObservations.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface ILaunchDirectoryTokenOf {
    function tokenOf(bytes32 launchId) external view returns (address);
}

/// @title LaunchObservations (reference implementation)
/// @notice Permissionless, ownerless, append-only registry of block-pinned launch observations.
contract LaunchObservations is ILaunchObservations, IERC165 {
    // Limits
    uint256 public constant MAX_FINDINGS = 32;
    uint256 public constant MAX_URI_LENGTH = 512;
    uint256 public constant NOT_READ = type(uint256).max;
    uint256 public constant MAX_BPS = 10_000;

    // Block history. On Arbitrum chains `block.number` is the parent chain's block, so the chain's own block number is
    // read from ArbSys; past block hashes come from the EIP-2935 history contract where the chain deploys it.
    address public constant ARB_SYS = address(100);
    address public constant HISTORY_STORAGE = 0x0000F90827F1C53a10cb7A02335B175320002935;
    uint256 public constant HISTORY_WINDOW = 8191;
    uint256 public constant BLOCKHASH_WINDOW = 256;

    // Key derivation
    bytes32 public constant TOKEN_SCOPED = keccak256("erc.launch-observations.token-scoped");
    bytes32 public constant VENUE_DECLARED = keccak256("erc.launch-observations.venue-declared");

    // Core finding kinds
    bytes32 public constant FIRST_BLOCK_SHARE = keccak256("erc.launch-observations.first-block-share");
    bytes32 public constant EARLY_BUYER_SHARE = keccak256("erc.launch-observations.early-buyer-share");
    bytes32 public constant CREATOR_PRIOR_LAUNCHES = keccak256("erc.launch-observations.creator-prior-launches");
    bytes32 public constant FUNDING_LINKED_SHARE = keccak256("erc.launch-observations.funding-linked-share");
    bytes32 public constant PRODUCT_LABEL = keccak256("erc.launch-observations.product-label");

    // ERC-8376 base signals, measured from launch to the observed block
    bytes32 public constant DEPLOYER_SUPPLY_SHARE = keccak256("erc.launch-observations.signal.deployerSupplyShare");
    bytes32 public constant INSIDER_ALLOCATION_SHARE = keccak256("erc.launch-observations.signal.insiderAllocationShare");
    bytes32 public constant SNIPER_CONCENTRATION = keccak256("erc.launch-observations.signal.sniperConcentration");
    bytes32 public constant LP_LOCKED_SHARE = keccak256("erc.launch-observations.signal.lpLockedShare");
    bytes32 public constant LP_LOCK_REMAINING = keccak256("erc.launch-observations.signal.lpLockRemaining");
    bytes32 public constant LIQUIDITY_REMOVED = keccak256("erc.launch-observations.signal.liquidityRemoved");
    bytes32 public constant DEPLOYER_SELL_RATIO = keccak256("erc.launch-observations.signal.deployerSellRatio");
    bytes32 public constant PROCEEDS_WITHDRAWN_SHARE = keccak256("erc.launch-observations.signal.proceedsWithdrawnShare");
    bytes32 public constant PRIVILEGED_POWERS = keccak256("erc.launch-observations.signal.privilegedPowers");
    bytes32 public constant PRIOR_UPHELD_CLAIMS = keccak256("erc.launch-observations.signal.priorUpheldClaims");
    bytes32 public constant SUPPLY_INFLATION = keccak256("erc.launch-observations.signal.supplyInflation");
    bytes32 public constant WASH_TRADE_RATIO = keccak256("erc.launch-observations.signal.washTradeRatio");

    // Product label values
    uint256 public constant LABEL_FOUND = 1;
    uint256 public constant LABEL_PARTLY_FOUND = 2;
    uint256 public constant LABEL_NOT_FOUND = 3;

    error InvalidKey();
    error LaunchNotListed();
    error InvalidObservedBlock();
    error InvalidObservedBlockHash();
    error StaleObservedBlock(uint64 latestObservedBlock);
    error InvalidReport();
    error TooManyFindings();
    error InvalidFinding(uint256 index);
    error DuplicateFinding(uint256 index);
    error TallyBelowFindings();
    error InvalidIdentity();

    struct Identity {
        address registry;
        uint256 agentId;
    }

    address private immutable _directory;

    uint256 private _count;
    mapping(uint256 => Observation) private _observations;
    mapping(uint256 => Finding[]) private _findings;
    mapping(bytes32 => uint256[]) private _byKey;
    mapping(bytes32 => mapping(address => uint256[])) private _byKeyDetector;
    mapping(bytes32 => address[]) private _detectors;
    mapping(address => Identity) private _identity;
    // tokenKey(chainId, token) => detector => its observation of the token with the highest observed block, any key kind
    mapping(bytes32 => mapping(address => uint256)) private _latestByToken;

    constructor(address directory) {
        _directory = directory;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILaunchObservations).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function launchDirectory() external view returns (address) {
        return _directory;
    }

    function tokenKey(uint256 chainId, address token) public pure returns (bytes32) {
        return keccak256(abi.encode(TOKEN_SCOPED, chainId, token));
    }

    function declarationKey(uint256 chainId, bytes32 declarationId) public pure returns (bytes32) {
        return keccak256(abi.encode(VENUE_DECLARED, chainId, declarationId));
    }

    // ---------------------------------------------------------------- writing

    function recordObservation(ObservationInput calldata input, Finding[] calldata findings)
        external
        returns (uint256 observationId, bytes32 launchKey)
    {
        uint256 chainId;
        address token;
        (launchKey, chainId, token) = _resolveKey(input);

        if (input.observedBlock == 0) revert InvalidObservedBlock();
        if (chainId == block.chainid) _checkOwnChainBlock(input.observedBlock, input.observedBlockHash);

        uint256 uriLength = bytes(input.reportURI).length;
        if (input.reportHash == bytes32(0) || uriLength == 0 || uriLength > MAX_URI_LENGTH) revert InvalidReport();

        _checkFindings(findings, input.tally);

        observationId = ++_count;
        _store(observationId, launchKey, chainId, token, input);
        _emitRecorded(observationId, input.observedBlockHash);
        _storeFindings(observationId, findings);
    }

    function _store(uint256 observationId, bytes32 key, uint256 chainId, address token, ObservationInput calldata input)
        private
    {
        uint256[] storage history = _byKeyDetector[key][msg.sender];
        uint256 previous;
        if (history.length == 0) {
            _detectors[key].push(msg.sender);
        } else {
            previous = history[history.length - 1];
            uint64 last = _observations[previous].observedBlock;
            if (input.observedBlock < last) revert StaleObservedBlock(last);
        }
        history.push(observationId);
        _byKey[key].push(observationId);

        // Latest by token, across both key kinds: the highest observed block wins, and on a tie the one recorded last.
        mapping(address => uint256) storage byToken = _latestByToken[tokenKey(chainId, token)];
        uint256 current = byToken[msg.sender];
        if (current == 0 || input.observedBlock >= _observations[current].observedBlock) {
            byToken[msg.sender] = observationId;
        }

        Observation storage o = _observations[observationId];
        // The link is copied only while it still holds: a transferred identity is not claimed for this observation.
        Identity storage id = _identity[msg.sender];
        address idRegistry = id.registry;
        if (idRegistry != address(0)) {
            uint256 agentId = id.agentId;
            if (_holdsIdentity(idRegistry, agentId, msg.sender)) {
                o.identityRegistry = idRegistry;
                o.agentId = agentId;
            }
        }
        o.launchKey = key;
        o.kind = input.kind;
        o.chainId = chainId;
        o.token = token;
        o.detector = msg.sender;
        o.observedBlock = input.observedBlock;
        o.recordedAt = uint64(block.timestamp);
        o.supersedes = previous;
        o.tally = input.tally;
        o.reportHash = input.reportHash;
        o.reportURI = input.reportURI;
        o.evidenceRoot = input.evidenceRoot;
        // An ERC-8462 venue-scoped declaration id is kept so a reader joins the observation to the declaration.
        if (input.kind == KeyKind.Erc8462Venue) o.declarationId = input.launchId;
    }

    function _storeFindings(uint256 observationId, Finding[] calldata findings) private {
        Finding[] storage stored = _findings[observationId];
        for (uint256 i = 0; i < findings.length; i++) {
            Finding calldata f = findings[i];
            stored.push(f);
            emit FindingObserved(observationId, f.kind, f.value, f.param, f.lean);
        }
    }

    function setDetectorIdentity(address identityRegistry, uint256 agentId) external {
        if (identityRegistry == address(0)) {
            if (agentId != 0) revert InvalidIdentity();
        } else if (!_holdsIdentity(identityRegistry, agentId, msg.sender)) {
            revert InvalidIdentity();
        }
        _identity[msg.sender] = Identity(identityRegistry, agentId);
        emit DetectorIdentitySet(msg.sender, identityRegistry, agentId);
    }

    // ---------------------------------------------------------------- reading

    function detectorIdentity(address detector) external view returns (address identityRegistry, uint256 agentId) {
        Identity memory id = _identity[detector];
        return (id.registry, id.agentId);
    }

    function getObservation(uint256 observationId)
        external
        view
        returns (Observation memory observation, Finding[] memory findings)
    {
        return (_observations[observationId], _findings[observationId]);
    }

    function latestOf(bytes32 launchKey, address detector) external view returns (uint256) {
        uint256[] storage history = _byKeyDetector[launchKey][detector];
        return history.length == 0 ? 0 : history[history.length - 1];
    }

    function latestByToken(uint256 chainId, address token, address detector) public view returns (uint256) {
        return _latestByToken[tokenKey(chainId, token)][detector];
    }

    function latestFinding(uint256 chainId, address token, address detector, bytes32 kind, uint64 param)
        external
        view
        returns (uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean)
    {
        observationId = latestByToken(chainId, token, detector);
        if (observationId == 0) return (0, 0, 0, NOT_READ, Lean.None);
        Observation storage o = _observations[observationId];
        (value, lean) = _findingOf(observationId, kind, param);
        return (observationId, o.observedBlock, o.recordedAt, value, lean);
    }

    /// @dev Gas is linear in the length of `detectors`: one by-token lookup and one findings scan per detector tried.
    function latestFindingFrom(uint256 chainId, address token, address[] calldata detectors, bytes32 kind, uint64 param)
        external
        view
        returns (address detector, uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean)
    {
        mapping(address => uint256) storage byToken = _latestByToken[tokenKey(chainId, token)];
        uint256 n = detectors.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 id = byToken[detectors[i]];
            if (id == 0) continue;
            (value, lean) = _findingOf(id, kind, param);
            if (value == NOT_READ) continue;
            Observation storage o = _observations[id];
            return (detectors[i], id, o.observedBlock, o.recordedAt, value, lean);
        }
        return (address(0), 0, 0, 0, NOT_READ, Lean.None);
    }

    function observationsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (uint256[] memory) {
        return _page(_byKey[launchKey], start, limit);
    }

    function observationsBy(bytes32 launchKey, address detector, uint256 start, uint256 limit)
        external
        view
        returns (uint256[] memory)
    {
        return _page(_byKeyDetector[launchKey][detector], start, limit);
    }

    function detectorsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (address[] memory out) {
        address[] storage all = _detectors[launchKey];
        uint256 n = _pageLength(all.length, start, limit);
        out = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = all[start + i];
        }
    }

    // ---------------------------------------------------------------- internal

    /// @dev The number the chain's own blocks carry, as `eth_blockNumber` returns it. On an Arbitrum chain
    /// `block.number` is the parent chain's block, so the number is read from ArbSys at 0x64 when it answers.
    function _chainBlockNumber() internal view returns (uint256 number, bool arbitrum) {
        if (ARB_SYS.code.length != 0) {
            (bool ok, bytes memory ret) = ARB_SYS.staticcall(abi.encodeWithSignature("arbBlockNumber()"));
            if (ok && ret.length >= 32) return (abi.decode(ret, (uint256)), true);
        }
        return (block.number, false);
    }

    /// @dev On the registry's own chain the block must exist and its hash must be given. The hash must match the
    /// EIP-2935 history contract where it answers for the block (8191 blocks), else `blockhash` within 256 blocks on a
    /// chain whose `blockhash` takes its own block numbers. Otherwise it is emitted unchecked for readers to compare.
    function _checkOwnChainBlock(uint64 observedBlock, bytes32 observedBlockHash) private view {
        (uint256 current, bool arbitrum) = _chainBlockNumber();
        if (observedBlock >= current) revert InvalidObservedBlock();
        if (observedBlockHash == bytes32(0)) revert InvalidObservedBlockHash();
        uint256 age = current - observedBlock;
        bytes32 known = bytes32(0);
        if (age <= HISTORY_WINDOW && HISTORY_STORAGE.code.length != 0) {
            (bool ok, bytes memory ret) = HISTORY_STORAGE.staticcall(abi.encode(uint256(observedBlock)));
            if (ok && ret.length >= 32) known = abi.decode(ret, (bytes32));
        }
        if (known == bytes32(0) && !arbitrum && age <= BLOCKHASH_WINDOW) known = blockhash(observedBlock);
        if (known != bytes32(0) && known != observedBlockHash) revert InvalidObservedBlockHash();
    }

    function _emitRecorded(uint256 observationId, bytes32 observedBlockHash) private {
        Observation storage o = _observations[observationId];
        emit ObservationRecorded(
            observationId,
            o.launchKey,
            o.detector,
            o.kind,
            o.chainId,
            o.token,
            o.declarationId,
            o.observedBlock,
            observedBlockHash,
            o.supersedes,
            o.tally,
            o.reportHash,
            o.reportURI,
            o.evidenceRoot
        );
    }

    function _resolveKey(ObservationInput calldata input)
        private
        view
        returns (bytes32 key, uint256 chainId, address token)
    {
        if (input.kind == KeyKind.Erc8376) {
            if (_directory == address(0) || input.chainId != 0 || input.token != address(0)) revert InvalidKey();
            token = ILaunchDirectoryTokenOf(_directory).tokenOf(input.launchId);
            if (token == address(0)) revert LaunchNotListed();
            return (input.launchId, block.chainid, token);
        }
        if (input.kind == KeyKind.Token) {
            if (input.launchId != bytes32(0) || input.chainId == 0 || input.token == address(0)) revert InvalidKey();
            return (tokenKey(input.chainId, input.token), input.chainId, input.token);
        }
        if (input.kind == KeyKind.Erc8462Venue) {
            // `launchId` carries the ERC-8462 venue-scoped declaration id. It is not checked against a declarations
            // contract here (ERC-8462 has no canonical deployment); readers check it with `getDeclaration`.
            if (input.launchId == bytes32(0) || input.chainId == 0 || input.token == address(0)) revert InvalidKey();
            return (declarationKey(input.chainId, input.launchId), input.chainId, input.token);
        }
        revert InvalidKey();
    }

    function _checkFindings(Finding[] calldata findings, Tally calldata tally) private pure {
        uint256 n = findings.length;
        if (n > MAX_FINDINGS) revert TooManyFindings();
        uint256 against;
        uint256 careful;
        uint256 clear;
        for (uint256 i = 0; i < n; i++) {
            Finding calldata f = findings[i];
            if (!_validFinding(f)) revert InvalidFinding(i);
            for (uint256 j = 0; j < i; j++) {
                if (findings[j].kind == f.kind && findings[j].param == f.param) revert DuplicateFinding(i);
            }
            if (f.lean == Lean.Against) against++;
            else if (f.lean == Lean.Careful) careful++;
            else if (f.lean == Lean.Clear) clear++;
        }
        if (tally.against < against || tally.careful < careful || tally.clear < clear) revert TallyBelowFindings();
    }

    function _validFinding(Finding calldata f) private pure returns (bool) {
        bytes32 k = f.kind;
        uint256 v = f.value;
        if (k == bytes32(0)) return false;
        if (k == FIRST_BLOCK_SHARE) {
            return f.param == 0 && (v <= MAX_BPS || v == NOT_READ);
        }
        if (k == EARLY_BUYER_SHARE || k == FUNDING_LINKED_SHARE) {
            return f.param != 0 && (v <= MAX_BPS || v == NOT_READ);
        }
        if (k == CREATOR_PRIOR_LAUNCHES) {
            return f.param == 0;
        }
        if (k == PRODUCT_LABEL) {
            return f.param == 0 && ((v >= LABEL_FOUND && v <= LABEL_NOT_FOUND) || v == NOT_READ);
        }
        uint256 max = _signalMax(k);
        if (max != 0) {
            return f.param == 0 && (v <= max || v == NOT_READ);
        }
        // Kinds outside the core set are not validated here; readers treat unknown kinds as informational.
        return true;
    }

    /// @dev The largest value an ERC-8376 signal kind takes, or 0 for a kind that is not one.
    function _signalMax(bytes32 k) private pure returns (uint256) {
        if (
            k == DEPLOYER_SUPPLY_SHARE || k == INSIDER_ALLOCATION_SHARE || k == SNIPER_CONCENTRATION
                || k == LP_LOCKED_SHARE || k == LIQUIDITY_REMOVED || k == DEPLOYER_SELL_RATIO
                || k == PROCEEDS_WITHDRAWN_SHARE || k == SUPPLY_INFLATION || k == WASH_TRADE_RATIO
        ) return MAX_BPS;
        if (k == LP_LOCK_REMAINING) return type(uint32).max - 1;
        if (k == PRIVILEGED_POWERS) return 0xff;
        if (k == PRIOR_UPHELD_CLAIMS) return type(uint16).max - 1;
        return 0;
    }

    /// @dev The value and lean of an observation's finding of `kind` and `param`, or not read and `None`.
    function _findingOf(uint256 observationId, bytes32 kind, uint64 param) private view returns (uint256, Lean) {
        Finding[] storage all = _findings[observationId];
        uint256 n = all.length;
        for (uint256 i = 0; i < n; i++) {
            Finding storage f = all[i];
            if (f.kind == kind && f.param == param) return (f.value, f.lean);
        }
        return (NOT_READ, Lean.None);
    }

    function _holdsIdentity(address registry, uint256 agentId, address account) private view returns (bool) {
        if (registry.code.length == 0) return false;
        (bool ok, bytes memory ret) = registry.staticcall(abi.encodeWithSignature("ownerOf(uint256)", agentId));
        if (ok && ret.length >= 32 && abi.decode(ret, (address)) == account) return true;
        (ok, ret) = registry.staticcall(abi.encodeWithSignature("getAgentWallet(uint256)", agentId));
        return ok && ret.length >= 32 && abi.decode(ret, (address)) == account && account != address(0);
    }

    function _page(uint256[] storage all, uint256 start, uint256 limit) private view returns (uint256[] memory out) {
        uint256 n = _pageLength(all.length, start, limit);
        out = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = all[start + i];
        }
    }

    function _pageLength(uint256 length, uint256 start, uint256 limit) private pure returns (uint256) {
        if (start >= length) return 0;
        uint256 remaining = length - start;
        return limit < remaining ? limit : remaining;
    }
}
