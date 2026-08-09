#!/usr/bin/env bash

client_id=$1 # Client ID as first argument
pem=$( cat $2 ) # file path of the private key as second argument
SECRET_FILE=$4 # file path of the plaintext secret value as fourth argument
TARGETS=()

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 300)) # Expires 5 min out (exp-iat must be <= 10 min)

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json="{
    \"iat\":${iat},
    \"exp\":${exp},
    \"iss\":\"${client_id}\"
}"
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT
JWT="${header_payload}"."${signature}"

read -r -a TARGETS <<< "$3"

gh_jwt() { curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $JWT" "$@"; }

for repo in "${TARGETS[@]}"; do
  org=${repo%%/*}

  # Look up this org's installation id from the JWT (no hardcoded id).
  inst=$(gh_jwt "https://api.github.com/orgs/$org/installation" | jq -r .id)
  [[ $inst =~ ^[0-9]+$ ]] || { echo "app not installed on org: $org" >&2; continue; }

  RESP=$(gh_jwt --request POST "https://api.github.com/app/installations/$inst/access_tokens")
  TOKEN=$(jq -r .token <<< "$RESP")
  [[ $TOKEN == ghs_* ]] || { echo "token mint failed for $org: $RESP" >&2; continue; }

  echo "storing org secret in $org (visibility all)"
  GH_TOKEN="$TOKEN" gh secret set "${CANARY_SECRET_NAME:-HERON_CANARY}" --org "$org" --visibility all < "$SECRET_FILE"
done
