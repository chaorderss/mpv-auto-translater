local mp = require 'mp'
local utils = require 'mp.utils'
local json = require 'dkjson'

local function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w%-%.%_%~ ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

local function translate(text, target_language)
    local url_request = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" .. target_language .. "&dt=t&q=" .. urlencode(text)

    mp.msg.info("Request URL: " .. url_request)  -- Print the request URL

    local res, err = utils.subprocess({ args = { "curl", "-s", "-S", "-f", url_request } })

    if not res then
        mp.msg.error("Translation error: Failed to execute curl")
        return nil
    elseif res.status ~= 0 then
        mp.msg.error("Translation error: HTTP error code: " .. tostring(res.status))
        return nil
    end

    local result = json.decode(res.stdout)

    if result and result[1] and result[1][1] and result[1][1][1] then
        return result[1][1][1]
    else
        mp.msg.error("Translation error: Unable to parse JSON response")
        return nil
    end
end

function get_sub()
    local res = {}
    res['text'] = mp.get_property("sub-text")
    if res['text'] == "" or res['text'] == nil then return nil; end

    res['start'] = mp.get_property("sub-start")
    res['end'] = mp.get_property("sub-end")
    return res
  end

local function escape_special_characters(str)
    local escaped_str = string.gsub(str, '([\\{}%[%]%(%)%\\])', '\\%1') -- Escape necessary characters
    escaped_str = string.gsub(escaped_str, '\n', ' ') -- Replace LF with a blank space
    return escaped_str
end

local function display_translated_subtitle()
    local target_language = "zh-CN" -- Set your desired target language here
    local sub = get_sub()
    if sub == nil then return; end
    escaped_sub = escape_special_characters(sub['text'])
    mp.msg.info('escaped_sub:' .. escaped_sub)
    local translated_text = translate(escaped_sub, target_language)

    mp.msg.info('sub:' .. sub['text'] .. 'start:' .. sub['start'] .. 'end:' .. sub['end'] )
    time_duration = tonumber(sub['end'] - sub['start']) * 1000
    if translated_text then
        mp.msg.info("translated_text: " .. translated_text) -- Print the translated text to the console
        translated_text = translated_text:gsub('"', '\\"')
        local command_string = string.format("show-text '${osd-ass-cc/0}{\\an5}${osd-ass-cc/1}%s' %i", translated_text, time_duration)

        mp.command(command_string)

    else
        mp.msg.error("Translation error")
    end
end





mp.observe_property("sub-text", "string", function(_, text)
    if text and text ~= "" then
        display_translated_subtitle()
        --show_translated_sub(text)
    else
        mp.set_property("osd-ass-cc/0", "")
    end
end)
