#!/usr/bin/env bash
# Replace every deploy key on each target repo with a fresh bait key, and optionally
# stash the private half in a secrets manager. Keys land in the current directory
# as heron-canary-<random> and heron-canary-<random>.pub.
#
#   ./mint.sh [--secrets-manager aws|azure] [--aws-profile NAME] [--vault-name NAME] [--targets "owner/repo ..."]
#
# KEY_TITLE overrides the deploy key's title; otherwise a plausible one is picked at random.

secrets_provider=""
aws_profile=""
vault_name=""
targets=()

titles=("Production Server" "CI Deploy" "prod-deploy" "gh-actions-deploy" "release-bot" "staging-deploy")
key_title=${KEY_TITLE:-${titles[RANDOM % ${#titles[@]}]}}

usage() {
  echo "usage: $0 [--secrets-manager aws|azure] [--aws-profile NAME] [--vault-name NAME] [--targets \"owner/repo ...\"]" >&2
  exit 1
}

# every flag takes exactly one value
while [[ $# -gt 0 ]]; do
  if [[ $1 == -h || $1 == --help ]]; then
    usage
  fi
  if [[ $# -lt 2 ]]; then
    echo "missing value for $1" >&2
    usage
  fi
  case $1 in
    --secrets-manager) secrets_provider=$2 ;;
    --aws-profile)     aws_profile=$2 ;;
    --vault-name)      vault_name=$2 ;;
    --targets)         read -r -a targets <<< "$2" ;;   # space-separated list
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
  shift 2
done

for repo in "${targets[@]}"; do
  secret_name=heron-canary-$RANDOM
  key=$PWD/$secret_name

  # the "y" answers ssh-keygen's overwrite prompt if the random name is already taken
  echo y | ssh-keygen -t ed25519 -C "null" -f "$key" -N "" -q

  # drop every existing deploy key, then add ours
  for id in $(gh api "repos/$repo/keys" --jq '.[].id'); do
    gh api -X DELETE "repos/$repo/keys/$id" >&2
  done
  gh repo deploy-key add "$key.pub" -R "$repo" --title "$key_title"

  # optionally keep the private half in a secrets manager; otherwise it stays on disk here
  case $secrets_provider in
    aws)
      echo "Using AWS secrets manager"
      aws secretsmanager create-secret --name "$secret_name" --secret-string "file://$key" \
        --region us-east-2 --profile "$aws_profile"
      ;;
    azure)
      echo "Using Azure Key Vault"
      az keyvault secret set --vault-name "$vault_name" --name "$secret_name" --file "$key"
      ;;
  esac
done
