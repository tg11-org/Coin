#!/usr/bin/env python3
"""
Genesis Block Generator for TG11 (Litecoin/Bitcoin-based forks)

Usage:
  python3 genesis.py --timestamp <int> --message "<string>" --bits <hex> --pubkey <hex> --reward <int>

Example:
  python3 genesis.py --timestamp 1716100000 --message "TG11 Mainnet Launch" --bits 1e0ffff0 --pubkey 04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f --reward 50

Outputs genesis hash, merkle root, and nonce.
"""
import hashlib
import struct
import time
import argparse

# Helper functions
def sha256d(data):
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()

def little_endian(hexstr):
    return bytes.fromhex(hexstr)[::-1]

def encode_varint(i):
    if i < 0xfd:
        return struct.pack('<B', i)
    elif i <= 0xffff:
        return b'\xfd' + struct.pack('<H', i)
    elif i <= 0xffffffff:
        return b'\xfe' + struct.pack('<I', i)
    else:
        return b'\xff' + struct.pack('<Q', i)

def create_coinbase_tx(message, pubkey, reward):
    # Coinbase input
    script_sig = message.encode('utf-8')
    script_sig = encode_varint(len(script_sig)) + script_sig
    txin = (
        b'\x00' * 32 +  # prevout hash
        b'\xff\xff\xff\xff' +  # prevout index
        encode_varint(len(script_sig)) + script_sig +
        b'\xff\xff\xff\xff'  # sequence
    )
    # Coinbase output
    pubkey_bytes = bytes.fromhex(pubkey)
    script_pubkey = b'\x41' + pubkey_bytes + b'\xac'  # OP_PUSHDATA 65 + pubkey + OP_CHECKSIG
    txout = (
        struct.pack('<Q', reward * 100000000) +  # reward in satoshis
        encode_varint(len(script_pubkey)) + script_pubkey
    )
    # Assemble tx
    tx = (
        b'\x01\x00\x00\x00' +  # version
        b'\x01' + txin +  # 1 input
        b'\x01' + txout +  # 1 output
        b'\x00\x00\x00\x00'  # locktime
    )
    return tx

def mine_genesis_block(version, prev_block, merkle_root, timestamp, bits, reward, pubkey, message):
    target = (bits & 0xffffff) * 2 ** (8 * ((bits >> 24) - 3))
    nonce = 0
    coinbase_tx = create_coinbase_tx(message, pubkey, reward)
    merkle_root_hash = sha256d(coinbase_tx)
    print(f"Merkle root: {merkle_root_hash[::-1].hex()}")
    while True:
        header = (
            struct.pack('<L', version) +
            bytes.fromhex(prev_block)[::-1] +
            merkle_root_hash[::-1] +
            struct.pack('<L', timestamp) +
            struct.pack('<L', bits) +
            struct.pack('<L', nonce)
        )
        hash_ = sha256d(header)
        hash_int = int.from_bytes(hash_[::-1], 'big')
        if hash_int < target:
            print(f"Found genesis hash: {hash_[::-1].hex()}")
            print(f"Nonce: {nonce}")
            print(f"Timestamp: {timestamp}")
            print(f"Bits: {bits:08x}")
            print(f"Merkle root: {merkle_root_hash[::-1].hex()}")
            return hash_[::-1].hex(), nonce, merkle_root_hash[::-1].hex()
        nonce += 1
        if nonce % 1000000 == 0:
            print(f"Tried {nonce} nonces...")

def main():
    parser = argparse.ArgumentParser(description="Genesis Block Generator for TG11")
    parser.add_argument('--timestamp', type=int, required=True, help='Block timestamp (UNIX time)')
    parser.add_argument('--message', type=str, required=True, help='Genesis block message')
    parser.add_argument('--bits', type=lambda x: int(x, 16), required=True, help='Difficulty bits (hex, e.g. 1e0ffff0)')
    parser.add_argument('--pubkey', type=str, required=True, help='Hex-encoded pubkey for coinbase output')
    parser.add_argument('--reward', type=int, default=50, help='Block reward (default: 50)')
    parser.add_argument('--version', type=int, default=1, help='Block version (default: 1)')
    parser.add_argument('--prevblock', type=str, default='00'*32, help='Previous block hash (default: all zeroes)')
    args = parser.parse_args()

    print(f"Generating genesis block with timestamp={args.timestamp}, message='{args.message}', bits={args.bits:08x}")
    print(f"Pubkey: {args.pubkey}")
    print(f"Reward: {args.reward}")
    print(f"Block version: {args.version}")
    print(f"Prev block: {args.prevblock}")

    mine_genesis_block(
        version=args.version,
        prev_block=args.prevblock,
        merkle_root=None,
        timestamp=args.timestamp,
        bits=args.bits,
        reward=args.reward,
        pubkey=args.pubkey,
        message=args.message
    )

if __name__ == '__main__':
    main()
