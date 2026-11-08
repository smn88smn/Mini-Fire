#!/usr/bin/env python3
"""Gem code generator for the Mini Fire Telegram shop.

The in-game SPIN SHOP -> REDEEM GEM CODE dialog accepts codes in this format:
    MF-<payload>-<checksum>-<gems>

- payload: 6 random chars from the same alphabet used by the checksum
- checksum: 5 chars derived from HMAC-SHA256(CODE_SECRET, payload)
- gems: the number of gems the code grants (shown in the code itself)

Codes are one-time-use: the game records redeemed payloads in the player's
profile, so each code can only be redeemed once per account.

Usage:
  python3 tools/gem_codes.py 10          # 10 codes for 100 gems (default)
  python3 tools/gem_codes.py 5 250       # 5 codes for 250 gems
  python3 tools/gem_codes.py --check MF-XXXXXX-YYYYY-100   # verify a code
"""

import hashlib
import hmac
import random
import sys

CODE_SECRET = "MiniFire::gems::7f3a9c2e51b8d046"
CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def checksum(payload: str) -> str:
    mac = hmac.new(CODE_SECRET.encode(), payload.encode(), hashlib.sha256).digest()
    out = []
    for i in range(5):
        if i % 2 == 0:
            out.append(CODE_ALPHABET[(mac[i] >> 3) & 31])
        else:
            out.append(CODE_ALPHABET[mac[i] & 31])
    return "".join(out)


def make_code(gems: int) -> str:
    payload = "".join(random.choice(CODE_ALPHABET) for _ in range(6))
    return f"MF-{payload}-{checksum(payload)}-{gems}"


def check_code(code: str):
    parts = code.strip().upper().split("-")
    if len(parts) != 4 or parts[0] != "MF":
        return None
    _, payload, cks, gems = parts
    try:
        gems_val = int(gems)
    except ValueError:
        return None
    if len(payload) != 6 or len(cks) != 5 or checksum(payload) != cks:
        return None
    if gems_val <= 0 or gems_val > 100000:
        return None
    return gems_val


def main():
    args = sys.argv[1:]
    if args and args[0] == "--check":
        if len(args) < 2:
            print("usage: gem_codes.py --check MF-XXXXXX-YYYYY-100")
            sys.exit(2)
        val = check_code(args[1])
        if val is None:
            print("INVALID code")
            sys.exit(1)
        print(f"VALID - grants {val} gems")
        return

    count = int(args[0]) if args else 10
    gems = int(args[1]) if len(args) > 1 else 100
    if not (1 <= count <= 500):
        print("count must be 1..500")
        sys.exit(2)
    if not (1 <= gems <= 100000):
        print("gems must be 1..100000")
        sys.exit(2)
    print(f"# {count} gem codes ({gems} gems each) - sell these in your Telegram shop")
    for _ in range(count):
        print(make_code(gems))


if __name__ == "__main__":
    main()
