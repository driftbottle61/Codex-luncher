# codex-provider

A small launcher for running Codex with multiple API providers and models.
Each provider/model gets an isolated `CODEX_HOME` and a persistent tmux session,
so multiple SSH clients attach to the same Codex process instead of creating
competing writers.

## Install

Install Codex first (`npm install -g @openai/codex`). The installer also
installs tmux automatically when it is missing.

One-shot install:

```bash
curl -fsSL https://raw.githubusercontent.com/driftbottle61/Codex-luncher/main/install.sh | sudo bash
```

Or clone this repository and run locally:

```bash
sudo ./install.sh
```

The launcher is installed as `/usr/local/bin/codex-provider`.

When run from an interactive terminal the installer drops you straight into
the session menu when it finishes (`codex-provider recent`, which shows the
resume picker when sessions exist and the provider setup otherwise); press `q`
to leave the menu back to the shell. On non-interactive installs it simply
finishes and prints the SSH note.

## Usage

```bash
codex-provider          # interactive provider/model/session menu
codex-provider setup    # add a provider (same name = overwrite, no prompt)
codex-provider edit NAME                       # edit a provider in place
codex-provider edit NAME --set model=other     # non-interactive single change
codex-provider edit NAME --set base_url=https://x/v1 --refresh
codex-provider groups NAME                    # list the relay's groups (new-api /api/pricing)
codex-provider groups NAME --group AZ         # the models a group is entitled to
codex-provider probe NAME                     # test every candidate with a real minimal request
codex-provider probe NAME --apply             # ...then rebuild the catalog with only the usable ones
codex-provider probe NAME --group AZ --no-verify --apply   # just take the group catalog, no requests
codex-provider probe NAME --model gpt-5.6-luna --keep gpt-image-2 --yes --apply
codex-provider repair NAME                    # drop undecryptable encrypted reasoning from history
codex-provider edit NAME --set strip_reasoning=1   # ...or do it automatically on every entry
                                              # (after an api-key/group change old sessions fail with
                                              #  invalid_encrypted_content; originals are backed up)
codex-provider list     # list configured providers
codex-provider go       # auto-resume the single most recent session
codex-provider recent   # pick one of the 10 most recent sessions
codex-provider resume tokenhub --last
codex-provider update tokenhub           # refresh that provider's model catalog
codex-provider update all --replace      # refresh all, drop local-only entries
                                         # (backs the old catalogs up and lists what it drops)
codex-provider upgrade                   # check + upgrade codex (official standalone installer)
codex-provider upgrade --check           # only report; change nothing
codex-provider upgrade --launcher        # upgrade codex-provider itself from GitHub releases
```

Provider data is stored under `${CODEX_PROVIDER_ROOT:-$HOME/.codex-providers}`.
API keys are saved in mode `600` and exported only when a provider is started.
Do not commit that directory or any API key files.

Relays of the new-api family keep an authoritative per-group catalog at
`/api/pricing` (the same data the web UI's pricing page uses): every model
carries `enable_groups`. `codex-provider groups NAME` prints the groups and the
model count, `--group G` prints that group's models. `probe` uses it as the
candidate source: it derives the pricing URL from `base_url`, auto-detects which
group the token belongs to (one deliberately impossible request — new-api
answers `No available channel for model X under group AZ`, which is free because
it always fails) and probes that group's models only. `--group G` overrides the
detection, `--wide` falls back to the old "local catalog plus upstream
`/models`" union, and `--model M` probes exactly what you name.

`/v1/models` on the other hand is not trustworthy in either direction: it lists
models with no channel behind them and omits models that do work. `probe` sends
one minimal request (`input=hi`, `max_output_tokens=16`) per candidate, because
being in the group catalog only means "entitled to", not "currently has a
channel" — the difference is a 503 `No available channel` at call time. A model
counts as usable only if the response is HTTP 200 *and* `status == completed`
(chat providers need `choices`), so "listed but 503 / no channel" and "200 but
the stream never completes" both show up as unusable. It costs a tiny amount of
credit per model, so it asks for confirmation unless `--yes`; `--jobs N`
(default 4) sets the parallelism and `--timeout S` (default 60) the per-request
limit.

By default `probe` only reports. With `--apply` it rewrites `model-catalog.json`
to the usable models, keeping the original catalog order, backing the old file
up as `model-catalog.json.bak-before-probe-<YYYYmmdd-HHMMSS>`, and refusing to
write an empty catalog. `--no-verify` skips the requests altogether and applies
the candidate list as-is — the way to write a group's whole catalog without
spending anything, at the cost of keeping models that currently have no channel. `--keep M` forces a model to stay even if it failed —
handy for image models, which cannot answer a `/responses` probe. Models the
probe cannot judge this way are simply reported, never auto-added.

`update NAME` merges by default: entries already in the local catalog keep their
place and the upstream list is appended, so hand-picked models survive a refresh.
`--replace` is the destructive one — use `codex-provider update NAME` instead when
the upstream list is incomplete (some relays do not return every model a key can
actually call, e.g. `gpt-5.6-luna` on openmove). It now copies the previous
catalog to `model-catalog.json.bak-before-replace-<YYYYmmdd-HHMMSS>` and lists the
entries it drops, so a mistake is recoverable.

A provider may pin a relay `group` (`group=AZ` in `provider.conf`, asked for by
`setup`, editable with `codex-provider edit NAME` / `--set group=AZ`, shown by
`list`). When a group is pinned — or auto-detected — `update NAME`, the menu's
refresh and the pre-session refresh all take the model list from that group's
catalog in `/api/pricing` instead of `/v1/models`, so models belonging to other
groups never leak into the picker. Without a group, and if `/api/pricing` is
missing, it falls back to `/v1/models` and says so. Note the merge rule still
applies: a refresh keeps local entries and appends the group's, so running
`probe --apply` to narrow the catalog to what currently works is undone by the
next refresh (the group catalog is the entitlement list, not the live one).

`edit` shows the current value as the prompt default and keeps it if you just
press Enter, so you can change one field without retyping the rest; the API key
prompt is hidden and an empty answer leaves the saved key alone. Editable
fields are `label`, `base_url`, `group`, `model`, `wire_api`, `key_env` and
`key`
(`--set key=...` rotates the key). The provider `name` is its directory and is
not editable. Every change first copies `provider.conf` to
`provider.conf.bak-before-edit-<YYYYmmdd-HHMMSS>` (and `api-key` likewise when
the key changes), then prints a unified diff. Values that contain spaces are
written quoted, since `provider.conf` is sourced by bash. `--refresh` also
refreshes the model catalog afterwards; a failed refresh only warns.

The interactive launcher uses tmux sessions named like:

```text
codex-tokenhub-hy3
codex-tokenhub-kimi-k3
```

Selecting a model always attaches to that model's session. Detach without
stopping Codex with `Ctrl-b`, then `d`.

## Upgrading codex

Codex only shows its own `Update available` banner when it recognises its
installation as a *managed* one (standalone / npm / brew ...), and that
detection keys off `CODEX_HOME` being the home the install lives in. This
launcher points `CODEX_HOME` at a per-session directory (that is what keeps
providers isolated), so codex sees itself as "other" and never offers the
update - and picking `Update now` if it ever does appear just tears the session
down without installing anything.

So the launcher does the check itself: the menu prints a hint when a newer
codex (or codex-provider) is out, and `codex-provider upgrade` runs the same
official standalone installer codex's `Update now` would have run - but outside
the TUI, so the running session is not killed. The check happens at most once a
day and is cached in `$CODEX_PROVIDER_ROOT/upgrade-check.json`.

At the menu prompt (and at the `recent` picker prompt) you can skip the shell
round-trip: type `u` to upgrade codex, or `U` to upgrade codex-provider. Both
still print the exact command and ask for confirmation before running anything,
and a failed check just prints an error and returns you to the menu.

## Retries (rate limits on shared relay capacity)

Relays are usually backed by shared quota - openmove's `AZ` group, for example,
is Azure `japaneast` and occasionally answers

```
rate limit exceeded: Your requests to gpt-5.6-luna for gpt-5.6-luna in japaneast
have exceeded token rate limit
```

for a minute or two before recovering on its own. Generated session configs
therefore set `request_max_retries = 8` and `stream_max_retries = 8` (codex
honours the upstream `Retry-After`), so a short quota window is ridden out
instead of surfacing as an error. Verified in practice:

```
ERROR: Reconnecting... 1/8
codex
ok
```

Nothing else changes: a real outage still fails, just after more attempts.

## Repairing a session that fails with `invalid_encrypted_content`

Relays of the new-api family encrypt each reasoning item's `encrypted_content`
per account. Rotate the api-key (or move the token to another group) and the
items recorded under the old account can no longer be decrypted, so every
request that replays that history fails with:

```
invalid_encrypted_content: The encrypted content for item rs_... could not be verified
```

The history itself is fine - those reasoning items are not needed to replay it.
`codex-provider repair NAME` lists how many are affected, and (after the
confirmation prompt, or `--yes`) rewrites each rollout file without them,
leaving every message and tool call untouched. Originals are kept next to the
file as `*.bak-before-repair-<timestamp>`. Narrow it with `--model M`, and
re-run it safely: a second pass reports "nothing to do".

```bash
codex-provider repair openmove                    # count + confirm
codex-provider repair openmove --yes              # non-interactive
codex-provider repair openmove --model gpt-5.6-luna --yes
```

Attaching a tmux session whose credentials were rotated already tells you when
to run this: the launcher prints the hint right after it respawns the pane.

### Doing it automatically: `strip_reasoning=1`

A relay can also hand back a *single* reasoning item nobody can decrypt any
more (seen in practice: one item out of 124 returns 400 while its siblings
return 200). One such item is enough to brick the whole conversation, so
`repair` supports an automatic mode per provider:

```bash
codex-provider edit openmove --set strip_reasoning=1   # enable
codex-provider edit openmove --set strip_reasoning=     # disable
```

With it on, every entry into an existing session strips undecryptable
reasoning items from that session's rollout first and prints
`已摘除 N 处上游解不开的 encrypted reasoning item（历史消息保留）`. Messages,
tool calls and their output are never touched. The first automatic pass keeps a
`*.bak-before-repair-<timestamp>` copy; later passes reuse it instead of piling
up more backups (`repair` itself always writes a fresh, timestamped backup).

Note the trade-off: replayed history loses the reasoning *summaries* of past
turns. Those are cosmetic for the model (they are re-derived), but the resumed
transcript will not show them for old turns.

## In-session /model switching

For custom providers, Codex can show the provider's model catalog in the
in-session `/model` picker. When a provider has a `model-catalog.json`, the
launcher converts it into Codex's internal catalog format and writes
`model_catalog_json` into the session's `config.toml`, so `/model` lists those
models instead of falling back to the bundled ChatGPT models.

The conversion caches Codex's official base instructions once at
`${CODEX_PROVIDER_ROOT:-$HOME/.codex-providers}/base-instructions.md`. If that
download fails, a short fallback instruction is used. Restart the session after
adding a model catalog for `/model` to pick up the new list.

Refreshing a provider's catalog (`codex-provider update NAME`, and the refresh
that runs automatically when you pick a provider in the menu) **merges**: your
existing entries keep their order, upstream models that you do not have are
appended, and anything upstream no longer returns is kept and reported rather
than dropped - so hand-picked or provider-specific models survive a refresh.
Pass `--replace` to force the catalog to exactly the upstream list.

Entering a session - the `recent` picker, `go`, `resume`, `use` and the provider
menu - also refreshes that provider's catalog first, so the in-session `/model`
list is current. It runs once per provider per run, never blocks the session
(if the API or key is bad you just get a warning and the cached catalog is
used), and never writes an empty catalog (Codex refuses to start when
`model_catalog_json` has no models). Set `CODEX_PROVIDER_REFRESH_ON_SESSION=0`
to skip it; the provider menu's own refresh is unaffected by that switch.

## GitHub release

Create an empty GitHub repository, then from this directory:

```bash
git init
git add bin install.sh README.md
git commit -m 'Initial codex-provider launcher'
git branch -M main
git remote add origin git@github.com:YOUR_ACCOUNT/codex-provider.git
git push -u origin main
```

Do not add provider configs, session data, API keys, or Codex auth files.

## SSH session picker menu

`codex-provider recent` lists the 10 most recently active sessions across
**all** providers/models *and legacy Codex homes* (timestamped, newest first,
each with its first message as a hint) and resumes the one you pick:

```bash
codex-provider recent     # pick one of the 10 most recent sessions
codex-provider recent 5   # show the 5 most recent sessions
codex-provider go         # skip the menu, auto-resume the single latest
```

"Recent" means the newest home-local session activity (`history.jsonl`,
`state_5.sqlite`, a non-empty `state_5.sqlite-wal`, or `config.toml`), not just
directory age or a rollout path pointing outside the home, so an idle but
freshly started session cannot shadow your real last conversation. Sessions
whose tmux is still running are attached
directly. Legacy homes are ranked by the same activity clock and merged into
the same list, so the truly newest session is always entry `#1` — even when it
lives in an old plain-Codex home (`~/.codex`) rather than under a managed
provider. `codex-provider go` uses the same merged ranking.

`install.sh` installs this hook automatically. It scans `~/.profile`,
`~/.bash_profile` and `~/.bashrc` (SSH login shells source both), disables any
older auto-enter hook left by a previous Codex setup (plain `codex`,
`exec codex`, or an earlier `codex-provider go`/`recent` hook — each modified
file is backed up first). Auto-run lines are replaced with harmless no-ops
instead of being deleted, so function/if blocks in the rc file stay
syntactically valid; the result is syntax-checked before being kept. The
installer then enables the canonical picker hook in the login rc file.
Re-running the installer is safe: an already-active hook is left as is.

Add this hook to the SSH login shell (`~/.profile` for root) so any SSH client
lands in the session picker:

```bash
if [ -n "$SSH_CONNECTION" ] && [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$CODEX_SKIP" ]; then
    codex-provider recent || true
fi
```

- Detaching with `Ctrl-b d` returns to the login shell (normal admin shell).
- Exiting Codex inside tmux closes the window; the next `recent`/`go` restarts
  a fresh Codex that resumes the same session.
- Re-attaching a *live* tmux session also refreshes credentials: if the saved
  `api-key` no longer matches what that pane was started with, the pane is
  respawned with the current value instead of silently keeping the stale key
  (which surfaces as a confusing upstream `503 No available channel for model
  ...`). Codex history lives on disk, so the respawn resumes the same
  conversation.
- The last menu entry starts a new session through the original
  provider/model picker (`codex-provider menu`).
- First run is self-guiding: when no provider and no session exists yet, the
  picker drops straight into the interactive provider setup (`codex-provider
  setup`) instead of exiting; afterwards it returns to the menu.
- Escape hatch for an admin shell without Codex:
  `ssh -t root@host 'CODEX_SKIP=1 bash -l'`

Legacy Codex homes are detected too: any `$CODEX_HOME` or `~/.codex` outside
the provider root that contains `sessions/*.jsonl` is scanned, and its sessions
appear alongside the managed ones in both `recent` and the interactive menu
(shown as a `=> 恢复 legacy 历史会话 <=` entry). Legacy sessions are resumed
with their own `config.toml` provider/key settings, so they work even if the
provider was never added to `codex-provider`.

## Codex 0.158+ 的后台 app-server（`--no-daemon`）

自 codex 0.158 起，codex 会在 `$CODEX_HOME/app-server-control/` 下建 unix socket 启动后台 app-server。codex-provider 把
`CODEX_HOME` 指向较深的会话目录（`.../providers/<name>/sessions/<model>/<suffix>`），拼接出的 socket 路径会超过 Unix socket
的 SUN_LEN（约 108 字节），导致 `app server did not become ready`、会话一进就退。

因此 codex-provider 在启动 codex 时会加 `--no-daemon`（交互会话直接前台跑，绕过后台 daemon）。这不影响 tmux 交互用法，
只放弃后台 daemon 特性。以后若 codex 的 daemon/目录行为再变，留意这个开关。

注意：`--no-daemon` 是 codex 0.158 才引入的参数，0.158 之前的版本不认识它，会直接报
`unexpected argument '--no-daemon'` 并以非零码退出（表现为「选新建会话后秒退」）。所以 codex-provider 会先探测
`codex --version`，只有 ≥ 0.158 时才追加该参数；旧版 codex 直接照常启动。旧机器想用到新版行为再单独升级 codex 即可。
