#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""纯标准库 RSA 加密（PKCS#1 v1.5）

长安 iov 的 /encrypt_data 需要把明文用服务端下发的公钥做 RSA 加密，
容器里的 python 没有 cryptography 包，这里手写 DER 解析 + 模幂运算。

支持输入：
 - PEM（-----BEGIN PUBLIC KEY-----）  → SPKI
 - PEM（-----BEGIN RSA PUBLIC KEY---）→ PKCS#1
 - 裸 base64（无头尾，按 SPKI 处理）
"""
import base64
import hashlib
import binascii
import os
import re


def _der_read(buf, i):
    """读一个 TLV，返回 (tag, value_bytes, next_index)"""
    tag = buf[i]
    i += 1
    ln = buf[i]
    i += 1
    if ln & 0x80:
        n = ln & 0x7F
        ln = int.from_bytes(buf[i:i + n], "big")
        i += n
    return tag, buf[i:i + ln], i + ln


def _der_seq(buf):
    """把 SEQUENCE 拆成子项列表 [(tag, value)]"""
    out = []
    i = 0
    while i < len(buf):
        tag, val, i = _der_read(buf, i)
        out.append((tag, val))
    return out


def parse_public_key(pem_or_b64):
    """返回 (n, e)"""
    s = (pem_or_b64 or "").strip()
    if "-----BEGIN" in s:
        body = re.sub(r"-----[^-]+-----", "", s)
    else:
        body = s
    body = re.sub(r"\s+", "", body)
    der = base64.b64decode(body + "=" * (-len(body) % 4))

    tag, val, _ = _der_read(der, 0)
    if tag != 0x30:
        raise ValueError("不是 DER SEQUENCE")
    items = _der_seq(val)
    # SPKI: SEQUENCE { AlgorithmIdentifier, BIT STRING }
    if len(items) == 2 and items[0][0] == 0x30 and items[1][0] == 0x03:
        bits = items[1][1][1:]          # 去掉 unused-bits 字节
        tag2, val2, _ = _der_read(bits, 0)
        items = _der_seq(val2)
        if len(items) != 2:
            raise ValueError("RSAPublicKey 结构异常")
    if len(items) != 2 or items[0][0] != 0x02 or items[1][0] != 0x02:
        raise ValueError("不是 RSA 公钥")
    n = int.from_bytes(items[0][1], "big")
    e = int.from_bytes(items[1][1], "big")
    return n, e


def encrypt(pem_or_b64, plaintext):
    """RSA/PKCS1-v1.5 加密，返回 base64 字符串"""
    n, e = parse_public_key(pem_or_b64)
    k = (n.bit_length() + 7) // 8
    msg = plaintext.encode("utf-8") if isinstance(plaintext, str) else plaintext
    if len(msg) > k - 11:
        raise ValueError("明文太长：%d > %d" % (len(msg), k - 11))
    ps_len = k - 3 - len(msg)
    # 非零随机填充
    ps = bytearray()
    while len(ps) < ps_len:
        ps += os.urandom(ps_len - len(ps))
        ps = bytearray(b for b in ps if b != 0)
    ps = ps[:ps_len]
    em = b"\x00\x02" + bytes(ps) + b"\x00" + msg
    c = pow(int.from_bytes(em, "big"), e, n)
    return base64.b64encode(c.to_bytes(k, "big")).decode()


if __name__ == "__main__":
    import sys
    pub = open(sys.argv[1], encoding="utf-8").read()
    print(encrypt(pub, sys.argv[2] if len(sys.argv) > 2 else "hello"))


def _mgf1(seed, length, hash_name="sha256"):
    out = b""
    counter = 0
    while len(out) < length:
        out += hashlib.new(hash_name, seed + counter.to_bytes(4, "big")).digest()
        counter += 1
    return out[:length]


def _oaep_pad(msg, k, hash_name="sha256"):
    h_len = hashlib.new(hash_name).digest_size
    if len(msg) > k - 2 * h_len - 2:
        raise ValueError("message too long for OAEP")
    l_hash = hashlib.new(hash_name, b"").digest()
    ps = b"\x00" * (k - len(msg) - 2 * h_len - 2)
    db = l_hash + ps + b"\x01" + msg
    seed = os.urandom(h_len)
    masked_db = bytes(a ^ b for a, b in zip(db, _mgf1(seed, k - h_len - 1, hash_name)))
    masked_seed = bytes(a ^ b for a, b in zip(seed, _mgf1(masked_db, h_len, hash_name)))
    return b"\x00" + masked_seed + masked_db


def encrypt_oaep(pem_or_b64, plaintext, hash_name="sha256"):
    """RSA-OAEP 加密（长安控车用的是这套）"""
    n, e = parse_public_key(pem_or_b64)
    k = (n.bit_length() + 7) // 8
    padded = _oaep_pad(plaintext.encode("utf-8"), k, hash_name)
    c = pow(int.from_bytes(padded, "big"), e, n)
    return base64.b64encode(c.to_bytes(k, "big")).decode()
