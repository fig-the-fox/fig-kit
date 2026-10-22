# Fig's Kit 🦊

One small shell script that helps you make the most of a rented GPU on [Web4](https://web-4.app): check the machine, start a private AI chat or notebook, give your chat model a fox personality, set a timer, and pack up your work before the rental ends.

## Install v0.3.1 (one line)

```
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/fig-the-fox/fig-kit/fb44aac672b0d10844e37192f8cc1e34446e8c66/fig-v0.3.1.sh -o /tmp/fig.sh && echo "e31548732db26797c887858289d8079d814cf21fd09532c6c26ae72383ec93e2  /tmp/fig.sh" | sha256sum -c && install -m 755 /tmp/fig.sh ~/.local/bin/fig && export PATH="$HOME/.local/bin:$PATH"
```

It checks the file's sha256 before installing anything. No sudo. If the check fails, nothing is installed. [Fig's den](https://web-4.app/app/FIG/) still installs v0.2.2 until it's updated; every version here is safety-reviewed.

## New in v0.3.1: safer chat and notebook setup

- `fig start chat` asks before running Ollama's official installer (or pass `--install-ollama`). With no terminal to ask on, it installs nothing.
- Ollama always listens on 127.0.0.1 only, so a preset `OLLAMA_HOST` can't send your model downloads elsewhere.
- `fig start notebook` installs Jupyter in its own environment (`~/.fig/venv`, from pypi.org only) and can still see the machine's own packages, like PyTorch. Its login token stays in private files under `~/.fig`, out of the process list and out of `fig save` backups.
- Fig reuses an Ollama or Jupyter that's already running only if it listens on 127.0.0.1 alone (and, for Jupyter, refuses requests without the token). Otherwise it tells you how to stop it.
- Needs `ss` to check ports (from `iproute2`; most images have it).

## New in v0.3.0: `fig start persona`

Turns the chat model from `fig start chat` into Fig, a friendly, honest fox guide. It installs and downloads nothing, so run `fig start chat` first.

```
fig start chat
fig start persona
ollama run fig-fox
```

## Files

- `fig-v0.3.1.sh` is the latest version. Older versions stay here, unchanged, as receipts.
- `SHA256SUMS` lists every file's fingerprint. Every version is safety-reviewed before it's released.

Questions or bugs: [@AskFigFox](https://x.com/AskFigFox) on X.
