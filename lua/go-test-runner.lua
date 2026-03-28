local M = {
  go_file_test_path = "/usr/bin/go test -test.fullpath=true -timeout 30s -run '^",
  go_function_test_path = '/usr/bin/go test -test.fullpath=true -timeout 30s -run ^',
  go_package_test_path = '/usr/bin/go test -test.fullpath=true -timeout 30s',

  function_test_cmd = '<leader>tr',
  file_test_cmd = '<leader>tf',
  package_test_cmd = '<leader>tp',
}

function M.setup(opts)
  opts = opts or {}

  local function_test_cmd = opts.function_test_cmd or M.function_test_cmd
  local file_test_cmd = opts.file_test_cmd or M.file_test_cmd
  local package_test_cmd = opts.package_test_cmd or M.package_test_cmd

  vim.keymap.set('n', function_test_cmd, M.run_function_test, {
    desc = 'Test Go function',
    buffer = true,
    silent = true,
  })

  vim.keymap.set('n', file_test_cmd, M.run_file_test, {
    desc = 'Test Go file',
    buffer = true,
    silent = true,
  })

  vim.keymap.set('n', package_test_cmd, M.run_package_test, {
    desc = 'Test Go package',
    buffer = true,
    silent = true,
  })
end

function M.get_go_package_name(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr, 'go')
  local tree = parser:parse()
  local root = tree[1]:root()

  local query = vim.treesitter.query.parse('go', '(package_clause (package_identifier) @name)')
  for _, node in query:iter_captures(root, bufnr) do
    return vim.treesitter.get_node_text(node, bufnr)
  end
end

-- get golang module name by finding and parsing go.mod from the current file's directory
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

  local rel = abs_dir:sub(#mod_dir + 2)
  return rel
end

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

-- assume that test cases inside a test table are in the form of
-- for _, tc := range []struct{
--   name string
--   want string
-- }{
--   {name: "test1", want: "a"},
--   {name: "test2", want: "b"},
-- } {
--   t.Run(tc.name, func(t *testing.T) { ...})
-- }
function M.get_test_case_name_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local node = vim.treesitter.get_node { bufnr = bufnr, pos = { row, col } }

  while node do
    local node_type = node:type()

    local par1 = node:parent()
    local par2 = par1 and par1:parent()
    local par3 = par2 and par2:parent()
    local par4 = par3 and par3:parent()
    local par5 = par4 and par4:parent()

    if
      node_type == 'literal_value'
      and par1:type() == 'literal_element'
      and par2:type() == 'literal_value'
      and par3:type() == 'composite_literal'
      and par4:type() == 'expression_list'
      and par5:type() == 'short_var_declaration'
    then
      local child_1 = node:child(1)

      local child_1_name = vim.treesitter.get_node_text(child_1:child(0), bufnr)
      if child_1_name == 'name' then
        return vim.treesitter.get_node_text(child_1:child(2), bufnr)
      end
    end

    -- Stop searching once we exit the enclosing test function
    if node_type == 'function_declaration' or node_type == 'method_declaration' then
      break
    end

    if node_type == 'call_expression' then
      local func_node = node:field('function')[1]
      if func_node and func_node:type() == 'selector_expression' then
        local field_node = func_node:field('field')[1]
        if field_node and vim.treesitter.get_node_text(field_node, bufnr) == 'Run' then
          local args_node = node:field('arguments')[1]
          if args_node then
            -- child(0) is '(', child(1) is first argument
            local first_arg = args_node:child(1)
            if first_arg and (first_arg:type() == 'interpreted_string_literal' or first_arg:type() == 'raw_string_literal') then
              local name_with_quotes = vim.treesitter.get_node_text(first_arg, bufnr)
              -- Strip surrounding quotes and replace spaces with underscores (Go test behaviour)
              return name_with_quotes:sub(2, -2):gsub(' ', '_')
            end
          end
        end
      end
    end

    node = node:parent()
  end

  return nil
end

function M.print_and_run_cmd(cmd)
  vim.cmd('split | terminal sh -c ' .. vim.fn.shellescape('echo Running: ' .. cmd .. ' && printf "\\n" && exec ' .. cmd))
end

function M.run_package_test()
  local bufnr = vim.api.nvim_get_current_buf()

  local module_name = M.get_go_module_name(bufnr)
  local pkg_path = M.get_go_package_path(bufnr)
  local import_path = pkg_path ~= '' and (module_name .. '/' .. pkg_path) or module_name

  local cmd = M.go_package_test_path .. ' ' .. import_path

  M.print_and_run_cmd(cmd)
end

function M.run_file_test()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr)

  local query_string = '(function_declaration) @name'

  local query = vim.treesitter.query.parse(parser:lang(), query_string)

  local tree = parser:parse()
  local root = tree[1]:root()

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

  local funcs_string = table.concat(funcs, '|')

  local module_name = M.get_go_module_name(bufnr)
  local pkg_path = M.get_go_package_path(bufnr)
  local import_path = pkg_path ~= '' and (module_name .. '/' .. pkg_path) or module_name

  local cmd = M.go_file_test_path .. '(' .. funcs_string .. ")$' " .. import_path

  M.print_and_run_cmd(cmd)
end

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

  local run_pattern = func_name
  if test_case_name then
    run_pattern = func_name .. '/' .. test_case_name
  end

  local cmd = M.go_function_test_path .. run_pattern .. '$ ' .. import_path

  M.print_and_run_cmd(cmd)
end

return M
