"""Executable reference model of the ERC-8412 registry (§6, §7).

Mirrors contracts/PreregisteredCriteria.sol line for line so the conformance
vectors can be run without a Solidity toolchain. Each revert carries the tag
of the invariant it enforces.

`disabled` switches individual invariants off. It exists only for mutation
testing: tools/mutation_test.py disables one invariant at a time and checks
that at least one vector then fails, which proves every invariant is actually
exercised by the vector set.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from ethcrypto import enc_address, enc_bytes32, enc_uint, h, keccak256, unhex

ZERO32 = "0x" + "00" * 32
ZERO_ADDR = "0x" + "00" * 20

NONE, SATISFIED, NOT_SATISFIED, INDETERMINATE, EXPIRED_UNRESOLVED = range(5)
VERDICT_NAMES = ["None", "Satisfied", "NotSatisfied", "Indeterminate", "ExpiredUnresolved"]
UNMET, MET, WAIVED, NOT_APPLICABLE = range(4)
OUTCOME_NAMES = ["UNMET", "MET", "WAIVED", "NOT_APPLICABLE"]


class Revert(Exception):
    def __init__(self, tag: str, detail: str = ""):
        super().__init__(f"{tag}: {detail}" if detail else tag)
        self.tag = tag


def pair(packed: bytes, i: int) -> int:
    """2-bit field i, most-significant bits first (§5)."""
    return (packed[i // 4] >> (6 - 2 * (i % 4))) & 0b11


def pack(values: list[int]) -> bytes:
    out = bytearray((len(values) + 3) // 4)
    for i, v in enumerate(values):
        out[i // 4] |= (v & 0b11) << (6 - 2 * (i % 4))
    return bytes(out)


@dataclass
class Prereg:
    author: str
    criteria_digest: str
    task_ref: str
    obligation_count: int
    obligation_flags: bytes
    expiry: int
    registered_at: int
    verifier: str
    supersedes: str
    superseded_by: str = ZERO32


@dataclass
class Attestation:
    verifier: str = ZERO_ADDR
    bundle_digest: str = ZERO32
    attestation_digest: str = ZERO32
    verdict: int = NONE
    obligation_outcomes: bytes = b""
    attested_at: int = 0


@dataclass
class Registry:
    chain_id: int
    address: str
    disabled: set = field(default_factory=set)
    preregs: dict = field(default_factory=dict)
    atts: dict = field(default_factory=dict)
    events: list = field(default_factory=list)

    # ------------------------------------------------------------- helpers
    def _on(self, tag):
        return tag not in self.disabled

    def _check_packed(self, packed: bytes, n: int):
        """E2: exact length ceil(2n/8) and zero trailing pad bits."""
        if not self._on("E2"):
            return
        if len(packed) != (2 * n + 7) // 8:
            raise Revert("E2", "packed length")
        used = (2 * n) % 8
        if used and packed[-1] & ((1 << (8 - used)) - 1):
            raise Revert("E2", "nonzero pad bits")

    def compute_id(self, sender, criteria_digest, task_ref) -> str:
        return h(keccak256(enc_uint(self.chain_id) + enc_address(self.address) +
                           enc_address(sender) + enc_bytes32(criteria_digest) +
                           enc_bytes32(task_ref)))

    # ------------------------------------------------------------- §6 functions
    def preregister(self, sender, ts, criteria_digest, task_ref, obligation_count,
                    obligation_flags: bytes, expiry, verifier, supersedes=ZERO32) -> str:
        if self._on("E1") and expiry <= ts:
            raise Revert("E1", "expiry not in the future")
        self._check_packed(obligation_flags, obligation_count)
        if self._on("E14") and int(verifier, 16) == 0:
            raise Revert("E14", "zero verifier")
        if self._on("E14") and verifier.lower() == sender.lower():
            raise Revert("E14", "author is verifier")
        pid = self.compute_id(sender, criteria_digest, task_ref)
        if self._on("DUP") and pid in self.preregs:
            raise Revert("DUP", "duplicate preregistrationId")
        if supersedes != ZERO32:
            prior = self.preregs.get(supersedes)
            if prior is None:
                raise Revert("E12", "unknown prior")
            if self._on("E12"):
                if prior.author.lower() != sender.lower() or prior.task_ref != task_ref:
                    raise Revert("E12", "different author or taskRef")
                if prior.superseded_by != ZERO32:
                    raise Revert("E12", "prior already superseded")
                v = self.atts.get(supersedes, Attestation()).verdict
                if v not in (NONE, INDETERMINATE):
                    raise Revert("E12", "prior has a final verdict")
            prior.superseded_by = pid
        self.preregs[pid] = Prereg(sender, criteria_digest, task_ref, obligation_count,
                                   bytes(obligation_flags), expiry, ts, verifier, supersedes)
        self.events.append(("CriteriaPreregistered", pid))
        return pid

    def attest_outcome(self, sender, ts, pid, bundle_digest, attestation_digest, verdict,
                       outcomes: bytes):
        p = self.preregs.get(pid)
        if p is None:
            raise Revert("UNKNOWN", "unknown preregistrationId")
        if self._on("E3") and sender.lower() != p.verifier.lower():
            raise Revert("E3", "sender is not the recorded verifier")
        if self._on("E13") and p.superseded_by != ZERO32:
            raise Revert("E13", "preregistration superseded")
        if self._on("E10") and self.atts.get(pid, Attestation()).verdict != NONE:
            raise Revert("E10", "terminal verdict already recorded")
        if self._on("E7") and ts > p.expiry:
            raise Revert("E7", "past expiry")
        if self._on("E9") and verdict not in (SATISFIED, NOT_SATISFIED, INDETERMINATE):
            raise Revert("E9", "verdict must be Satisfied, NotSatisfied or Indeterminate")
        self._check_packed(outcomes, p.obligation_count)
        any_unmet, required_ok = False, True
        for i in range(p.obligation_count):
            flag, out = pair(p.obligation_flags, i), pair(outcomes, i)
            required, waivable = flag & 1, (flag >> 1) & 1
            if self._on("E6") and out == NOT_APPLICABLE and required:
                raise Revert("E6", f"NOT_APPLICABLE on required obligation {i}")
            if self._on("E5") and out == WAIVED and not waivable:
                raise Revert("E5", f"WAIVED on non-waivable obligation {i}")
            if out == UNMET:
                any_unmet = True
            if required and out not in (MET, WAIVED):
                required_ok = False
        if self._on("E4") and verdict == SATISFIED and not required_ok:
            raise Revert("E4", "Satisfied with a required obligation not MET/WAIVED")
        if self._on("E11") and verdict in (NOT_SATISFIED, INDETERMINATE) and not any_unmet:
            raise Revert("E11", "NotSatisfied/Indeterminate with no UNMET obligation")
        self.atts[pid] = Attestation(sender, bundle_digest, attestation_digest, verdict,
                                     bytes(outcomes), ts)
        self.events.append(("OutcomeAttested", pid))

    def resolve_expired(self, sender, ts, pid):
        p = self.preregs.get(pid)
        if p is None:
            raise Revert("UNKNOWN", "unknown preregistrationId")
        if self._on("E8"):
            # "ORIGINAL_E8" reproduces the pre-fix text ("revert before expiry"),
            # used only by mutation testing to show the vectors catch the gap.
            too_early = ts < p.expiry if "ORIGINAL_E8" in self.disabled else ts <= p.expiry
            if too_early:
                raise Revert("E8", "not yet expired")
            if self.atts.get(pid, Attestation()).verdict != NONE:
                raise Revert("E8", "verdict already recorded")
            if p.superseded_by != ZERO32:
                raise Revert("E8", "preregistration superseded")
        self.atts[pid] = Attestation(verdict=EXPIRED_UNRESOLVED)
        self.events.append(("ExpiredResolved", pid))

    # ------------------------------------------------------------- views
    def get_attestation(self, pid) -> Attestation:
        return self.atts.get(pid, Attestation())

    def get_preregistration(self, pid) -> Prereg:
        return self.preregs[pid]


def flags_from_obligations(obligations) -> bytes:
    """obligationFlags derived from a criteria document (§5 table)."""
    return pack([(1 if o["required"] else 0) | (2 if o["waivable"] else 0) for o in obligations])


def outcomes_from_names(names) -> bytes:
    return pack([OUTCOME_NAMES.index(n) for n in names])


__all__ = ["Registry", "Revert", "pack", "pair", "flags_from_obligations",
           "outcomes_from_names", "VERDICT_NAMES", "OUTCOME_NAMES", "ZERO32", "ZERO_ADDR",
           "unhex"]
