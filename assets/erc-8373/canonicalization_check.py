#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""pq_key_binding.v1/canonicalization -- admission check for a binding statement's raw bytes (stdlib only).

Verdicts: admit | reject:size_exceeded | reject:unsupported_shape | reject:not_canonical | reject:name_too_long
Order (the first failing check gives the verdict): (1) size, on the raw bytes before parsing; (2) shape: a JSON
object whose member values are strings, integers, or objects whose member values are strings or integers (one level
of nesting); (3) canonical form: the raw bytes are exactly JCS(statement) (RFC 8785: members ordered by UTF-16 code
units, no whitespace, ECMAScript string escaping) and every integer is within +-(2^53 - 1); (4) member names, nested
ones included, are at most 64 escaped bytes.
Booleans, null, non-integer numbers, arrays and deeper nesting are valid RFC 8785 the profile does not admit:
reject:unsupported_shape, kept separate from reject:not_canonical (broken or non-canonical JCS).

usage: python3 canonicalization_check.py pq-key-binding-v1.canonicalization.json pq-key-binding-v1.canonicalization-vectors.json
"""
import json, sys

MAX_SAFE = 2**53 - 1


def jcs_string(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"': out.append('\\"')
        elif ch == '\\': out.append('\\\\')
        elif ch == '\b': out.append('\\b')
        elif ch == '\t': out.append('\\t')
        elif ch == '\n': out.append('\\n')
        elif ch == '\f': out.append('\\f')
        elif ch == '\r': out.append('\\r')
        elif o < 0x20: out.append('\\u%04x' % o)
        else: out.append(ch)
    out.append('"')
    return ''.join(out)


def jcs(obj):
    keys = sorted(obj, key=lambda k: k.encode('utf-16-be'))
    parts = []
    for k in keys:
        v = obj[k]
        enc = jcs_string(v) if isinstance(v, str) else jcs(v) if isinstance(v, dict) else str(v)
        parts.append(jcs_string(k) + ':' + enc)
    return '{' + ','.join(parts) + '}'


def _scalar(v):
    return isinstance(v, str) or (isinstance(v, int) and not isinstance(v, bool))


class _ObjectPairs(list):
    """Marks a list as the result of parsing a JSON *object*, so a top-level JSON array
    (which json.loads also hands back as a plain list) can never be mistaken for one."""


def check(raw: bytes, facet: dict) -> str:
    if len(raw) > facet['max_statement_bytes']:
        return 'reject:size_exceeded'
    try:
        text = raw.decode('utf-8', errors='strict')
        pairs = json.loads(text, object_pairs_hook=_ObjectPairs)
    except RecursionError:
        # nesting deep enough to exhaust the parser is, whatever else it is, deeper than one level
        return 'reject:unsupported_shape'
    except (UnicodeDecodeError, ValueError):
        return 'reject:not_canonical'
    # (2) shape
    if not isinstance(pairs, _ObjectPairs):
        return 'reject:unsupported_shape'
    for _, v in pairs:
        if _scalar(v):
            continue
        if isinstance(v, _ObjectPairs) and all(_scalar(x) for _, x in v):
            continue
        return 'reject:unsupported_shape'
    # (3) canonical form
    def to_dict(ps):
        if len({k for k, _ in ps}) != len(ps):
            raise ValueError('duplicate member')
        return {k: (to_dict(x) if isinstance(x, _ObjectPairs) else x) for k, x in ps}
    try:
        obj = to_dict(pairs)
    except ValueError:
        return 'reject:not_canonical'
    ints = [v for v in obj.values() if isinstance(v, int)] + [x for v in obj.values() if isinstance(v, dict) for x in v.values() if isinstance(x, int)]
    if any(abs(n) > MAX_SAFE for n in ints):
        return 'reject:not_canonical'
    names = list(obj) + [k for v in obj.values() if isinstance(v, dict) for k in v]
    try:
        canonical = jcs(obj).encode('utf-8')
        name_lens_ok = all(len(jcs_string(k).encode('utf-8')) - 2 <= facet['max_member_name_escaped_bytes'] for k in names)
    except UnicodeEncodeError:
        # a lone surrogate in a name or value: JCS (RFC 8785) has no encoding for it, so the
        # statement cannot be canonical, regardless of which side tripped the encoder first.
        return 'reject:not_canonical'
    if canonical != raw:
        return 'reject:not_canonical'
    if not name_lens_ok:
        return 'reject:name_too_long'
    return 'admit'


def main(facet_path, vectors_path):
    facet = json.load(open(facet_path))
    cases = json.load(open(vectors_path))['cases']
    bad = 0
    for c in cases:
        got = check(bytes.fromhex(c['statement_hex']), facet)
        ok = got == c['expect']
        bad += not ok
        print(('PASS ' if ok else 'FAIL ') + c['id'] + ' -> ' + got + ('' if ok else '  (expected ' + c['expect'] + ')'))
    print('%d/%d' % (len(cases) - bad, len(cases)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:3]))
