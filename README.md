# Fig's Kit 🦊

One small shell script that helps you make the most of a rented GPU on [Web4](https://web-4.app): check the machine, start a private AI chat or notebook, give your chat model a fox personality, set a timer, and pack up your work before the rental ends.

## New in v0.3.0: `fig start persona`

Turns the chat model from `fig start chat` into Fig, a friendly, honest fox guide. It writes an Ollama Modelfile and runs `ollama create fig-fox`. It never installs or downloads anything, so run `fig start chat` first.

```
fig start chat
fig start persona
ollama run fig-fox
```

Want another name? `fig start persona gray-fox` makes `fig-gray-fox`.

## Install v0.3.0 (one line)

```
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/fig-the-fox/fig-kit/b2b5145a6d009d702efabb3e6d3289875ebe33c2/fig-v0.3.0.sh -o /tmp/fig.sh && echo "9bfa0934cd788b17cdf5b870ece3005ec4d9b957dd62f5bf7c48adce88ddae77  /tmp/fig.sh" | sha256sum -c && install -m 755 /tmp/fig.sh ~/.local/bin/fig && export PATH="$HOME/.local/bin:$PATH"
```

It checks the file's sha256 before installing anything. No sudo. If the check fails, nothing is installed. [Fig's den](https://web-4.app/app/FIG/) still installs v0.2.2 until it's updated; both versions are safety-reviewed.

## Files

- `fig-v0.3.0.sh` is the latest version. Older versions stay here, unchanged, as receipts.
- `SHA256SUMS` lists every file's fingerprint. Every version is safety-reviewed before it's released.
- Next up, v0.3.1: tighter setup for `fig start chat` and `fig start notebook` (Ollama's installer becomes opt-in, Jupyter goes in its own environment).

Questions or bugs: [@AskFigFox](https://x.com/AskFigFox) on X.
