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
  if not ok_parsers then return nil end
  
  local lang = parsers.get_buf_lang(bufnr)
  if not lang then return nil end
  
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok_parser or not parser then return nil end
  
  parser:parse(true)
  
  local func_names = M.get_func_names(config)
  if #func_names == 0 then return nil end
  
  -- 构建 Query
  -- 匹配 t('key') 或 this.t('key')
  local query_str_js = [[
    (call_expression
      function: [
        (identifier) @func_name
        (member_expression property: (property_identifier) @func_name)
      ]
      arguments: (arguments (string) @string_node . )
      (#any-of? @func_name %s)
    )
  ]]
  
  local funcs_str = ""
  for _, name in ipairs(func_names) do
    funcs_str = funcs_str .. '"' .. name .. '" '
  end
  
  local query_str = string.format(query_str_js, funcs_str)
  
  local keys = {}
  local seen_ranges = {} -- 避免重复 (line_col)
  
  local function process_tree(tree, l)
    local ok_q, query = pcall(vim.treesitter.query.parse, l, query_str)
    if not ok_q then return end
    
    for _, match, _ in query:iter_matches(tree:root(), bufnr, 0, -1) do
      local string_node = nil
      for id, node in pairs(match) do
        local name = query.captures[id]
        if name == "string_node" then
          string_node = node
        end
      end
      
      if string_node then
        local r1, c1, r2, c2 = string_node:range()
        -- 避免重复
        local id = string.format("%d:%d-%d:%d", r1, c1, r2, c2)
        if not seen_ranges[id] then
          seen_ranges[id] = true
          
          local text = vim.treesitter.get_node_text(string_node, bufnr)
          -- 去除引号
          local key = text
          local first = text:sub(1, 1)
          local last = text:sub(-1)
          if (first == '"' or first == "'" or first == "`") and first == last then
            key = text:sub(2, -2)
          end
          
          table.insert(keys, {
            key = key,
            line = r1,      -- 字符串所在行（如果是多行字符串，取起始行?）
            start_pos = c1, -- 0-based
            end_pos = c2,   -- 0-based (after quote)
            row_end = r2    -- 字符串结束行
          })
        end
      end
    end
  end
  
  parser:for_each_tree(function(t, l)
    if l == 'javascript' or l == 'typescript' or l == 'tsx' or l == 'jsx' then
      process_tree(t, l)
    end
  end)
  
  return keys
end

return M
