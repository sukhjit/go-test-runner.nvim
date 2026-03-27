local M = {
	go_file_test_path = "/usr/bin/go test -test.fullpath=true -timeout 30s -run '^",
	go_function_test_path = "/usr/bin/go test -test.fullpath=true -timeout 30s -run ^",
	go_package_test_path = "/usr/bin/go test -test.fullpath=true -timeout 30s",

	function_test_cmd = "<leader>tr",
	file_test_cmd = "<leader>tf",
	package_test_cmd = "<leader>tp",
}

function M.setup(opts)
	opts = opts or {}

	local function_test_cmd = opts.function_test_cmd or M.function_test_cmd
	local file_test_cmd = opts.file_test_cmd or M.file_test_cmd
	local package_test_cmd = opts.package_test_cmd or M.package_test_cmd

	vim.keymap.set("n", function_test_cmd, M.run_function_test, {
		desc = "Test Go function",
		buffer = true,
		silent = true,
	})

	vim.keymap.set("n", file_test_cmd, M.run_file_test, {
		desc = "Test Go file",
		buffer = true,
		silent = true,
	})

	vim.keymap.set("n", package_test_cmd, M.run_package_test, {
		desc = "Test Go package",
		buffer = true,
		silent = true,
	})
end

function M.get_go_package_name(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(bufnr, "go")
	local tree = parser:parse()
	local root = tree[1]:root()

	local query = vim.treesitter.query.parse("go", "(package_clause (package_identifier) @name)")
	for _, node in query:iter_captures(root, bufnr) do
		return vim.treesitter.get_node_text(node, bufnr)
	end
end

-- get golang module name by finding and parsing go.mod from the current file's directory
function M.get_go_module_name(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local dir = vim.fn.fnamemodify(filepath, ":h")

	local gomod = vim.fn.findfile("go.mod", dir .. ";")
	if gomod == "" then
		return nil
	end

	for line in io.lines(vim.fn.fnamemodify(gomod, ":p")) do
		local module = line:match("^module%s+(%S+)")
		if module then
			return module
		end
	end
end

function M.get_go_package_path(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local dir = vim.fn.fnamemodify(filepath, ":h")

	local gomod = vim.fn.findfile("go.mod", dir .. ";")
	if gomod == "" then
		return nil
	end

	local mod_dir = vim.fn.fnamemodify(vim.fn.fnamemodify(gomod, ":p"), ":h")
	local abs_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
	mod_dir = mod_dir:gsub("/$", "")

	if abs_dir == mod_dir then
		return ""
	end

	local rel = abs_dir:sub(#mod_dir + 2)
	return rel
end

function M.get_function_name_at_cursor(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- TreeSitter uses 0-indexed rows
	local col = cursor[2]

	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

	while node do
		if node:type() == "function_declaration" or node:type() == "method_declaration" then
			local name_node = node:field("name")[1]
			if name_node then
				return vim.treesitter.get_node_text(name_node, bufnr)
			end
		end
		node = node:parent()
	end

	return nil
end

function M.print_and_run_cmd(cmd)
	vim.cmd(
		"split | terminal sh -c " .. vim.fn.shellescape("echo Running: " .. cmd .. ' && printf "\\n" && exec ' .. cmd)
	)
end

function M.run_package_test()
	local bufnr = vim.api.nvim_get_current_buf()

	local module_name = M.get_go_module_name(bufnr)
	local pkg_path = M.get_go_package_path(bufnr)
	local import_path = pkg_path ~= "" and (module_name .. "/" .. pkg_path) or module_name

	local cmd = M.go_package_test_path .. " " .. import_path

	M.print_and_run_cmd(cmd)
end

function M.run_file_test()
	local bufnr = vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(bufnr)

	local query_string = "(function_declaration) @name"

	local query = vim.treesitter.query.parse(parser:lang(), query_string)

	local tree = parser:parse()
	local root = tree[1]:root()

	local funcs = {}
	for _, node in query:iter_captures(root, bufnr) do
		if node:type() == "function_declaration" then
			local name_node = node:field("name")[1]
			if name_node then
				local func_name = vim.treesitter.get_node_text(name_node, bufnr)
				if func_name:match("^Test") then
					table.insert(funcs, func_name)
				end
			end
		end
	end

	if #funcs == 0 then
		vim.notify("No test functions found")
		return
	end

	local funcs_string = table.concat(funcs, "|")

	local module_name = M.get_go_module_name(bufnr)
	local pkg_path = M.get_go_package_path(bufnr)
	local import_path = pkg_path ~= "" and (module_name .. "/" .. pkg_path) or module_name

	local cmd = M.go_file_test_path .. "(" .. funcs_string .. ")$' " .. import_path

	M.print_and_run_cmd(cmd)
end

function M.run_function_test()
	local bufnr = vim.api.nvim_get_current_buf()

	local func_name = M.get_function_name_at_cursor(bufnr)
	if not func_name then
		vim.notify("No function found")
		return
	end

	if not func_name:match("^Test") then
		vim.notify("Not a test function")
		return
	end

	local module_name = M.get_go_module_name(bufnr)
	local pkg_path = M.get_go_package_path(bufnr)
	local import_path = pkg_path ~= "" and (module_name .. "/" .. pkg_path) or module_name
	local cmd = M.go_function_test_path .. func_name .. "$ " .. import_path

	M.print_and_run_cmd(cmd)
end

return M
