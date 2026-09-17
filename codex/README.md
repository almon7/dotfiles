# Codex settings and the DeepSeek launcher

This component checks Codex's own settings and adds a DeepSeek launcher. It does not install Codex itself.

Install the configuration with:

```sh
./install.sh codex
```

Use `codex` normally, and `codex-ds` for DeepSeek. `codex-ds` exports the DeepSeek key only for the Codex process it starts, so exiting that session is all switching back requires. Arguments are forwarded unchanged, for example `codex-ds --continue` or `codex-ds resume`.

## DeepSeek API key

The API key is deliberately outside this repository. Save only the key, with no `export` or quotes, at `~/.config/codex/deepseek-api-key`:

```sh
mkdir -p ~/.config/codex
chmod 700 ~/.config/codex
read -rsp 'DeepSeek API key: ' key; printf '\n'
(umask 077; printf '%s\n' "$key" > ~/.config/codex/deepseek-api-key)
chmod 600 ~/.config/codex/deepseek-api-key
unset key
```

`codex-ds` reports a missing or empty key file rather than starting a session without one.

## How the switch works

`codex-ds` runs `codex --profile deepseek`, which layers [`deepseek.config.toml`](deepseek.config.toml) over `~/.codex/config.toml` instead of replacing it. Trust levels, plugins, skills and the `[tui]` table are untouched, and the DeepSeek settings exist only for that one command. The key reaches Codex through the provider's `env_key`, so it is never written into a config file. It does live in the session's environment, and every command, subagent, plugin and MCP server that session starts inherits it — treat a shared transcript as disclosure and rotate the key if it leaks.

Two of the files here are linked into `~/.codex`, which is unusual: [`codex/config.toml`](config.toml) deliberately is **not**, because Codex writes its own settings there and a link would hand it this repository. The profile and the catalog are only ever read, which is what makes them safe to link. Codex writes to the user config, never to a profile.

A missing profile is not an error to Codex — it layers nothing and the session quietly runs the default configuration against OpenAI. `codex-ds` checks for the profile itself, because that failure would otherwise be silent.

## Model catalog

[`deepseek-models.json`](deepseek-models.json) is DeepSeek's own model catalog, vendored verbatim from the `CODEX_MODELS_JSON` heredoc in the setup script at `https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh`. Codex gives a session the instructions its model's catalog entry carries, so a catalog holding no entry for the selected model costs that session Codex's own system prompt: it receives skills, permissions and `AGENTS.md`, and nothing that says how to behave as Codex. A catalog *file* that is missing is the louder failure, because the profile names the path — Codex then refuses to start with `Error: No such file or directory (os error 2)`.

The catalog replaces Codex's built-in model list rather than adding to it: `codex debug models` reports eleven models normally and the two DeepSeek entries under this profile, so `--model gpt-5.6-sol` is not available inside a `codex-ds` session.

To refresh it, download that script and take the body of the heredoc. The catalog carries `base_instructions` and `model_messages.instructions_template`, which Codex treats as alternatives; DeepSeek ships both, byte-identical, and `python3 codex/test_codex.py` fails if they drift apart.

## Things worth knowing

- The model name must match the catalog exactly. `claude-ds` uses `deepseek-flash[1m]`, but that suffix means nothing to Codex — a slug of `deepseek-flash[1m]` matches no catalog entry and silently costs the session its system prompt.
- `--profile` applies only to runtime commands (`codex`, `exec`, `review`, `resume`, `fork`, `sandbox` and a few others). `codex-ds doctor` and `codex-ds debug models` therefore fail; run those as plain `codex`. `codex-ds --version` does work, because the flag never reaches the config loader.
- `codex-ds` refuses to run when `CODEX_HOME` is set to anything but `~/.codex`. Codex would resolve the profile there while the profile's catalog path cannot follow it, so the launcher stops rather than layering nothing.
- The profile also disables `web_search` and pins `model_reasoning_effort = "high"`, both stricter than a plain `codex` session. `claude-ds` pins `max` for the same model pair, so the two launchers do not agree.
- The profile sets `forced_login_method = "api"`, so surfaces that depend on the ChatGPT login refuse under `codex-ds`. This is what keeps a DeepSeek session from borrowing the stored account.
- `~/.codex/config.toml` sets `model_context_window` and `model_auto_compact_token_limit`, and layering puts them under the profile, so they apply to DeepSeek sessions too and override the catalog's 1,048,576-token window. They are compatible values, so this is left alone rather than pinned twice.

Run the offline regression tests with `python3 codex/test_codex.py`.
