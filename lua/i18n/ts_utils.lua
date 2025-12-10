local M = {}

-- 尝试从配置中提取纯函数名列表（忽略复杂的正则配置）
function M.get_func_names(config)
  local names = {}
  local raw = (config.options and config.options._func_pattern_spec) or {}
  
  if type(raw) == 'table' then
    for _, v in ipairs(raw) do
      if type(v) == 'string' then
        -- 简单过滤：如果不包含特殊正则字符，则视为普通函数名
        if not v:find('[%^%$%(%)%%%.%[%]%*%+%-%?]') then
          table.insert(names, v)
        end
      elseif type(v) == 'table' and v.call then
        table.insert(names, v.call)
      end
    end
  end
  
  -- 如果没提取到，或者是默认配置，使用默认值
  if #names == 0 then
    return { 't', '$t' }
  end
  return names
end

-- 使用 Treesitter 提取 i18n keys
-- 返回一个 list: { { key=string, line=number(0-based), col=number(end_col of string) }, ... }
function M.extract_keys(bufnr, config)
  -- 检查环境是否支持
  local ok_parsers, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok_parsers then parsers = nil end

  local func_names = M.get_func_names(config)
  if #func_names == 0 then return nil end

  local funcs_str = ""
  for _, name in ipairs(func_names) do
    funcs_str = funcs_str .. '"' .. name .. '" '
  end

  local keys = {}

  local function strip_quotes(text)
    local first = text:sub(1, 1)
    local last = text:sub(-1)
    if (first == '"' or first == "'" or first == "`") and first == last then
      return text:sub(2, -2)
    end
    return text
  end

  -- TS 路径（支持跨行、模板字符串、首参校验）
  local function extract_with_ts()
    if not parsers then return nil end
    local lang = parsers.get_buf_lang(bufnr)
    if not lang then return nil end

    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok_parser or not parser then return nil end
    parser:parse(true)

    local get_text = vim.treesitter.get_node_text

    -- 收集 const t = useTranslations("banner") 的命名空间映射
    local ns_query_str = [[
      (variable_declarator
        name: (identifier) @var
        value: (call_expression
          function: [ (identifier) @fn (member_expression property: (property_identifier) @fn) ]
          arguments: (arguments . [(string) (template_string)] @ns .?)
        )
        (#eq? @fn "useTranslations")
      )
    ]]

    local ns_map = {}
    local ok_ns, ns_query = pcall(vim.treesitter.query.parse, lang, ns_query_str)
    if ok_ns then
      parser:for_each_tree(function(t, l)
        if l == 'javascript' or l == 'typescript' or l == 'tsx' or l == 'jsx' then
          for _, match, _ in ns_query:iter_matches(t:root(), bufnr, 0, -1) do
            local var_node
            local ns_node
            for id, node in pairs(match) do
              local name = ns_query.captures[id]
              if name == 'var' then
                var_node = node
              elseif name == 'ns' then
                ns_node = node
              end
            end
            if var_node and ns_node and get_text then
              local var_name = get_text(var_node, bufnr)
              local ns_text = strip_quotes(get_text(ns_node, bufnr))
              if var_name and ns_text and ns_text ~= '' then
                ns_map[var_name] = ns_text
              end
            end
          end
        end
      end)
    end

    local query_str_js = [[
      (call_expression
        function: [
          (identifier) @func_name
          (member_expression property: (property_identifier) @func_name)
        ]
        arguments: (arguments) @args
        (#any-of? @func_name %s)
      )
    ]]
    local query_str = string.format(query_str_js, funcs_str)

    local seen_ranges = {}

    local function process_tree(tree, l)
      local ok_q, query = pcall(vim.treesitter.query.parse, l, query_str)
      if not ok_q then return end

      for _, match, _ in query:iter_matches(tree:root(), bufnr, 0, -1) do
        local args_node
        local func_name_node
        for id, node in pairs(match) do
          local name = query.captures[id]
          if name == "args" then
            args_node = node
          elseif name == "func_name" then
            func_name_node = node
          end
        end

        if args_node then
          local first_named
          for child in args_node:iter_children() do
            if child:named() then
              first_named = child
              break
            end
          end

          if first_named and (first_named:type() == "string" or first_named:type() == "template_string") then
            local r1, c1, r2, c2 = first_named:range()
            local id_key = string.format("%d:%d-%d:%d", r1, c1, r2, c2)
            if not seen_ranges[id_key] then
              seen_ranges[id_key] = true

                local text = get_text(first_named, bufnr)
                local key = strip_quotes(text)

                if func_name_node and get_text then
                  local fname = get_text(func_name_node, bufnr)
                  local ns = ns_map[fname]
                  if ns and ns ~= '' then
                    key = ns .. "." .. key
                  end
                end

              table.insert(keys, {
                key = key,
                line = r1,
                start_pos = c1,
                end_pos = c2,
                row_end = r2,
              })
            end
          end
        end
      end
    end

    parser:for_each_tree(function(t, l)
      if l == 'javascript' or l == 'typescript' or l == 'tsx' or l == 'jsx' then
        process_tree(t, l)
      end
    end)

    if #keys > 0 then return true end
    return nil
  end

  -- 纯文本回退（无 TS 解析时仍能跨行匹配）
  local function extract_with_text()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if not lines or #lines == 0 then return nil end
    local content = table.concat(lines, "\n")

    -- 预构建行起始偏移，便于定位行列
    local offsets = {}
    local acc = 1
    for i, l in ipairs(lines) do
      offsets[i] = acc
      acc = acc + #l + 1
    end

    local function pos_to_line_col(pos)
      local lo, hi = 1, #offsets
      while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local start_pos = offsets[mid]
        local next_start = offsets[mid + 1] or acc
        if pos < start_pos then
          hi = mid - 1
        elseif pos >= next_start then
          lo = mid + 1
        else
          return mid, pos - start_pos + 1
        end
      end
      return 1, pos
    end

    -- 解析 useTranslations("ns") -> 变量名映射（跨行也可匹配）
    local ns_map = {}
    for var, quote, ns in content:gmatch("([%w_]+)%s*=%s*useTranslations%s*%(%s*([`'\"])%s*(.-)%s*%2") do
      if var and ns and ns ~= '' then
        ns_map[var] = ns
      end
    end

    local seen = {}
    for _, pat in ipairs(config.options.func_pattern or {}) do
      local init = 1
      while true do
        local s, e, key = content:find(pat, init)
        if not s then break end
        init = e + 1
        if key and key ~= '' then
          local match_str = content:sub(s, e)
          local ks, ke = match_str:find(key, 1, true)
          if ks and ke then
            local abs_s = s + ks - 1
            local abs_e = s + ke - 1
            local id_key = string.format("%d-%d", abs_s, abs_e)
            if not seen[id_key] then
              seen[id_key] = true
              local call = match_str:match("([%w_%.]+)%s*%(")
              local ns = call and ns_map[call]
              if ns and ns ~= '' then
                key = ns .. "." .. key
              end
              local line_s, col_s = pos_to_line_col(abs_s)
              local line_e, col_e = pos_to_line_col(abs_e)
              table.insert(keys, {
                key = key,
                line = line_s - 1,
                start_pos = col_s - 1,
                end_pos = col_e,
                row_end = line_e - 1,
              })
            end
          end
        end
      end
    end

    if #keys > 0 then return true end
    return nil
  end

  if extract_with_ts() then
    return keys
  end

  if extract_with_text() then
    return keys
  end

  return nil
end

return M
