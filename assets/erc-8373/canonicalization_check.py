#!/usr/bin/env python3
"""pq_key_binding.v1/canonicalization -- admission check for a binding statement's raw bytes (stdlib only).

Verdicts: admit | reject:size_exceeded | reject:name_too_long | reject:not_canonical
Order: the size bound is checked first (it needs no parsing), then canonical form, then the member-name bound.
Canonical form here is the flat-object JCS profile (RFC 8785) used by pq_key_binding statements: an object whose
values are strings or integers with |n| <= 2^53 - 1, members ordered by UTF-16 code units, no whitespace,
ECMAScript string escaping. Anything else is reject:not_canonical.

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
        parts.append(jcs_string(k) + ':' + (jcs_string(v) if isinstance(v, str) else str(v)))
    return '{' + ','.join(parts) + '}'


def check(raw: bytes, facet: dict) -> str:
    if len(raw) > facet['max_statement_bytes']:
        return 'reject:size_exceeded'
    try:
        text = raw.decode('utf-8', errors='strict')
        pairs = json.loads(text, object_pairs_hook=lambda p: p)
    except (UnicodeDecodeError, ValueError):
        return 'reject:not_canonical'
    if not isinstance(pairs, list) or len({k for k, _ in pairs}) != len(pairs):
        return 'reject:not_canonical'
    obj = dict(pairs)
    for v in obj.values():
        if isinstance(v, bool) or not (isinstance(v, str) or (isinstance(v, int) and abs(v) <= MAX_SAFE)):
            return 'reject:not_canonical'
    if jcs(obj).encode('utf-8') != raw:
        return 'reject:not_canonical'
    if any(len(jcs_string(k).encode('utf-8')) - 2 > facet['max_member_name_escaped_bytes'] for k in obj):
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
