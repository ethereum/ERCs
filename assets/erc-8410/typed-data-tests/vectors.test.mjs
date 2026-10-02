import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import Ajv2020 from 'ajv/dist/2020.js';
import { TypedDataEncoder, concat, keccak256, toUtf8Bytes } from 'ethers';
import { hashTypedData, keccak256 as viemKeccak256, stringToHex } from 'viem';

const read = (name) => JSON.parse(readFileSync(new URL(`../${name}`, import.meta.url)));
const ajv = new Ajv2020({ strict: true });
const resultSchema = read('typed-data-result.schema.json');
ajv.addSchema(resultSchema);
const validateResult = ajv.getSchema(resultSchema.$id);
const validateRequest = ajv.compile(read('typed-data-signature-request.schema.json'));
const validateDelivery = ajv.compile(read('typed-data-delivery.schema.json'));
const validateReceipt = ajv.compile(read('typed-data-receipt.schema.json'));
// The existing plan schema includes human-oriented annotations and is unchanged.
const validatePlan = new Ajv2020({ strict: false }).compile(read('execution-plan.schema.json'));
const validateReference = ajv.compile(read('artifact-reference.schema.json'));
const vectors = read('typed-data-test-vectors.json').cases;
const byName = Object.fromEntries(vectors.map((v) => [v.name, v]));

// Normalize by declared type, never by a value's apparent hexadecimal spelling.
// Like project(), this is a fixture helper, not an adversarial input validator.
function normalize(type, value, types) {
  const array = type.match(/^(.*)\[[0-9]*\]$/);
  if (array) return value.map((item) => normalize(array[1], item, types));
  if (type === 'address' || /^bytes([0-9]+)?$/.test(type)) return value.toLowerCase();
  if (Object.hasOwn(types, type)) {
    return Object.fromEntries(types[type].map((field) =>
      [field.name, normalize(field.type, value[field.name], types)]));
  }
  return value;
}

// This projection accepts already semantically validated requests only.
function project(request, signingDigest) {
  return JSON.stringify({
    kind: request.kind,
    schema_version: request.schema_version,
    signer: request.signer.toLowerCase(),
    signing_digest: signingDigest.toLowerCase(),
    valid_until: request.valid_until ?? null,
    delivery: request.delivery ? {
      url: request.delivery.url,
      request_id: request.delivery.request_id,
    } : null,
  });
}

for (const vector of vectors) {
  test(`typed data: ${vector.name}`, () => {
    assert.ok(validateRequest(vector.request), ajv.errorsText(validateRequest.errors));
    const { types, primaryType } = vector.request.typed_data;
    const domain = normalize('EIP712Domain', vector.request.typed_data.domain, types);
    const message = normalize(primaryType, vector.request.typed_data.message, types);
    const { EIP712Domain, ...messageTypes } = types;
    const ethersDigest = TypedDataEncoder.hash(domain, messageTypes, message);
    assert.equal(ethersDigest, vector.signing_digest);
    assert.equal(hashTypedData({ domain, types, primaryType, message }), vector.signing_digest);
    const domainSeparator = TypedDataEncoder.hashDomain(domain);
    const messageHash = TypedDataEncoder.hashStruct(primaryType, messageTypes, message);
    assert.equal(domainSeparator, vector.domain_separator);
    assert.equal(messageHash, vector.message_hash);
    assert.equal(keccak256(concat(['0x1901', domainSeparator, messageHash])), ethersDigest);
    const canonical = project(vector.request, ethersDigest);
    assert.equal(canonical, vector.canonical_form);
    assert.equal(keccak256(toUtf8Bytes(canonical)), vector.request_digest);
    assert.equal(viemKeccak256(stringToHex(canonical)), vector.request_digest);
  });
}

test('identity boundaries', () => {
  const base = byName['permit'];
  for (const name of ['object-key-order', 'hexadecimal-case']) {
    assert.equal(byName[name].signing_digest, base.signing_digest);
    assert.equal(byName[name].request_digest, base.request_digest);
    assert.notEqual(JSON.stringify(byName[name].request), JSON.stringify(base.request));
  }
  for (const name of ['domain-chain', 'domain-verifier']) {
    assert.equal(byName[name].message_hash, base.message_hash);
    assert.notEqual(byName[name].signing_digest, base.signing_digest);
    assert.notEqual(byName[name].request_digest, base.request_digest);
  }
  for (const name of ['signer', 'wallet-cutoff', 'no-wallet-cutoff', 'delivery']) {
    assert.equal(byName[name].signing_digest, base.signing_digest);
    assert.notEqual(byName[name].request_digest, base.request_digest);
  }
  for (const name of ['delivery-url', 'delivery-request-id']) {
    assert.equal(byName[name].signing_digest, byName.delivery.signing_digest);
    assert.notEqual(byName[name].request_digest, byName.delivery.request_digest);
  }
  for (const name of ['amount', 'protocol-deadline', 'uint256-max']) {
    assert.notEqual(byName[name].signing_digest, base.signing_digest);
    assert.notEqual(byName[name].request_digest, base.request_digest);
  }
});

test('exact-byte artifact integrity changes with JSON formatting', () => {
  const request = byName.permit.request;
  const compact = JSON.stringify(request);
  const pretty = JSON.stringify(request, null, 2);
  assert.notEqual(keccak256(toUtf8Bytes(compact)), keccak256(toUtf8Bytes(pretty)));
  assert.equal(project(JSON.parse(compact), byName.permit.signing_digest),
    project(JSON.parse(pretty), byName.permit.signing_digest));
});

test('request schema rejection cases', () => {
  const changes = [
    (r) => { r.schema_version = '2'; },
    (r) => { r.kind = 'execution_plan'; },
    (r) => { r.signer = '0x12'; },
    (r) => { r.signer += '\n'; },
    (r) => { r.valid_until = 1800000000; },
    (r) => { r.valid_until = '01'; },
    (r) => { r.valid_until = '-1'; },
    (r) => { r.valid_until += '\n'; },
    (r) => { r.valid_until = null; },
    (r) => { r.delivery = null; },
    (r) => { r.unknown = true; },
    (r) => { r.typed_data = JSON.stringify(r.typed_data); },
    (r) => { r.typed_data.primaryType = 'EIP712Domain'; },
    (r) => { r.typed_data.extra = 'unsigned caption'; },
    (r) => { delete r.typed_data.types.EIP712Domain; },
  ];
  for (const change of changes) {
    const request = structuredClone(byName.permit.request);
    change(request);
    assert.equal(validateRequest(request), false, JSON.stringify(request));
  }
  for (const url of ['http://producer.example/results', 'https://producer.example:443/results',
    'https://user@producer.example/results', 'https://producer.example/results?token=x',
    'https://producer.example/results#fragment', 'https://producer.example/a/../b',
    'https://producer.example/a%2fb', 'https://producer.example//results',
    'https://Producer.example/results', 'https://[::1]/results',
    'https://producer.example/results\n']) {
    const request = structuredClone(byName.delivery.request);
    request.delivery.url = url;
    assert.equal(validateRequest(request), false, url);
  }
});

const baseResult = {
  kind: 'typed_data_result', schema_version: '1',
  request_digest: byName.delivery.request_digest,
  signing_digest: byName.delivery.signing_digest,
  signer: byName.delivery.request.signer,
  signature: '0x1234', // Shape only: no claim of a valid signature.
};

test('opaque results and fixed delivery operations', () => {
  assert.ok(validateResult(baseResult));
  assert.ok(validateResult({ ...baseResult, signature: `0x${'ab'.repeat(65)}` }));
  for (const signature of ['0x', '0x123', 'not-hex']) {
    assert.equal(validateResult({ ...baseResult, signature }), false);
  }
  assert.equal(validateResult({ ...baseResult, r: '0x12' }), false);
  const submit = { action: 'submit', request_id: 'quote-123-permit-1', result: baseResult };
  const status = { action: 'status', request_id: submit.request_id, request_digest: baseResult.request_digest };
  assert.ok(validateDelivery(submit));
  assert.ok(validateDelivery(status));
  assert.equal(validateDelivery({ ...submit, headers: { Authorization: 'caller-input' } }), false);
  assert.equal(validateDelivery({ ...submit, action: 'execute' }), false);
  assert.equal(validateDelivery({ ...status, result: baseResult }), false);
});

test('receipt states cannot imply settlement or return signatures', () => {
  const receipt = {
    kind: 'typed_data_receipt', schema_version: '1', request_id: 'quote-123-permit-1',
    request_digest: baseResult.request_digest, status: 'accepted', operation_id: 'order-123',
  };
  assert.ok(validateReceipt(receipt));
  const { operation_id, ...withoutOperation } = receipt;
  assert.equal(validateReceipt(withoutOperation), false);
  for (const status of ['rejected', 'unknown']) {
    assert.ok(validateReceipt({ ...withoutOperation, status }));
    assert.equal(validateReceipt({ ...receipt, status }), false);
  }
  assert.equal(validateReceipt({ ...receipt, status: 'settled' }), false);
  assert.equal(validateReceipt({ ...receipt, signature: '0x1234' }), false);
});

test('reference envelope accepts exactly the two document types', () => {
  const bytes = toUtf8Bytes(JSON.stringify(byName.permit.request));
  const reference = {
    kind: 'artifact_reference', artifact_type: 'typed_data_signature_request',
    url: 'https://producer.example/requests/permit-1', bytes: bytes.length,
    integrity: { algorithm: 'keccak256', value: keccak256(bytes) },
  };
  assert.ok(validateReference(reference));
  assert.ok(validateReference({ ...reference, artifact_type: 'execution_plan' }));
  for (const artifact_type of ['read_calls', 'token_list', 'typed_data_request', 'unknown']) {
    assert.equal(validateReference({ ...reference, artifact_type }), false);
  }
  // Actual consumers must still refuse artifact types unsupported at the point of use.
  assert.equal(validatePlan(byName.permit.request), false);
});

for (const vector of read('digest-test-vectors.json').cases) {
  test(`unchanged execution plan: ${vector.name}`, () => {
    assert.ok(validatePlan(vector.plan));
    assert.equal(validateRequest(vector.plan), false);
    const plan = vector.plan;
    const canonical = JSON.stringify({
      schema_version: plan.schema_version, chain_id: plan.chain_id,
      sender: plan.sender.toLowerCase(), ordered_steps: plan.ordered_steps.map((step) => ({
        step: step.step, kind: step.kind, transaction: {
          chain_id: step.transaction.chain_id, from: step.transaction.from.toLowerCase(),
          to: step.transaction.to.toLowerCase(), data: step.transaction.data.toLowerCase(),
          value: step.transaction.value,
        },
      })),
    });
    assert.equal(canonical, vector.canonical_form);
    assert.equal(keccak256(toUtf8Bytes(canonical)), vector.digest);
    assert.equal(viemKeccak256(stringToHex(canonical)), vector.digest);
  });
}
