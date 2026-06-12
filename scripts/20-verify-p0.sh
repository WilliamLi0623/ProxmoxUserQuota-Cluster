#!/usr/bin/env bash
# Verify the P0 exit criteria via the PVE API.
#
# Usage: 20-verify-p0.sh <api-base> <user1> <pass1> <user2> <pass2> <node> [--create <vmid>]
#   api-base   e.g. https://192.0.2.10:8006
#   user1/2    two provisioned test users (e.g. testuser1@pve)
#   node       node name used for the create attempts
#   --create   additionally create a real (disk-less) VM as user1 in their own
#              pool to prove the positive path; the VM is left in place for
#              GUI inspection and must be deleted manually afterwards.
#
# Checks:
#   1  each user sees exactly their own pool in GET /pools
#   2  user1 sees none of user2's guests in /cluster/resources
#   3  create WITHOUT a pool      -> denied (403)
#   4  create into user2's pool   -> denied (403)
#   5  pool membership edit       -> denied (403)
#   6  (--create) create into own pool -> allowed
#
# Needs: curl, python3. Accepts self-signed TLS (-k): test clusters only.
set -euo pipefail

[[ $# -ge 6 ]] || { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }
API="$1"; U1="$2"; P1="$3"; U2="$4"; P2="$5"; NODE="$6"
CREATE_VMID=""
if [[ "${7:-}" == "--create" ]]; then
  CREATE_VMID="${8:?--create needs a vmid}"
fi

pool1="uq-${U1%@*}"
pool2="uq-${U2%@*}"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
fails=0

json() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))' "$1"; }

login() { # $1 user, $2 pass -> sets TICKET, CSRF
  local resp
  resp="$(curl -ksS --data-urlencode "username=$1" --data-urlencode "password=$2" \
          "$API/api2/json/access/ticket")"
  TICKET="$(printf '%s' "$resp" | json 'd["data"]["ticket"]')"
  CSRF="$(printf '%s' "$resp" | json 'd["data"]["CSRFPreventionToken"]')"
}

req() { # $1 method, $2 path, $3 form-data (optional) -> echoes http code; body in $body
  local m="$1" p="$2" d="${3:-}"
  if [[ -n "$d" ]]; then
    curl -ksS -o "$body" -w '%{http_code}' -X "$m" \
      -b "PVEAuthCookie=${TICKET}" -H "CSRFPreventionToken: ${CSRF}" \
      --data "$d" "$API/api2/json$p"
  else
    curl -ksS -o "$body" -w '%{http_code}' -X "$m" \
      -b "PVEAuthCookie=${TICKET}" "$API/api2/json$p"
  fi
}

check() { # $1 description, $2 expected, $3 actual
  if [[ "$3" == "$2" ]]; then
    echo "PASS: $1 (got $3)"
  else
    echo "FAIL: $1 (expected $2, got $3)"
    fails=$((fails + 1))
  fi
}

echo "== login =="
login "$U1" "$P1"; T1="$TICKET"; C1="$CSRF"
login "$U2" "$P2"; T2="$TICKET"; C2="$CSRF"
echo "ok: both users authenticated"

echo "== 1: pool visibility =="
TICKET="$T1"; CSRF="$C1"
code="$(req GET /pools)"
check "user1 GET /pools" 200 "$code"
pools="$(json 'sorted(p["poolid"] for p in d["data"])' < "$body")"
check "user1 sees exactly [$pool1]" "['$pool1']" "$pools"

TICKET="$T2"; CSRF="$C2"
code="$(req GET /pools)"
check "user2 GET /pools" 200 "$code"
pools="$(json 'sorted(p["poolid"] for p in d["data"])' < "$body")"
check "user2 sees exactly [$pool2]" "['$pool2']" "$pools"

echo "== 2: resource invisibility =="
TICKET="$T1"; CSRF="$C1"
code="$(req GET "/cluster/resources?type=vm")"
check "user1 GET /cluster/resources" 200 "$code"
foreign="$(json "sum(1 for r in d['data'] if r.get('pool')=='$pool2')" < "$body")"
check "user1 sees 0 guests of $pool2" 0 "$foreign"

echo "== 3: create without pool denied =="
code="$(req POST "/nodes/$NODE/qemu" "vmid=999111&cores=1&memory=128")"
check "create without pool denied" 403 "$code"

echo "== 4: create into foreign pool denied =="
code="$(req POST "/nodes/$NODE/qemu" "vmid=999112&cores=1&memory=128&pool=$pool2")"
check "create into $pool2 denied" 403 "$code"

echo "== 5: pool membership edit denied =="
code="$(req PUT "/pools/$pool1" "vms=999113")"
if [[ "$code" == "404" || "$code" == "405" ]]; then
  # newer API shape (PUT /pools with poolid in the body)
  code="$(req PUT "/pools" "poolid=$pool1&vms=999113")"
fi
check "pool membership edit denied" 403 "$code"

if [[ -n "$CREATE_VMID" ]]; then
  echo "== 6: create into own pool allowed =="
  code="$(req POST "/nodes/$NODE/qemu" \
    "vmid=$CREATE_VMID&name=uq-p0-test&cores=1&memory=128&pool=$pool1")"
  check "create VM $CREATE_VMID in $pool1 allowed" 200 "$code"
  echo "NOTE: VM $CREATE_VMID left in place; inspect it in the GUI, then delete it manually."
fi

echo
if [[ "$fails" -eq 0 ]]; then
  echo "ALL CHECKS PASSED"
else
  echo "$fails CHECK(S) FAILED"
  exit 1
fi
