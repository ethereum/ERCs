// Conformance runner: executes verify() against every fixture vector.
import { readFileSync } from 'node:fs';
import { verify, keccak256, blake2b256, TOPIC0, ERC165_INTERFACE_ID } from './verify.mjs';

// independent sanity checks of the JS hash implementations
const hex = (b) => Array.from(b, x => x.toString(16).padStart(2,'0')).join('');
const enc = (s) => new TextEncoder().encode(s);
// keccak256("") and ERC-20 Transfer topic
console.assert(hex(keccak256(enc(''))) === 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470', 'keccak empty FAILED');
console.assert(hex(keccak256(enc('Transfer(address,address,uint256)'))) === 'ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef', 'keccak transfer FAILED');
// RFC 7693 BLAKE2b-512 test vector is for 64-byte digests; cross-check blake2b-256("abc")
// against python hashlib value computed during vector generation:
console.assert(hex(blake2b256(enc('abc'))) === 'bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319', 'blake2b256 abc FAILED');

const suite = JSON.parse(readFileSync('./test-vectors.json', 'utf8'));
console.assert(suite.constants.topic0 === TOPIC0, 'topic0 constant mismatch');
console.assert(suite.constants.erc165_interface_id === ERC165_INTERFACE_ID, 'interface id mismatch');

let pass = 0, fail = 0;
for (const v of suite.vectors) {
  if (v.expect === 'constants') {
    const t0 = '0x' + hex(keccak256(enc(v.constants.topic0_signature)));
    const ifid = '0x' + hex(keccak256(enc(v.constants.interface_id_signature))).slice(0, 8);
    const ok = t0 === v.constants.topic0 && ifid === v.constants.interface_id;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${v.id}  ${v.name}`);
    ok ? pass++ : fail++;
    continue;
  }
  const provider = {
    eth_chainId: async () => v.fixtures.eth_chainId,
    eth_getTransactionReceipt: async (h) =>
      h === v.fixtures.receipt.transactionHash ? v.fixtures.receipt : null,
  };
  const obs = Uint8Array.from(v.observation_hex.slice(2).match(/.{2}/g) ?? [], x => parseInt(x, 16));
  const result = await verify(v.envelope, obs, provider);
  let ok;
  if (v.expect === 'pass') ok = result.valid === true;
  else ok = result.valid === false && result.reason === v.reject_reason;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${v.id}  ${v.name}` + (ok ? '' : `   got: ${JSON.stringify(result)} expected: ${v.expect}/${v.reject_reason ?? ''}`));
  ok ? pass++ : fail++;
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
