#!/usr/bin/env python3
"""
Generate a new secp256k1 private/public keypair for genesis block use.

Outputs:
- Private key (hex)
- Public key (hex, uncompressed)
- Public key (hex, compressed)

Requires: ecdsa (pip install ecdsa)
"""
import os
import binascii
from ecdsa import SigningKey, SECP256k1

# Generate private key
sk = SigningKey.generate(curve=SECP256k1)
private_key = sk.to_string().hex()

# Get uncompressed public key
vk = sk.get_verifying_key()
public_key_bytes = b'\x04' + vk.to_string()
public_key_hex = public_key_bytes.hex()

# Get compressed public key
x = vk.to_string()[:32]
y = vk.to_string()[32:]
if int.from_bytes(y, 'big') % 2 == 0:
    prefix = b'\x02'
else:
    prefix = b'\x03'
public_key_compressed = (prefix + x).hex()

print(f"Private key (hex):   {private_key}")
print(f"Public key (hex, uncompressed): {public_key_hex}")
print(f"Public key (hex, compressed):   {public_key_compressed}")
print("\nSave the private key securely! Use the uncompressed public key for genesis block creation.")
