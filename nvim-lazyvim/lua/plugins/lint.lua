-- nvim-lint runs `markdownlint-cli2 -` over stdin, so the linter resolves its
-- config from the cwd (never $HOME). To disable MD013 (line length) everywhere,
-- point it at the config shipped in this repo via --config. The file keeps a
-- supported *.markdownlint-cli2.jsonc name so --config accepts it.
local md_config = vim.fn.stdpath("config") .. "/.markdownlint-cli2.jsonc"

return {
  "mfussenegger/nvim-lint",
  opts = {
    -- LazyVim deep-merges this into the linter definition (args = { "-" }),
    -- yielding: markdownlint-cli2 --config <file> -
    linters = {
      ["markdownlint-cli2"] = {
        args = { "--config", md_config, "-" },
      },
    },
  },
}
