// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {IFinancialLease} from "../../src/IFinancialLease.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Handler para invariant testing (FASE 4). Llama al protocolo con
///      secuencias acotadas de acciones y mantiene ghost variables para
///      las dos propiedades derivadas de S3-01/S4-02 (ver audit/step6.md).
///      No hay handler de "solvencia clasica" (4.3 #1): el contrato nunca
///      custodia fondos (pay() transfiere lessee->lessor directo), asi que
///      esa invariante universal no aplica a este protocolo.
contract Handler is Test {
    FinancialLease public lease;
    MockERC20 public token;

    uint256 internal constant UNIT = 1e18;

    address[] public actors;
    uint256[] public leaseIds;

    // INV-LESSEE: true si algun leaseId sufrio un cambio de lessee
    // disparado por alguien que NO era el lessee saliente en ese momento.
    mapping(uint256 => bool) public ghost_lesseeHijacked;

    // Invariante auxiliar de sanidad (4.3, adaptada): una vez alcanzado un
    // status terminal (Terminated/Completed/PurchaseExercised), el lease
    // nunca deberia reportar un status distinto despues.
    mapping(uint256 => IFinancialLease.LeaseStatus) public ghost_lastStatus;
    bool public ghost_anyTerminalRegression;

    constructor(FinancialLease lease_, MockERC20 token_) {
        lease = lease_;
        token = token_;

        actors.push(makeAddr("actor0-lessor"));
        actors.push(makeAddr("actor1-lessee"));
        actors.push(makeAddr("actor2-declarer"));
        actors.push(makeAddr("actor3-outsider"));

        for (uint256 i = 0; i < actors.length; i++) {
            token.mint(actors[i], 10_000_000 * UNIT);
            vm.prank(actors[i]);
            token.approve(address(lease), type(uint256).max);
        }
    }

    function leaseIdsLength() external view returns (uint256) {
        return leaseIds.length;
    }

    function leaseIdAt(uint256 i) external view returns (uint256) {
        return leaseIds[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    /// @dev De los 3 valores "terminales" del enum, Completed NO es
    ///      absorbente en la practica: exercisePurchaseOption() lo mueve
    ///      legitimamente a PurchaseExercised (ver purchaseOption():
    ///      exercisable = status == Completed). Terminated nunca se
    ///      asigna en ningun lado del contrato (grep confirmado) — dead
    ///      enum member, nota aparte en step6.md, no es parte de esta
    ///      invariante. El unico estado genuinamente absorbente es
    ///      PurchaseExercised: ninguna funcion tiene un path de salida
    ///      (pay/declareDefault revierten por status > InDefault;
    ///      exercisePurchaseOption revierte porque exercisable exige
    ///      status == Completed).
    function _isAbsorbing(IFinancialLease.LeaseStatus s) internal pure returns (bool) {
        return s == IFinancialLease.LeaseStatus.PurchaseExercised;
    }

    function _trackStatus(uint256 leaseId) internal {
        IFinancialLease.LeaseStatus prev = ghost_lastStatus[leaseId];
        IFinancialLease.LeaseStatus cur = lease.status(leaseId);
        if (_isAbsorbing(prev) && cur != prev) {
            ghost_anyTerminalRegression = true;
        }
        ghost_lastStatus[leaseId] = cur;
    }

    // ─── acciones ───────────────────────────────────────────────

    function createLease(uint256 lessorSeed, uint256 lesseeSeed, uint256 declarerSeed, uint256 nInstallments, uint256 amountSeed, uint256 bpsSeed)
        external
    {
        address lessor_ = _actor(lessorSeed);
        address lessee_ = _actor(lesseeSeed);

        // declarerSeed tambien explora el branch p.defaultDeclarer == 0
        // (post fix S4-01: sin override -> se resuelve dinamicamente
        // contra ownerOf(leaseId) en cada llamada, YA NO se congela en
        // msg.sender al originar — ver _declarer() en FinancialLease.sol).
        address declarer_ = declarerSeed % 5 == 0 ? address(0) : _actor(declarerSeed);

        uint256 n = bound(nInstallments, 1, 3);
        uint64[] memory dueDates = new uint64[](n);
        uint256[] memory unitAmounts = new uint256[](n);
        uint256 amountEach = bound(amountSeed, 1, 1000) * UNIT;
        for (uint256 i = 0; i < n; i++) {
            dueDates[i] = uint64(block.timestamp) + uint64((i + 1) * 30 days);
            unitAmounts[i] = amountEach;
        }

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee_,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256(abi.encode(lessorSeed, lesseeSeed, block.timestamp)),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "USD",
            oracle: address(0),
            maxStaleness: 0,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: amountEach,
            penaltyBpsPerDay: uint16(bound(bpsSeed, 0, 500)),
            defaultDeclarer: declarer_,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });

        vm.prank(lessor_);
        uint256 id = lease.createLease(p);
        leaseIds.push(id);
        ghost_lastStatus[id] = IFinancialLease.LeaseStatus.Active;
    }

    function pay(uint256 leaseIdSeed, uint256 payerSeed, uint256 assetsSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address payer = _actor(payerSeed);
        uint256 assets = bound(assetsSeed, 0, 2000 * UNIT);

        vm.prank(payer);
        try lease.pay(id, assets) {
            _trackStatus(id);
        } catch {}
    }

    function warp(uint256 daysSeed) external {
        vm.warp(block.timestamp + bound(daysSeed, 0, 30 days));
    }

    function declareDefault(uint256 leaseIdSeed, uint256 callerSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address caller = _actor(callerSeed);

        vm.prank(caller);
        try lease.declareDefault(id) {
            _trackStatus(id);
        } catch {}
    }

    /// @dev El corazon del fuzz de INV-LESSEE: el caller es un actor
    ///      arbitrario, no necesariamente el lessee saliente.
    function assignLessee(uint256 leaseIdSeed, uint256 callerSeed, uint256 newLesseeSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address caller = _actor(callerSeed);
        address newLessee = _actor(newLesseeSeed);
        address oldLessee = lease.lessee(id);

        vm.prank(caller);
        try lease.assignLessee(id, newLessee) {
            if (caller != oldLessee) {
                ghost_lesseeHijacked[id] = true;
            }
        } catch {}
    }

    function exercisePurchaseOption(uint256 leaseIdSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address lessee_ = lease.lessee(id);

        vm.prank(lessee_);
        try lease.exercisePurchaseOption(id) {
            _trackStatus(id);
        } catch {}
    }
}
