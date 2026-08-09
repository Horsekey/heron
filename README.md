# Heron: bait fishing with secrets

https://www.youtube.com/watch?v=K_Tv8bpiHQo&t

Hi. Was inspired to make a hacky deception tool in light of supply chain security issues. This is a tool that you can use to setup bait deploy keys that, when used, send you an alert. Detection comes from canarytokens embedded in the decoy's files (they fire when a threat actor uses them) or, if you have GitHub Enterprise, audit-log streaming for `git.clone`. GitHub emits no event for a deploy key being used, so there's no webhook that catches the clone itself. I have not found a way to consistently generate other types of tokens yet, but would love people to contribute.

# outline

    1. generate deployment keys
    2. associate deployment keys to fake repositories
    3. save private key to organization secrets
    4. alert on use of private key
    5. on alert, regenerate and rotate secret

## inspiration

[google cloud sec podcast](https://open.spotify.com/episode/2Ac5LRaC2fduw9B9S2A2WK?si=966f3c61985b414f)

## setup

The entire deployment of keys relies on a GitHub app that is given specific permissions to read and write secrets (this is a scenario where write-only permissions would be ideal but impossible) and, eventually, a GitHub action that you can configure to revoke and regenerate them on use.

You will need to setup a decoy repository that DOES NOT contain any real information. Since we're using read-only deploy keys, when threat actors use the tokens, real data WILL be lost.

## usage

Heron is a template repository, not an action. Click "Use this template" to get your own copy. The scripts and the workflow run entirely in your org, under your app, and nothing is ever sent back here. A tool that writes org-level secrets shouldn't be something you pull from a stranger at runtime.....

Then:

1. create a GitHub app with repo Administration:write (deploy keys) and org Secrets:write
2. install it on every org that owns decoy repos you want to target
3. save the app's client id and private key as `HERON_APP_CLIENT_ID` and `HERON_APP_PRIVATE_KEY` in your copy's repo secrets
4. run the "Generate & Deploy Canaries" workflow, passing `targets` as a space-separated `owner/repo` list. It can span multiple orgs, the workflow groups them and mints a separate app token per org.

You can also run `deploy_keys.sh` and `deploy_organization_secrets.sh` by hand the workflow is just those two scripts in a loop.

## setting it up to test

1. empty decoy repo in your org, no real data.
2. "Use this template" for your own copy.
3. new GitHub app, grant: repo Administration (read/write), org Secrets (read/write). Generate a private key, note the Client ID.
4. install the app on your org, give it the decoy repos.
5. add repo secrets `HERON_APP_CLIENT_ID` (Client ID) and `HERON_APP_PRIVATE_KEY` (the `.pem`).
6. Actions → "Generate & Deploy Canaries" → run with `targets` like `acme/decoy-api globex/decoy-x`.
7. check the deploy key and the org secret (`PRV_KEY` by default, or your `secret_name` input) landed in each org.

### seeding bait (optional, one-time, local)

Canarytokens are required if you do not have Enterprise Cloud (+ log streaming to catch it live) but they don't rotate with the deploy key, so seed them once locally.

**Give each decoy its own token** so a fired alert points at exactly one repo. Make sure to set the token's memo to the repo path when you generate it at [canarytokens.org](https://canarytokens.org).

Lay the bait out per repo, one dir each, then make sure to pepper with fake documents :D

```
bait/
  acme/decoy-api/.env        <- token with memo "acme/decoy-api"
  globex/decoy-x/.env        <- token with memo "globex/decoy-x"
```

Then `gh auth login` and seed them all:

```
./seed_bait.sh --map bait
```

(For a single repo: `./seed_bait.sh owner/repo somedir`.)

This commits the bait files with randomized, innocuous messages. Relies on your own GitHub access.

## future features

- [ ] Additional token support
- [ ] Free organization alerting
- [ ] Automatic creation and rotation of canary tokens and private keys

## disclaimer

Heron is not a Microsoft service or product. It is a personal project provided as-is for incorporating deception technology into your GitHub repositories, without any explicit or implicit obligations.

Heron only performs write operations and does not modify any pre-existing secrets or settings in your GitHub organization. Always validate deployment independently in a non-production environment before installing an organization-wide application that can write secrets at the organization level. The authors are not responsible for any misconfigurations or security issues resulting from the use of this tool.
