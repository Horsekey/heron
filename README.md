# Heron: bait fishing with secrets

https://www.youtube.com/watch?v=K_Tv8bpiHQo&t

Hi. Was inspired to make a hacky deception tool in light of supply chain security issues. 

This is a tool that you can use to setup bait SSH deploy keys and classic personal access tokens as organization-level secrets that, when stolen and used, fire off alerts. On use of the stolen private key, GitHub Enterprise audit logs will generate a `git.clone` event, which you can monitor for from the repositories you create and associate the fake deploy keys to.

If you don't have Github Enterprise, I've setup a way to generate classic personal access tokens on an account outside of your organization for alerting. This works because there is a specific header returned by GitHub via their REST API and GraphQL endpoints `x-ratelimit-used`. If we know with our action that we're spending one rate limit, we can look and alert on unexpected jumps.

## inspiration

[google cloud sec podcast](https://open.spotify.com/episode/2Ac5LRaC2fduw9B9S2A2WK?si=966f3c61985b414f)

## setup

There are two components to setup. 

The main functionality because it is free is the GitHub Classic Personal Access Token version. 

You can still setup deploy keys if you have log streaming setup, but detection is VERY, EXTREMELY, GIGANTICALLLY delayed.

### github classic pats

1. create random GitHub bait account

2. install pre-reqs
  * curl, jq, ssh-keygen, gh
  * pip install playwright pyyaml && playwright install chromium

3. cp heron.yaml.example -> heron.yaml
  * add one entry under `baits:` for each account. `repo:` is a bare name with no owner. `pat: true` is the default, and `deploy:` is optional

4. run `./heron init`
  * A browser window opens for each bait. Log in as that bait account when it asks. The script then:
    - creates the decoy repo as private, and stops if it ends up public;
    - mints a classic PAT with no expiration and only the repo scope. Classic is used because fine-grained tokens expire after at most a year, and repo is what lets the watcher read the decoy's clone traffic;
    - writes repo<TAB>token<TAB>login to ~/.heron/fleet, with permissions 600.
    
    - Logins are cached in .pw-bait-<repo> browser profiles, so later runs don't ask again.
    - Baits with pat: false get no token and are not added to the fleet file.

5. run `./heron secrets <you>/<private-repo> (logged in with gh cli) to upload the fleet file to the repo you want to use for alerting.
  * saves the fleet to `HERON_FLEET` secret
  
6. plant the tokens (stored in ~/.heron/ and ~/.heron/out by default) in your real repositories.

7. profit :D

Optional settings:
- `HERON_WEBHOOK` secret: posts alerts to Slack or Teams.
- `HERON_REVOKE=1` repo variable: automatically revokes any token that fires.

### deploy keys (optional)

The entire deployment of keys relies on a GitHub app you create with permissions to read and write secrets (this is a scenario where write-only permissions would be ideal but impossible) and, eventually, a GitHub action that you can configure to revoke and regenerate them on use.

Setup a decoy repository in one organization that DOES NOT contain any real information. Since we're using read-only deploy keys, when threat actors use the tokens, real data WILL be lost.

1. create a GitHub app with repo Administration:write (deploy keys) and org Secrets:write

2. install it on every org that owns decoy repos you want to target

3. save the app's client id and private key as `HERON_APP_CLIENT_ID` and `HERON_APP_PRIVATE_KEY` in your copy's repo secrets

4. run the "Generate & Deploy Canaries" workflow, passing `targets` as a space-separated `owner/repo` list. It can span multiple orgs, the workflow groups them and mints a separate app token per org.

You can also run `mint.sh` and `deploy_organization_secrets.sh` by hand the workflow is just those two scripts in a loop. `lib/provision.py` will also create deploy keys if you setup heron.yaml correctly.

## setting it up to test

1. empty decoy repo in your org, no real data.
2. "Use this template" for your own copy.
3. new GitHub app, grant: repo Administration (read/write), org Secrets (read/write). Generate a private key, note the Client ID.
4. install the app on your org, give it the decoy repos.
5. add repo secrets `HERON_APP_CLIENT_ID` (Client ID) and `HERON_APP_PRIVATE_KEY` (the `.pem`).
6. Actions → "Generate & Deploy Canaries" → run with `targets` like `acme/decoy-api globex/decoy-x`.
7. check the deploy key and the org secret (`PRV_KEY` by default, or your `secret_name` input) landed in each org.

## future features

- [x] Additional token support (Classic PATs)
- [x] Free organization alerting
- [x] Automatic creation and rotation of github tokens
- [ ] Automatic creation and rotation of deploy keys

## disclaimer

Heron is not a Microsoft service or product. It is a personal project provided as-is for incorporating deception technology into your GitHub repositories, without any explicit or implicit obligations.

Heron only performs write operations and does not modify any pre-existing secrets or settings in your GitHub organization. Always validate deployment independently in a non-production environment before installing an organization-wide application that can write secrets at the organization level. The authors are not responsible for any misconfigurations or security issues resulting from the use of this tool.
