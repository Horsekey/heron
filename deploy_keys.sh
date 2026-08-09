#!/usr/bin/env bash

# consts
SECRETS_PROVIDER=""
AWS_PROFILE=""
VAULT_NAME=""
TITLES=("Production Server" "CI Deploy" "prod-deploy" "gh-actions-deploy" "release-bot" "staging-deploy")
KEY_TITLE=${KEY_TITLE:-${TITLES[RANDOM % ${#TITLES[@]}]}}

# usage
usage() {
  echo "usage: $0 [--secrets-manager aws|azure] [--aws-profile NAME] [--vault-name NAME] [--targets owner/repo owner/repo ...]" >&2
  exit 1
}

# main loop reads in various tags as arguments
while [[ $# -gt 0 ]]; do
  [[ $1 == -h || $1 == --help ]] && usage
  [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; usage; }
  case $1 in
    --secrets-manager) SECRETS_PROVIDER=$2 ;;
    --aws-profile)     AWS_PROFILE=$2 ;;
    --vault-name)      VAULT_NAME=$2 ;;
    --targets)          read -r -a TARGETS <<< "$2" ;; # Splits string into array cleanly
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
  shift 2
done

# loop over each target, for each target generate a deploy key, add it to your canary repositories, and deploy the secrets with fake names 
for repo in "${TARGETS[@]}"; do
 SECRET_NAME="heron-canary-$RANDOM"
 echo y | ssh-keygen -t ed25519 -C "null" -f $(pwd)/$SECRET_NAME -N "" -q

  # need github app that can add these automatically to the org references in targets
  gh api repos/$repo/keys --jq '.[].id' | xargs -I {} gh api -X DELETE repos/$repo/keys/{} >&2
  gh repo deploy-key add $(pwd)/$SECRET_NAME.pub -R "$repo" --title "$KEY_TITLE"

  # optionally save private key to secrets manager of choice (azure kv, secrets manager, or local/manual)
  case "$SECRETS_PROVIDER" in
    aws)
      echo "Using AWS secrets manager"
      aws secretsmanager create-secret --name $SECRET_NAME --secret-string file://$(pwd)/$SECRET_NAME --region us-east-2 --profile $AWS_PROFILE
      ;;
    azure)
      echo "Using Azure Key Vault"
      az keyvault secret set --vault-name $VAULT_NAME --name $SECRET_NAME --file $(pwd)/$SECRET_NAME
      ;;
  esac
done
