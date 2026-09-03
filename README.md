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

## Usage

```bash
codex-provider          # interactive provider/model/session menu
codex-provider setup    # add or update a provider
codex-provider list     # list configured providers
codex-provider go       # auto-resume the single most recent session
codex-provider recent   # pick one of the 3 most recent sessions
codex-provider resume tokenhub --last
```

Provider data is stored under `${CODEX_PROVIDER_ROOT:-$HOME/.codex-providers}`.
API keys are saved in mode `600` and exported only when a provider is started.
Do not commit that directory or any API key files.

The interactive launcher uses tmux sessions named like:

```text
codex-tokenhub-hy3
codex-tokenhub-kimi-k3
```

Selecting a model always attaches to that model's session. Detach without
stopping Codex with `Ctrl-b`, then `d`.

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

`codex-provider recent` lists the 3 most recently active sessions across
**all** providers/models *and legacy Codex homes* (timestamped, newest first,
each with its first message as a hint) and resumes the one you pick:

```bash
codex-provider recent     # pick one of the 3 most recent sessions
codex-provider recent 5   # show the 5 most recent sessions
codex-provider go         # skip the menu, auto-resume the single latest
```

"Recent" means the newest recorded session activity (rollout file mtime), not
just directory age, so an idle but freshly started session cannot shadow your
real last conversation. Sessions whose tmux is still running are attached
directly. Legacy homes are ranked by the same activity clock and merged into
the same list, so the truly newest session is always entry `#1` — even when it
lives in an old plain-Codex home (`~/.codex`) rather than under a managed
provider. `codex-provider go` uses the same merged ranking.

`install.sh` installs this hook automatically: it detects any older SSH
auto-enter hook left by a previous Codex setup (plain `codex`, `exec codex`, or
an earlier `codex-provider go`/`recent` hook), disables it (the rc file is
backed up first) and installs the canonical picker hook. Only when no hook
existed at all does it leave the rc file untouched and print the snippet for
you to add manually.

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
- The last menu entry starts a new session through the original
  provider/model picker (`codex-provider menu`).
- Escape hatch for an admin shell without Codex:
  `ssh -t root@host 'CODEX_SKIP=1 bash -l'`

Legacy Codex homes are detected too: any `$CODEX_HOME` or `~/.codex` outside
the provider root that contains `sessions/*.jsonl` is scanned, and its sessions
appear alongside the managed ones in both `recent` and the interactive menu
(shown as a `=> 恢复 legacy 历史会话 <=` entry). Legacy sessions are resumed
with their own `config.toml` provider/key settings, so they work even if the
provider was never added to `codex-provider`.
