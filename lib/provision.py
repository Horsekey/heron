#!/usr/bin/env python3
"""Provision every bait account in heron.yaml through its own browser session.

    provision.py <heron.yaml> <out-dir> <profile-prefix>

Prints "repo<TAB>token<TAB>login[<TAB>deploy-only]" per bait on stdout, messages on stderr.
"""
import os, re, subprocess, sys, time
import yaml
from playwright.sync_api import sync_playwright


def log(*a): print(*a, file=sys.stderr, flush=True)


def read_baits(cfg, out, prefix):
    baits = (yaml.safe_load(open(cfg)) or {}).get("baits") or []
    if not baits:
        sys.exit(f"no baits listed in {cfg}")
    specs = []
    for b in baits:
        repo = str(b.get("repo", "")).strip()
        if not repo:
            sys.exit("every bait needs a repo")
        if any(c.isspace() or c == "/" for c in repo):
            sys.exit(f"repo {repo!r} must be a bare name, no spaces or slashes")

        title = str(b.get("deploy", "") or "").strip()
        pub = ""
        if title:
            key = os.path.join(out, f"heron-{repo}")
            if not os.path.exists(key):
                subprocess.run(["ssh-keygen", "-t", "ed25519", "-C", "", "-f", key,
                                "-N", "", "-q"], check=True)
            pub = open(key + ".pub").read().strip()

        # one token per account
        specs.append({"repo": repo, "profile": prefix + repo,
                      "pat": bool(b.get("pat", True)), "key": pub, "title": title})
    return specs


def fill_first(value, *locators):
    # GitHub's markup shifts and get_by_label often matches a button too.
    for loc in locators:
        try:
            loc.first.fill(value, timeout=8000)
            return True
        except Exception:
            continue
    return False


def pick_dropdown(page, opener_re, item_re):
    # visibility and expiration are Primer dropdowns.
    for opener in (page.get_by_role("button", name=re.compile(opener_re, re.I)),
                   page.locator("button").filter(has_text=re.compile(opener_re, re.I))):
        try:
            opener.first.click(timeout=8000)
            break
        except Exception:
            continue
    else:
        return False
    for item in (page.get_by_role("menuitemradio", name=re.compile(item_re, re.I)),
                 page.get_by_role("menuitem", name=re.compile(item_re, re.I)),
                 page.get_by_role("option", name=re.compile(item_re, re.I)),
                 page.locator("[role=menu]").get_by_text(re.compile(item_re, re.I))):
        try:
            item.first.click(timeout=5000)
            return True
        except Exception:
            continue
    return False


def wait_for_login(page, taken):
    # the user-login meta tag is present if a session exists. The persistent profile caches it, so this only blocks the first time for a given account.
    def who():
        try:
            return page.evaluate(
                "document.querySelector('meta[name=\"user-login\"]')?.content || ''")
        except Exception:
            return ""
    page.goto("https://github.com/login")
    asked = scolded = ""
    waited = 0
    while True:
        login = who()
        # one account per bait
        if login and login not in taken:
            return login
        if login and scolded != login:
            log(f"  this is {login}, which already carries '{taken[login]}'.")
            log("  sign out and sign in as a DIFFERENT bait account.")
            scolded = login
        elif not login and not asked:
            log("  log in as the BAIT account in the browser window...")
            asked = "1"
        page.wait_for_timeout(2000)
        waited += 2
        if waited % 30 == 0:
            log(f"  still waiting ({waited}s)")


def make_repo(page, login, name):
    resp = page.goto(f"https://github.com/{login}/{name}")
    if not (resp and resp.status == 404):
        log(f"  {name} already exists")
        return
    page.goto("https://github.com/new")
    if not fill_first(name,
                      page.get_by_role("textbox", name=re.compile("Repository name", re.I)),
                      page.locator("#repository-name-input")):
        page.screenshot(path="fail-newrepo.png")
        sys.exit("could not fill the repository name (shot fail-newrepo.png)")

    # make sure repo is private
    if not pick_dropdown(page, r"^(Public|Private)$", "Private"):
        page.screenshot(path="fail-private.png")
        sys.exit("could not set the repo Private (shot fail-private.png)")

    # the submit button stays disabled until GitHub validates the name is free
    page.wait_for_function("""() => {
        const b = [...document.querySelectorAll('button,input[type=submit]')]
          .find(x => /create repository/i.test((x.textContent || x.value || '').trim()));
        return b && !b.disabled && !b.getAttribute('aria-disabled');
      }""", timeout=60000)
    page.evaluate("""() => [...document.querySelectorAll('button,input[type=submit]')]
        .find(x => /create repository/i.test((x.textContent || x.value || '').trim())).click()""")
    page.wait_for_url(re.compile(rf"github\.com/{login}/{name}"), timeout=60000)

    # make sure to alarm on public repo creation
    if not page.evaluate("""() => {
           const h = document.querySelector('#repository-container-header') || document.body;
           return /(^|\\s)Private(\\s|$)/.test((h.innerText || '').slice(0, 800));
         }"""):
        page.screenshot(path="fail-visibility.png")
        sys.exit(f"{name} was created but is NOT private - fix it before planting")
    log(f"  created {login}/{name} (private)")


def add_deploy_key(page, login, spec):
    if not spec["key"]:
        return
    name = spec["repo"]
    page.goto(f"https://github.com/{login}/{name}/settings/keys/new")
    ok = fill_first(spec["title"],
                    page.get_by_role("textbox", name=re.compile(r"^Title", re.I)))
    ok &= fill_first(spec["key"],
                     page.get_by_role("textbox", name=re.compile(r"^Key", re.I)))
    if not ok:
        page.screenshot(path=f"fail-deploykey-{name}.png")
        sys.exit(f"could not fill the deploy key form for {name}")
    page.get_by_role("button", name=re.compile("Add key")).first.click()
    page.wait_for_url(re.compile(r"/settings/keys"), timeout=60000)
    log(f"  added deploy key to {name}")


def mint_token(page):
    # classic tokens since fine-grained ones cap at a year
    note = f"heron-canary-{int(time.time())}"
    page.goto("https://github.com/settings/tokens/new")
    if "/settings/tokens/new" not in page.url:
        sys.exit(f"redirected to {page.url} - not the classic token page")
    if not fill_first(note, page.get_by_role("textbox", name=re.compile("Note", re.I))):
        page.screenshot(path="fail-note.png")
        sys.exit("could not fill the token note (shot fail-note.png)")

    if not pick_dropdown(page, r"\d+\s*days|No expiration|Custom", "No expiration"):
        page.screenshot(path="fail-expiration.png")
        sys.exit("could not select 'No expiration' (shot fail-expiration.png)")

    # repo is the only scope a bait needs
    if not page.evaluate("""() => {
          const el = document.querySelector('input[type=checkbox][value="repo"]');
          if (!el) return false;
          if (!el.checked) el.click();
          return el.checked;
        }"""):
        page.screenshot(path="fail-scope.png")
        sys.exit("could not select the 'repo' scope (shot fail-scope.png)")

    page.get_by_role("button", name=re.compile("^Generate token$")).first.click()
    page.wait_for_url(re.compile(r"/settings/tokens(\?.*)?$"), timeout=60000)
    tok = page.evaluate(
        "(() => { const re=/(ghp_[A-Za-z0-9]{36})/;"
        " for (const el of document.querySelectorAll('input,textarea')) {"
        "   const m=(el.value||'').match(re); if (m) return m[1]; }"
        " const m=(document.body.innerText||'').match(re); return m?m[1]:null; })()")
    if not tok:
        page.screenshot(path="fail-token.png")
        sys.exit(f"minted '{note}' but could not read it - REVOKE it at /settings/tokens")
    return tok


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    cfg, out, prefix = sys.argv[1:4]
    seen = {}
    for spec in read_baits(cfg, out, prefix):
        repo = spec["repo"]
        log(f"---- {repo} ----")
        with sync_playwright() as pw:
            ctx = pw.chromium.launch_persistent_context(spec["profile"], headless=False)
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            page.set_default_timeout(15000)
            login = wait_for_login(page, seen)
            seen[login] = repo
            log(f"  provisioning as {login}")
            make_repo(page, login, spec["repo"])
            add_deploy_key(page, login, spec)
            token = mint_token(page) if spec["pat"] or spec["key"] else ""
            ctx.close()
        if token:
            print(f"{repo}\t{token}\t{login}" + ("" if spec["pat"] else "\tdeploy-only"), flush=True)

main()
