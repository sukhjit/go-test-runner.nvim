# go-test-runner.nvim

A Neovim plugin for running Go tests directly from the editor using TreeSitter for accurate function and test case detection.

## Features

- Run the test function at the cursor position
- Run a specific sub-test (table-driven or `t.Run`) at the cursor position
- Run all test functions in the current file
- Run all tests in the entire package

Tests execute in a floating terminal window. The window closes automatically 3 seconds after a successful run.

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

| Keymap       | Action                                    |
| ------------ | ----------------------------------------- |
| `<leader>tr` | Run test function (or sub-test) at cursor |
| `<leader>tf` | Run all tests in current file             |
| `<leader>tp` | Run all tests in current package          |
| `q`          | Close the floating output window          |

### Sub-test detection

When the cursor is inside a specific test case, `<leader>tr` narrows the run to that case using the `-run ^TestFunc/case_name$` pattern.

Two patterns are recognised:

**Table-driven tests** — cursor anywhere inside a struct entry with a `name` field:

```go
tests := []struct {
    name  string
    input int
}{
    {name: "valid input", input: 1},  // <-- cursor here runs TestFoo/valid_input
    {name: "empty input", input: 0},
}
```

**`t.Run` calls** — cursor inside the body of a named sub-test:

```go
t.Run("my case", func(t *testing.T) {
    // <-- cursor here runs TestFoo/my_case
})
```

If the cursor is not inside a recognised test case, the whole test function is run.

## Configuration

```lua
require('go-test-runner').setup({
    function_test_cmd = '<leader>tr',  -- keymap for function/sub-test
    file_test_cmd     = '<leader>tf',  -- keymap for file test
    package_test_cmd  = '<leader>tp',  -- keymap for package test
})
```

## How It Works

The plugin uses TreeSitter to parse the Go syntax tree:

- **Function test** — walks the tree upward from the cursor to find the enclosing `function_declaration` or `method_declaration`, then checks for a sub-test name before running
- **Sub-test (table-driven)** — detects a `literal_value` struct entry whose first `keyed_element` has `name` as its key and extracts the string value
- **Sub-test (`t.Run`)** — detects a `call_expression` where the selector field is `Run` and extracts the first string argument
- **File test** — collects all top-level `Test*` functions via TreeSitter and combines them into a single `-run '^(TestA|TestB)$'` pattern
- **Package test** — resolves the full import path from `go.mod` and runs `go test` on the whole package
