# go-test-runner.nvim

A Neovim plugin for running Go tests directly from the editor using TreeSitter for accurate function detection.

## Features

- Run the test function at the cursor position
- Run all test functions in the current file
- Run all tests in the entire package

All tests execute in a split terminal showing the command and output.

## Requirements

- Neovim with Lua support
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with the Go grammar installed
- Go installed at `/usr/bin/go`

## Installation

### lazy.nvim

```lua
{
    'sukhjit/go-test-runner.nvim',
    ft = 'go',
    config = function()
        require('go-test-runner').setup()
    end
}
```

### packer.nvim

```lua
use {
    'sukhjit/go-test-runner.nvim',
    ft = 'go',
    config = function()
        require('go-test-runner').setup()
    end
}
```

## Usage

Open a Go test file and use the following keymaps:

| Keymap | Action |
|--------|--------|
| `<leader>tr` | Run test function at cursor |
| `<leader>tf` | Run all tests in current file |
| `<leader>tp` | Run all tests in current package |

## Configuration

```lua
require('go-test-runner').setup({
    function_test_cmd = "<leader>tr",  -- keymap for function test
    file_test_cmd     = "<leader>tf",  -- keymap for file test
    package_test_cmd  = "<leader>tp",  -- keymap for package test
})
```

## How It Works

The plugin uses TreeSitter to parse the Go syntax tree:

- **Function test** — walks the tree from the cursor to find the enclosing `function_declaration` or `method_declaration`, then runs `go test -run ^FunctionName$`
- **File test** — collects all top-level functions starting with `Test` and runs them with a combined `-run` pattern
- **Package test** — resolves the import path from `go.mod` and runs `go test` on the full package

The import path is derived automatically by locating `go.mod` and computing the relative path from the module root.
