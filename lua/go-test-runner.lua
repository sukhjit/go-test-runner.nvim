local M = {
  -- Base go test commands; append the run pattern and import path at call time
  go_file_test_path = "/usr/bin/go test -test.fullpath=true -timeout 30s -run '^",
  go_function_test_path = '/usr/bin/go test -test.fullpath=true -timeout 30s -run ^',
  go_package_test_path = '/usr/bin/go test -test.fullpath=true -timeout 30s',

  -- Default keymaps (can be overridden via setup())
  function_test_cmd = '<leader>tr',
  file_test_cmd = '<leader>tf',
  package_test_cmd = '<leader>tp',
}

-- Register buffer-local keymaps. Call this from your plugin config, e.g.
--   require('go-test-runner').setup({ function_test_cmd = '<leader>rt' })
function M.setup(opts)
  opts = opts or {}

  local function_test_cmd = opts.function_test_cmd or M.function_test_cmd
  local file_test_cmd = opts.file_test_cmd or M.file_test_cmd
  local package_test_cmd = opts.package_test_cmd or M.package_test_cmd

  vim.keymap.set('n', function_test_cmd, M.run_function_test, {
    desc = 'Test Go function',
    silent = true,
  })

  vim.keymap.set('n', file_test_cmd, M.run_file_test, {
    desc = 'Test Go file',
    silent = true,
  })

  vim.keymap.set('n', package_test_cmd, M.run_package_test, {
    desc = 'Test Go package',
    silent = true,
  })
end

-- Returns the module name declared in the nearest go.mod, searched upward
-- from the current file's directory. Returns nil if no go.mod is found.
function M.get_go_module_name(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fn.fnamemodify(filepath, ':h')

  local gomod = vim.fn.findfile('go.mod', dir .. ';')
  if gomod == '' then
    return nil
  end

  for line in io.lines(vim.fn.fnamemodify(gomod, ':p')) do
    local module = line:match '^module%s+(%S+)'
    if module then
      return module
    end
  end
end

-- Returns the relative package path from the module root to the current
-- file's directory (e.g. "internal/foo"). Returns "" when the file sits
-- directly in the module root, or nil if no go.mod is found.
function M.get_go_package_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fn.fnamemodify(filepath, ':h')

  local gomod = vim.fn.findfile('go.mod', dir .. ';')
  if gomod == '' then
    return nil
  end

  local mod_dir = vim.fn.fnamemodify(vim.fn.fnamemodify(gomod, ':p'), ':h')
  local abs_dir = vim.fn.fnamemodify(dir, ':p'):gsub('/$', '')
  mod_dir = mod_dir:gsub('/$', '')

  if abs_dir == mod_dir then
    return ''
  end

  -- Strip the module root prefix to get the relative path
  local rel = abs_dir:sub(#mod_dir + 2)
  return rel
end

-- Walks the TreeSitter tree upward from the cursor to find the enclosing
-- function or method declaration. Returns the function name, or nil if the
-- cursor is not inside any function.
function M.get_function_name_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- TreeSitter uses 0-indexed rows
  local col = cursor[2]

  local node = vim.treesitter.get_node { bufnr = bufnr, pos = { row, col } }

  while node do
    if node:type() == 'function_declaration' or node:type() == 'method_declaration' then
      local name_node = node:field('name')[1]
      if name_node then
        return vim.treesitter.get_node_text(name_node, bufnr)
      end
    end
    node = node:parent()
  end

  return nil
end

-- Returns the test case name at the cursor position, or nil if none is found.
--
-- Two patterns are recognised:
--
-- 1. Table-driven tests — cursor is inside a struct literal entry that has a
--    "name" field. The expected node hierarchy is:
--      short_var_declaration
--        expression_list
--          composite_literal
--            literal_value          <- outer slice literal
--              literal_element
--                literal_value      <- one struct entry, e.g. {name: "foo", ...}
--                  literal_element
--                    keyed_element  <- name: "foo"
--
-- 2. t.Run calls — cursor is inside a t.Run("name", ...) call expression.
--
-- Spaces in the returned name are replaced with underscores to match Go's
-- sub-test naming convention.
function M.get_test_case_name_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local node = vim.treesitter.get_node { bufnr = bufnr, pos = { row, col } }

  while node do
    local node_type = node:type()

    -- Pattern 1: table-driven test struct entry
    if node_type == 'literal_value' then
      local par1 = node:parent()
      local par2 = par1 and par1:parent()
      local par3 = par2 and par2:parent()
      local par4 = par3 and par3:parent()
      local par5 = par4 and par4:parent()

      if
        par1
        and par1:type() == 'literal_element'
        and par2
        and par2:type() == 'literal_value'
        and par3
        and par3:type() == 'composite_literal'
        and par4
        and par4:type() == 'expression_list'
        and par5
        and par5:type() == 'short_var_declaration'
      then
        -- child(0) = '{', child(1) = first literal_element (keyed_element), child(2) = ':'  value
        local child_1 = node:child(1)
        if child_1 then
          local key_node = child_1:child(0)
          local val_node = child_1:child(2)
          if key_node and val_node and vim.treesitter.get_node_text(key_node, bufnr) == 'name' then
            local name = vim.treesitter.get_node_text(val_node, bufnr)
            return name:sub(2, -2):gsub(' ', '_') -- strip quotes
          end
        end
      end
    end

    -- Stop walking once we leave the enclosing test function
    if node_type == 'function_declaration' or node_type == 'method_declaration' then
      break
    end

    -- Pattern 2: t.Run("name", func(t *testing.T) { ... })
    if node_type == 'call_expression' then
      local func_node = node:field('function')[1]
      if func_node and func_node:type() == 'selector_expression' then
        local field_node = func_node:field('field')[1]
        if field_node and vim.treesitter.get_node_text(field_node, bufnr) == 'Run' then
          local args_node = node:field('arguments')[1]
          if args_node then
            -- argument_list layout: '(' [arg, ',', arg, ...] ')'
            -- child(0) = '(', child(1) = first argument (the sub-test name)
            local first_arg = args_node:child(1)
            if first_arg and (first_arg:type() == 'interpreted_string_literal' or first_arg:type() == 'raw_string_literal') then
              local name_with_quotes = vim.treesitter.get_node_text(first_arg, bufnr)
              return name_with_quotes:sub(2, -2):gsub(' ', '_') -- strip quotes
            end
          end
        end
      end
    end

    node = node:parent()
  end

  return nil
end

-- Appends non-empty lines from data to buf, scheduled on the main loop so it
-- is safe to call from a libuv callback (stdout/stderr handler).
local function schedule_output(buf, data)
  if data then
    vim.schedule(function()
      for _, line in ipairs(vim.split(data, '\n')) do
        if line ~= '' then
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
        end
      end
    end)
  end
end

-- Schedules automatic window closure 3 seconds after a successful command exit.
-- Does nothing when the command exits with a non-zero code so the output stays
-- visible for inspection.
local function schedule_exit(win, result)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    if result.code ~= 0 then
      -- command failed
      return
    end

    -- close window after 3 seconds
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, 3000)
  end)
end

-- Opens a centred floating terminal window, writes the command being run, and
-- streams its stdout/stderr into the buffer in real time. Press 'q' to close
-- the window manually; it also closes automatically on success (see
-- schedule_exit).
function M.open(cmd, test_type)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Running ' .. test_type,
    title_pos = 'center',
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Running: ' .. cmd, '' })

  local parts = vim.split(cmd, ' ')
  vim.system(parts, {
    stdout = function(_, data)
      schedule_output(buf, data)
    end,
    stderr = function(_, data)
      schedule_output(buf, data)
    end,
  }, function(result)
    schedule_exit(win, result)
  end)

  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, noremap = true })
end

-- Runs all tests in the package that contains the current file.
function M.run_package_test()
  local bufnr = vim.api.nvim_get_current_buf()

  local module_name = M.get_go_module_name(bufnr)
  local pkg_path = M.get_go_package_path(bufnr)
  local import_path = pkg_path ~= '' and (module_name .. '/' .. pkg_path) or module_name

  local cmd = M.go_package_test_path .. ' ' .. import_path

  M.open(cmd, 'Package')
end

-- Runs all Test* functions in the current file by collecting their names via
-- TreeSitter and building a combined -run pattern.
function M.run_file_test()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr)

  local query = vim.treesitter.query.parse(parser:lang(), '(function_declaration) @name')

  local tree = parser:parse()
  local root = tree[1]:root()

  -- Collect every top-level function whose name starts with "Test"
  local funcs = {}
  for _, node in query:iter_captures(root, bufnr) do
    if node:type() == 'function_declaration' then
      local name_node = node:field('name')[1]
      if name_node then
        local func_name = vim.treesitter.get_node_text(name_node, bufnr)
        if func_name:match '^Test' then
          table.insert(funcs, func_name)
        end
      end
    end
  end

  if #funcs == 0 then
    vim.notify 'No test functions found'
    return
  end

  -- Build: go test -run '^(TestFoo|TestBar)$' <import_path>
  local funcs_string = table.concat(funcs, '|')

  local module_name = M.get_go_module_name(bufnr)
  local pkg_path = M.get_go_package_path(bufnr)
  local import_path = pkg_path ~= '' and (module_name .. '/' .. pkg_path) or module_name

  local cmd = M.go_file_test_path .. '(' .. funcs_string .. ")$' " .. import_path

  M.open(cmd, 'File')
end

-- Runs the test function (and optionally a specific sub-test) at the cursor.
-- If the cursor is inside a table-driven test entry or a t.Run call, the
-- sub-test name is appended to produce a pattern like ^TestFoo/my_case$.
function M.run_function_test()
  local bufnr = vim.api.nvim_get_current_buf()

  local func_name = M.get_function_name_at_cursor(bufnr)
  if not func_name then
    vim.notify 'No function found'
    return
  end

  if not func_name:match '^Test' then
    vim.notify 'Not a test function'
    return
  end

  local test_case_name = M.get_test_case_name_at_cursor(bufnr)

  local module_name = M.get_go_module_name(bufnr)
  local pkg_path = M.get_go_package_path(bufnr)
  local import_path = pkg_path ~= '' and (module_name .. '/' .. pkg_path) or module_name

  -- Append sub-test name when the cursor is inside a specific test case
  local run_pattern = func_name
  local test_type = 'Function'
  if test_case_name then
    run_pattern = func_name .. '/' .. test_case_name
    test_type = 'Test Case'
  end

  local cmd = M.go_function_test_path .. run_pattern .. '$ ' .. import_path

  M.open(cmd, test_type)
end

return M
