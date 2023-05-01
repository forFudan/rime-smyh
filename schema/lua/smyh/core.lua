local M = {}
M.filter = {}
M.translator = {}

-- 计算分词列表
local function get_code_segs(input)
    local code_segs = {}
    while string.len(input) ~= 0 do
        if string.match(string.sub(input, 1, 2), "[a-y];") then
            -- 匹配到一简
            table.insert(code_segs, string.sub(input, 1, 2))
            input = string.sub(input, 3)
        elseif string.match(string.sub(input, 1, 3), "[a-y][a-y][a-z;]") then
            -- 匹配到全码或二简
            table.insert(code_segs, string.sub(input, 1, 3))
            input = string.sub(input, 4)
        elseif input == ";" then
            -- 匹配到冗余分号
            break
        else
            -- 不合法或不完整分词输入串
            return
        end
    end
    return code_segs, input
end

-- 查询分词首选字列表
local function query_char_list(code_segs, env)
    if code_segs then
        local char_list = {}
        for _, code in ipairs(code_segs) do
            if env.mem:dict_lookup(code, false, 1) then
                for entry in env.mem:iter_dict() do
                    table.insert(char_list, entry.text)
                    break
                end
            end
        end
        return char_list
    end
    return nil
end

function M.filter.init(env)
end

-- 过滤器
function M.filter.func(input, env)
    local comment = env.engine.context:get_property("smyh.comment")
    for cand in input:iter() do
        if comment and string.len(comment) ~= 0 and comment ~= cand.text then
            -- 给首个与打断提示不同的候选添加施法提示
            local c = cand:get_genuine()
            c.comment = "["..comment.."]"
            comment = nil
        end
        if cand.text == "_" then
            cand = Candidate(cand.type, cand.start, cand._end, "", "")
        end
        yield(cand)
    end
end

function M.filter.fini(env)
end

function M.translator.init(env)
    env.mem = Memory(env.engine, env.engine.schema)
end

-- 翻译器
function M.translator.func(input, seg, env)
    -- 施法提示
    local pass_comment = ""
    -- 分词
    input = string.gsub(input, 'z', ';')
    local code_segs, remaining = get_code_segs(input)

    if remaining and remaining == ";" and code_segs and #code_segs > 1 then
        -- 有单个冗余分号, 且分词数大于一, 触发 "打断施法"
        local retain = code_segs[#code_segs]
        table.remove(code_segs)
        -- 保留分词末项, 上屏之前的首选
        local char_list = query_char_list(code_segs, env)
        if char_list then
            for _, char in ipairs(char_list) do
                -- 上屏
                env.engine:commit_text(char)
            end
            -- 清空编码, 追加保留串
            -- env.engine.context:pop_input(string.len(input))
            env.engine.context:clear()
            env.engine.context:push_input(retain)
            -- 假装table_translator
            if env.mem:dict_lookup(retain, true, 100) then
                for entry in env.mem:iter_dict() do
                    yield(Candidate("table", seg.start, seg._end, entry.text, entry.comment))
                end
            end
        end
    elseif (not remaining or remaining == "") and code_segs and #code_segs > 1 then
        -- 没有冗余编码, 分词数大于一, 触发施法提示
        local char_list = query_char_list(code_segs, env)
        if char_list then
            for _, char in ipairs(char_list) do
                pass_comment = pass_comment..char
            end
        end
    end

    -- 用context传递施法提示
    env.engine.context:set_property("smyh.comment", pass_comment)
end

function M.translator.fini(env)
end

return M