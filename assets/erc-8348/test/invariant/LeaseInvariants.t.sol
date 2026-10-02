// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {Handler, MockERC20} from "./Handler.sol";

/// @title STEP 6 — Invariantes y fuzzing (FASE 4)
/// @dev INV-LESSEE es un handler-based invariant genuino: explora
///      secuencias aleatorias de llamadas a assignLessee con callers
///      arbitrarios y DEBE FALLAR con el codigo actual (confirma S4-02).
///
///      INV-FREQ (S3-01) NO vive aca como invariant_ de handler: requiere
///      comparar DOS leases identicos bajo DOS cadencias de llamada
///      controladas (1 vs 90), lo cual es una comparacion dirigida, no
///      una propiedad que emerja de una secuencia aleatoria unica (Fase 3:
///      "tests de escenario... mas efectivos que fuzzing puro porque
///      atacan patrones especificos"). Vive en
///      test/invariant/InvFreq.t.sol como test dirigido, y se documenta
///      aca igual porque es parte del mismo entregable de Step 6.
contract LeaseInvariantsTest is StdInvariant, Test {
    FinancialLease internal lease;
    MockERC20 internal token;
    Handler internal handler;

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        handler = new Handler(lease, token);

        targetContract(address(handler));
    }

    /// @dev DEBE FALLAR con el codigo actual. assignLessee (S4-02) no
    ///      exige que el caller sea el lessee saliente: cualquier caller
    ///      que sea el defaultDeclarer configurado (que por default ES
    ///      el lessor) puede reasignar el lessee sin su consentimiento.
    function invariant_INV_LESSEE_onlyOutgoingLesseeReassigns() public view {
        uint256 n = handler.leaseIdsLength();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.leaseIdAt(i);
            assertFalse(
                handler.ghost_lesseeHijacked(id),
                "INV-LESSEE violada: assignLessee acepto un caller distinto del lessee saliente (S4-02)"
            );
        }
    }

    /// @dev Invariante de sanidad (Fase 4.3 adaptada, no derivada de un
    ///      finding): PurchaseExercised es el unico status genuinamente
    ///      absorbente (ver Handler._isAbsorbing) — una vez alcanzado, no
    ///      debe volver a reportar otro status. Se espera que PASE; sirve
    ///      de control de que el harness efectivamente ejercita ese path
    ///      y de que _accrue()/pay()/declareDefault()/
    ///      exercisePurchaseOption() no lo pisan entre si (chequeo
    ///      cross-layer, Apendice H.8: tres funciones distintas escriben
    ///      `status`, cada una revisada individualmente en steps previos;
    ///      esta invariante prueba la interaccion de las tres bajo
    ///      secuencias arbitrarias). Nota: la primera version de esta
    ///      invariante trataba a Completed tambien como absorbente y
    ///      "fallaba" — era un bug en la invariante, no en el contrato:
    ///      Completed -> PurchaseExercised es una transicion legitima
    ///      (ver comentario en Handler.sol).
    function invariant_statusNeverLeavesTerminal() public view {
        assertFalse(
            handler.ghost_anyTerminalRegression(), "un lease en status PurchaseExercised reporto un status distinto despues"
        );
    }
}
