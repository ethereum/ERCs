#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "vyper==0.4.3",
#     "eth-abi>=5.0.0",
#     "ipfs-cid>=1.0.0",
# ]
# ///

import functools
import json
from pathlib import Path

import vyper

from eth_abi import encode as abi_encode

from ipfs_cid import cid_sha256_hash

CONTRACTS_DIR = Path(__file__).parent

DEPLOYMENT_PROXY = "0x4e59b44847b379578588920cA78FbF26c0B4956C"
SALT = b"\x00" * 32


def _compile_vyper(contract_path: str) -> bytes:
    input_bundle = vyper.compiler.input_bundle.FilesystemInputBundle([CONTRACTS_DIR])
    result = vyper.compile_from_file_input(
        input_bundle.load_file(contract_path),
        input_bundle=input_bundle,
        output_formats=["bytecode"],
    )
    return bytes.fromhex(result["bytecode"].removeprefix("0x"))


@functools.cache
def get_image_url() -> str:
    cid = cid_sha256_hash((CONTRACTS_DIR / "logo.svg").read_bytes())
    return f"ipfs://{cid}"


@functools.cache
def get_init_code() -> bytes:
    wr_code = _compile_vyper("WithdrawalReceiver.vy")
    erc_code = _compile_vyper("ERC8270.vy")
    image_url = get_image_url()

    return erc_code + abi_encode(["string", "bytes"], [image_url, wr_code])


@functools.cache
def get_deployment_tx():
    return {
        "to": DEPLOYMENT_PROXY,
        "input": "0x" + (SALT + get_init_code()).hex(),
    }


if __name__ == "__main__":
    result = {
        "image_url": get_image_url(),
        "initcode": "0x" + get_init_code().hex(),
        "deployment_tx": get_deployment_tx(),
    }
    print(json.dumps(result, indent=4))
