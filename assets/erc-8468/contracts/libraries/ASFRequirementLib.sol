// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "../ASFTypes.sol";

/// @title  ASFRequirementLib — storage helpers for requirement sets kept by consumers
/// @notice Consumers (guards, adapters, task contracts) keep the requirement they enforce in storage and
///         rebuild it in memory for every `check`. The helpers copy clause by clause so that no
///         nested-array storage copy is needed.
library ASFRequirementLib {
    struct Stored {
        T.Combinator combinator;
        uint16 k;
        T.Clause[] clauses;
    }

    function store(Stored storage s, T.RequirementSet memory r) internal {
        s.combinator = r.combinator;
        s.k = r.k;
        delete s.clauses;
        for (uint256 i = 0; i < r.clauses.length; i++) {
            s.clauses.push();
            T.Clause storage c = s.clauses[s.clauses.length - 1];
            c.specRegistry = r.clauses[i].specRegistry;
            c.specId = r.clauses[i].specId;
            c.versions = r.clauses[i].versions;
            c.adopter = r.clauses[i].adopter;
            c.subjectKey = r.clauses[i].subjectKey;
            c.scopeKey = r.clauses[i].scopeKey;
            c.enforcement = r.clauses[i].enforcement;
            for (uint256 j = 0; j < r.clauses[i].interveners.length; j++) {
                c.interveners.push(r.clauses[i].interveners[j]);
            }
        }
    }

    function load(Stored storage s) internal view returns (T.RequirementSet memory r) {
        r.combinator = s.combinator;
        r.k = s.k;
        r.clauses = new T.Clause[](s.clauses.length);
        for (uint256 i = 0; i < s.clauses.length; i++) {
            T.Clause storage c = s.clauses[i];
            r.clauses[i] = T.Clause({
                specRegistry: c.specRegistry,
                specId: c.specId,
                versions: c.versions,
                adopter: c.adopter,
                subjectKey: c.subjectKey,
                scopeKey: c.scopeKey,
                enforcement: c.enforcement,
                interveners: c.interveners
            });
        }
    }
}
