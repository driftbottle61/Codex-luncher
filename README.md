# codex-provider

A small launcher for running Codex with multiple API providers and models.
Each provider/model gets an isolated `CODEX_HOME` and a persistent tmux session,
so multiple SSH clients attach to the same Codex process instead of creating
competing writers.

## Install

Install Codex and tmux first, then run from this directory:

```bash
sudo ./install.sh
```

The launcher is installed as `/usr/local/bin/codex-provider`.

## Usage

```bash
codex-provider          # interactive provider/model/session menu
codex-provider setup    # add or update a provider
codex-provider list     # list configured providers
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
