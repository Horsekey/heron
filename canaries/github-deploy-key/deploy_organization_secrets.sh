#!/usr/bin/env bash
# Store a secret file as an org secret in the org of every target, authenticating as a GitHub App.
#
#   ./deploy_organization_secrets.sh <app_client_id> <app_private_key.pem> "<owner/repo ...>" <secret_file>
#
# Secret name: $CANARY_SECRET_NAME (default HERON_CANARY), visible to all repos in the org.

client_id=$1
pem_file=$2
read -r -a targets <<< "$3"
secret_file=$4

b64url() { openssl base64 | tr -d '=\n' | tr '/+' '_-'; }

# App JWT: issued 60s in the past for clock drift, expires in 5 min (GitHub allows at most 10).
now=$(date +%s)
header=$(printf '%s' '{"typ":"JWT","alg":"RS256"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 300)) "$client_id" | b64url)
signature=$(printf '%s' "$header.$payload" | openssl dgst -sha256 -sign "$pem_file" | b64url)
jwt=$header.$payload.$signature

as_app() {
  curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $jwt" "$@"
}

for repo in "${targets[@]}"; do
  org=${repo%%/*}

  # Look up the app's installation on this org (no hardcoded id).
  installation=$(as_app "https://api.github.com/orgs/$org/installation" | jq -r .id)
  if [[ ! $installation =~ ^[0-9]+$ ]]; then
    echo "app not installed on org: $org" >&2
    continue
  fi

  response=$(as_app -X POST "https://api.github.com/app/installations/$installation/access_tokens")
  token=$(jq -r .token <<< "$response")
  if [[ $token != ghs_* ]]; then
    echo "token mint failed for $org: $response" >&2
    continue
  fi

  echo "storing org secret in $org (visibility all)"
  GH_TOKEN=$token gh secret set "${CANARY_SECRET_NAME:-HERON_CANARY}" --org "$org" --visibility all < "$secret_file"
done
