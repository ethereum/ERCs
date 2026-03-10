import { keccak256 } from "@ethersproject/keccak256";

export function _keccak256(data: Buffer): Buffer {
  return Buffer.from(keccak256(data).slice(2), "hex");
}

export class MerkleTree {
  private readonly levels: Buffer[][];

  constructor(_messages: readonly Buffer[]) {
    const messages = [..._messages];
    let k = Math.ceil(Math.log2(messages.length));
    for (let i = messages.length; i < 1 << k; i++) {
      messages.push(Buffer.alloc(messages[0].length));
    }

    let currentLevel = messages;
    this.levels = [currentLevel];
    while (currentLevel.length > 1) {
      const nextLevel = [];
      for (let i = 0; i < currentLevel.length; i += 2) {
        const pair =
          currentLevel[i].compare(currentLevel[i + 1]) < 0
            ? [currentLevel[i], currentLevel[i + 1]]
            : [currentLevel[i + 1], currentLevel[i]];
        nextLevel.push(_keccak256(Buffer.concat(pair)));
      }
      currentLevel = nextLevel;
      this.levels.push(nextLevel);
    }
  }

  getProof(message: Buffer): readonly Buffer[] {
    // ceil(8/2)-1
    let index = this.levels[0].findIndex((m) => m.compare(message) === 0);
    if (index === -1) {
      throw new Error("Message not found");
    }
    let levelIndex = 0;
    let level = this.levels[0];
    let proof: Buffer[] = [];
    while (level.length > 1) {
      proof.push(level[index ^ 1]);
      index = Math.ceil((index + 1) / 2) - 1;
      level = this.levels[++levelIndex];
    }
    return proof as readonly Buffer[];
  }

  getRoot(): Buffer {
    return this.levels[this.levels.length - 1][0];
  }
}
