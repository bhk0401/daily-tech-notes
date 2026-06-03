#!/usr/bin/env python3
"""JWT Token Generator for API Gateway Testing"""

import jwt
import time
import sys

SECRET = "test-secret"
ISSUER = "test-issuer"

def generate_token(user_id: str, roles: list, exp_hours: int = 1) -> str:
    """Generate JWT Token"""
    payload = {
        "iss": ISSUER,
        "sub": user_id,
        "roles": roles,
        "iat": int(time.time()),
        "exp": int(time.time()) + exp_hours * 3600
    }
    token = jwt.encode(payload, SECRET, algorithm="HS256")
    return token

if __name__ == "__main__":
    # Default test user
    user_id = sys.argv[1] if len(sys.argv) > 1 else "user-123"
    roles = sys.argv[2].split(",") if len(sys.argv) > 2 else ["admin", "user"]
    
    token = generate_token(user_id, roles)
    print(f"JWT Token: {token}")
    print(f"\nUsage:")
    print(f"  Header: Authorization: Bearer {token}")
    print(f"  Query: ?jwt={token}")
    print(f"  Cookie: jwt={token}")
