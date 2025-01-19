### pair.nvim

Pair programming plugin for neovim written in Lua using Vim client-server
communication.

> [!WARNING]
> This plugin demonstrates collaborative programming in neovim as a concept. I
> plan to create a more reliable version at some point in the future. Any
> contributions are welcome.

### Features

**pair.nvim** starts a peer-to-peer "server" (`:PairServer`) and "client"
(`:PairClient`) for the current buffer.

- [x] Sync changed text in buffer
- [x] Display changed cursor position in remote
- [ ] Display visual selection in remote

requests are discarded if the buffer (`require("pair").bufnr`) buffer is
removed from the window. Sharing can be completely stopped with `:PairStop` and
then resumed from any buffer.

### Installation

Using [lazy.nvim]

```lua
return {
    "skeletony007/pair.nvim",

    config = true,
}
```

### Setup

`local pair = require("pair")`

Defaults

```lua
pair.setup({
    -- named pipe or socket address (see `:help remote`)
    server_addr = os.getenv("HOME") .. "/.cache/nvim/pair-server.pipe",
    client_addr = os.getenv("HOME") .. "/.cache/nvim/pair-client.pipe",

    virtual_cursor_blame_prefix = " remote ",
})
```

### Highlight Groups

`PairVirtualCursor` Used for the virtual cursor.

`PairVirtualBlame` Used for the virtual cursor blame.

[lazy.nvim]: https://github.com/folke/lazy.nvim
