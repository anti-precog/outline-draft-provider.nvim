# An outline.nvim external provider for draft

Port [draft](https://github.com/anti-precog/tree-sitter-draft) support of [outline.nvim](https://github.com/epheien/outline-treesitter-provider.nvim).

A Lazy.nvim example to use this provider.
``` lua
{
  'hedyhli/outline.nvim',
  config = function()
    require('outline').setup({
      providers = {
        priority = { 'lsp', 'coc', 'markdown', 'norg', 'draft' },
      },
    })
  end,
  event = "VeryLazy",
  dependencies = {
    'anti-precog/outline-draft-provider.nvim'
  }
}
```

