// buildMerkle.ts
// Usage: npx ts-node buildMerkle.ts

import fs from "fs";
import { buildPoseidon } from "circomlibjs";
import { MerkleTree }   from "merkletreejs";
import { keccak256 }    from "js-sha3";

/**
 * Canonicalize JSON per RFC8785: lexicographically sorted keys, no whitespace
 */
function canonicalize(x: any): string {
  if (x === null || typeof x !== "object") return JSON.stringify(x);
  if (Array.isArray(x)) return "[" + x.map(canonicalize).join(",") + "]";
  const keys = Object.keys(x).sort();
  return "{" + keys.map(k => JSON.stringify(k) + ":" + canonicalize(x[k])).join(",") + "}";
}

// buildMerkle.ts
// ... (imports and canonicalize function remain the same) ...

async function main() {
    // 1) Load your PAIN JSON
    const raw = JSON.parse(fs.readFileSync("./scripts/data/sample_usd_small.json", "utf8"));
  
    // 2) Extract relevant parts
    const senderObj    = raw.PmtInf.Dbtr;
    const recipientObj = raw.PmtInf.CdtTrfTxInf[0].Cdtr;
    const amountStr    = raw.PmtInf.CdtTrfTxInf[0].InstdAmt.Value;
    const currencyStr  = raw.PmtInf.CdtTrfTxInf[0].InstdAmt.Ccy;
    const expiryStr    = raw.PmtInf.ReqdExctnDt;
  
    // 3) Define each field with its tag and raw data
    type FieldDef = { tag: bigint; canonical?: string; numericStr?: string; dateStr?: string };
    const fields: FieldDef[] = [
      { tag: 1n, canonical: canonicalize(senderObj)      },
      { tag: 2n, canonical: canonicalize(recipientObj)   },
      { tag: 3n, numericStr: amountStr                    },
      { tag: 4n, canonical: JSON.stringify(currencyStr)  }, // As per your original logic
      { tag: 5n, dateStr:    expiryStr                    },
    ];
  
    // 4) Initialize Poseidon
    const poseidon = await buildPoseidon();
    const F = poseidon.F;
  
    // Arrays to gather results
    const fieldValues: bigint[] = [];
    const leaves: Buffer[]      = []; // This will be padded
    // proofSiblings and proofDirs will store proofs for data leaves only
    const proofSiblings: string[][] = [];
    const proofDirs: number[][] = [];
  
    // 5) Compute each field's preimage and leaf buffer FOR ACTUAL DATA
    for (const field of fields) {
      let preimage: bigint;
      if (field.canonical != null) {
        const hashHex = keccak256(field.canonical);
        preimage = BigInt("0x" + hashHex);
      } else if (field.numericStr != null) {
        const [intPart, fracPart = ""] = field.numericStr.split(".");
        const combined = intPart + fracPart;
        preimage = BigInt(combined);
      } else if (field.dateStr != null) {
        preimage = BigInt(field.dateStr.replace(/-/g, ""));
      } else {
        throw new Error("Invalid field definition");
      }
      fieldValues.push(preimage); // fieldValues will have 5 elements
  
      const leafFe = poseidon([F.e(preimage), F.e(field.tag)]);
      const leafBig = F.toObject(leafFe);
      const hex = leafBig.toString(16).padStart(64, "0");
      leaves.push(Buffer.from(hex, "hex")); // leaves now has 5 data leaf buffers
    }


  
    const numDataLeaves = leaves.length; // Store the count of actual data leaves (should be 5)
    const CIRCUIT_DEPTH = 3; // Your circuit's depth
    const requiredTotalLeaves = 1 << CIRCUIT_DEPTH; // 2^3 = 8
  
    if (numDataLeaves > requiredTotalLeaves) {
      throw new Error(`Number of data leaves (${numDataLeaves}) exceeds the capacity of the Merkle tree for DEPTH ${CIRCUIT_DEPTH} (${requiredTotalLeaves} slots).`);
    }
  
    // Define a padding leaf (e.g., Poseidon hash of 0,0 or similar neutral value)
    // It's good practice for the padding leaf to be a value that won't collide with real data leaves.
    const paddingPreimage = 0n;
    const paddingTag = 0n; // Or a distinct tag for padding elements if desired
    const paddingLeafFe = poseidon([F.e(paddingPreimage), F.e(paddingTag)]);
    const paddingLeafBig = F.toObject(paddingLeafFe);
    const paddingHex = paddingLeafBig.toString(16).padStart(64, "0");
    const paddingLeafBuffer = Buffer.from(paddingHex, "hex");
  
    // Add padding leaves until the total number of leaves is `requiredTotalLeaves`
    while (leaves.length < requiredTotalLeaves) {
      leaves.push(paddingLeafBuffer);
    }
    // Now, `leaves` array has 8 elements (5 data leaves + 3 padding leaves)
  
    // 6) Build Poseidon Merkle tree (depth=4 → 16 slots) <- This comment might be outdated if DEPTH is 3
    // The tree will now be built on 8 leaves, naturally forming a depth 3 tree.
    const hashFn = (L: Buffer, R?: Buffer) => {
      const rightBuf = R ?? L; // This handles potential odd nodes if duplicateOdd is still used, though not strictly needed for power-of-2 leaves
      const l = BigInt("0x" + L.toString("hex"));
      const r = BigInt("0x" + rightBuf.toString("hex"));
      const h = poseidon([F.e(l), F.e(r)]);
      const big = F.toObject(h);
      const hex = big.toString(16).padStart(64, "0");
      return Buffer.from(hex, "hex");
    };
    // With 8 leaves, duplicateOdd:true is less critical but harmless. You could set it to false.
    const tree = new MerkleTree(leaves, hashFn, { hashLeaves: false, sort: false, duplicateOdd: false });
    
    // 7) Generate proofs FOR ACTUAL DATA LEAVES ONLY
    // The `leaves` array has 8 elements, but we only need proofs for the first `numDataLeaves` (5)
    for (let i = 0; i < numDataLeaves; i++) {
      const dataLeafBuffer = leaves[i]; // Get the i-th original data leaf buffer
      const proof = tree.getProof(dataLeafBuffer);
      if (i === 3) { // For currency leaf (index 3)
        console.log(`Currency proof FROM MERKLETREEJS (after padding):`);
        console.log(`  Siblings: ${JSON.stringify(proof.map(p => BigInt("0x" + p.data.toString("hex")).toString()))}`);
        console.log(`  Directions: ${JSON.stringify(proof.map(p => (p.position === "right" ? 1 : 0)))}`);
        console.log(`  Length: ${proof.length}`);
    }
      // Your logging for the expiry proof (which is fields[4], so i === 4)
      if (i === 4) { // Index 4 corresponds to the 5th field (expiry)
          console.log("Expiry proof FROM MERKLETREEJS (after padding leaves array):");
          console.log(`  Siblings: ${JSON.stringify(proof.map(p => BigInt("0x" + p.data.toString("hex")).toString()))}`);
          console.log(`  Directions: ${JSON.stringify(proof.map(p => (p.position === "right" ? 1 : 0)))}`);
          console.log(`  Length: ${proof.length}`); // This should now be 3
      }
  
      proofSiblings.push(proof.map(p => BigInt("0x" + p.data.toString("hex")).toString()));
      proofDirs.push(proof.map(p => (p.position === 'left' ? 1 : 0)));
    }
    // Now, proofSiblings and proofDirs will each contain 5 elements (proofs for the data leaves)
    // Each proof should be of length 3.
  
    // 7.1) Normalize proofs to match circuit DEPTH
    // This section should ideally not modify the proofs if they are already length 3.
    const DEPTH = 3; // Consistent with CIRCUIT_DEPTH above
    for (let i = 0; i < proofSiblings.length; i++) { // This loop runs 5 times
      let sibs = proofSiblings[i];
      let dirs = proofDirs[i];
  
      // This condition should ideally not be true anymore
      if (sibs.length > DEPTH) {
        console.warn(`Proof for data leaf ${i} is longer (${sibs.length}) than circuit DEPTH (${DEPTH}). Trimming.`);
        sibs = sibs.slice(0, DEPTH);
        dirs = dirs.slice(0, DEPTH);
      }
      // This loop should ideally not execute anymore
      let padded = false;
      while (sibs.length < DEPTH) {
        padded = true;
        const last = sibs.length > 0 ? sibs[sibs.length - 1] : paddingHex; // Use paddingHex if sibs is empty, though unlikely here
        sibs.push(last);
        dirs.push(0); // Defaulting dir to 0 for padding is a choice, might need review if padding happens
      }
      if (padded && i === 4) { // If expiry proof was padded
          console.warn("Expiry proof was padded by normalization logic. This is unexpected after leaf padding.");
      }
  
  
      proofSiblings[i] = sibs;
      proofDirs[i] = dirs;
  
      if (i === 4) { // Log expiry proof after normalization again
          console.log(`Expiry proof AFTER NORMALIZATION (with padding):`);
          console.log(`  Siblings: ${JSON.stringify(sibs)}`);
          console.log(`  Directions: ${JSON.stringify(dirs)}`);
          console.log(`  Length: ${sibs.length}`);
      }
    }

    // 8) Assemble input.json
    // This section should be fine as it uses indices 0-4 for your 5 data fields
    // and expects proofSiblings/proofDirs to have 5 entries.
    const input = {
      root:             BigInt("0x" + tree.getRoot().toString("hex")).toString(),
      senderHash:       fieldValues[0].toString(),
      recipientHash:    fieldValues[1].toString(),
      minAmt:           "0",
      maxAmt:           "999999999999",
      currencyHash:     fieldValues[3].toString(), // This is the keccak hash
      expTs:            fieldValues[4].toString(), // This is YYYYMMDD from dateStr
  
      senderPath:       proofSiblings[0],
      senderDirs:       proofDirs[0],
      recipientPath:    proofSiblings[1],
      recipientDirs:    proofDirs[1],
  
      amtPath:          proofSiblings[2],
      amtDirs:          proofDirs[2],
      amountVal:        fieldValues[2].toString(),
  
      ccyPath:          proofSiblings[3],
      ccyDirs:          proofDirs[3],
      currencyValHash:  fieldValues[3].toString(), // This is the private input, also the keccak hash
  
      expPath:          proofSiblings[4],
      expDirs:          proofDirs[4],
      expiryVal:        fieldValues[4].toString(), // This is the private input, YYYYMMDD
    };
  
    // 9) Write input.json
    fs.writeFileSync("circuits/inputs/input.json", JSON.stringify(input, null, 2));
    console.log("✅ Generated circuits/inputs/input.json with padded leaves.");

  }
  
  main().catch(console.error);