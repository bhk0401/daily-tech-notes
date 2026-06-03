#!/bin/bash
# API Gateway Test Script

BASE_URL="http://localhost:8000"

# Generate token
TOKEN=$(python3 generate_jwt.py 2>/dev/null | grep "JWT Token" | awk '{print $3}')
if [ -z "$TOKEN" ]; then
    TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ0ZXN0LWlzc3VlciIsInN1YiI6InVzZXItMTIzIiwicm9sZXMiOlsiYWRtaW4iXSwiaWF0IjoxNzE3MzgwMDAwLCJleHAiOjE3MTc0NjY0MDB9.test"
    echo "Using fallback token for testing"
fi

echo "=== Test 1: No Token (expect 401) ==="
curl -s -o /dev/null -w "Status: %{http_code}\n" "$BASE_URL/api/users"

echo -e "\n=== Test 2: Valid Token (expect 200) ==="
curl -s -o /dev/null -w "Status: %{http_code}\n" -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/users"

echo -e "\n=== Test 3: Rate Limit Test (120 requests) ==="
count=0
for i in {1..120}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/users")
  if [ "$STATUS" = "429" ]; then
    echo "Rate limited at request $i (429)"
    break
  fi
  count=$i
  [ $((i % 30)) -eq 0 ] && echo "Completed $i requests..."
done
echo "Total successful requests: $count"

echo -e "\n=== Test Complete ==="
