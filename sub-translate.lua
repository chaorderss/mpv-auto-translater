--[[
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

local mp = require 'mp'
local utils = require 'mp.utils'
local json = require 'dkjson'
local md5 = require("md5")
local http = require("socket.http")

-- Set your desired target language here
local target_language = "zh-CN"
-- Global table for translated subtitles
translated_subs = {}
-- Set the pre-fetch delay in seconds
local pre_fetch_delay = 1
-- Set the path to the output subtitle file
local prev_translated_id = nil
local prev_original_id = nil
local subs
local tolerance = 0.2
local min_time_diff = 360
local totranslate_sub_num = 20
local function remove_extra_spaces(str)
    str = str:gsub("[\128-\255]", " ")
    return str:gsub("%s+", " ")
end

local function on_file_loaded()
    local video_path = mp.get_property("path")

    if video_path then
        local video_dir, video_name = utils.split_path(video_path)
        local video_name_no_ext = video_name:match("(.+)%..+$")
        local output_sub_file = utils.join_path(video_dir, video_name_no_ext .. ".ass")
        mp.msg.info("output_sub_file:" .. output_sub_file)
        -- Continue with the rest of your script
    else
        mp.msg.error("No video loaded.")
        return
    end
end
-- Helper function to check if a subtitle is already translated
local function is_translated(sub)
    return translated_subs[sub.start_time] ~= nil
end
local function read_file(path)
    local file_content = ""
    mp.msg.info('read_file:'..path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    for line in file:lines() do
        file_content = file_content .. line .. "\n"
    end

    file:close()
    return file_content
end
local function convert_time_to_seconds(time)
    local hours, minutes, seconds, milliseconds = string.match(time, "(%d+):(%d+):(%d+)[,%.](%d+)")
    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) + tonumber(milliseconds) / 1000
end
local function table_to_string(tbl, indent)
    if not indent then indent = 0 end

    local to_visit = {}
    local output = {}

    to_visit[#to_visit + 1] = {tbl = tbl, indent = indent}

    while #to_visit > 0 do
        local next = table.remove(to_visit)
        local tbl, indent = next.tbl, next.indent

        for k, v in pairs(tbl) do
            local formatting = string.rep("  ", indent) .. k .. ": "
            if type(v) == "table" then
                output[#output + 1] = formatting
                to_visit[#to_visit + 1] = {tbl = v, indent = indent + 1}
            else
                output[#output + 1] = formatting .. tostring(v)
            end
        end
    end

    return table.concat(output, "\n")
end
-- -- Set the stream index of the embedded subtitle you want to extract
-- local stream_index = 0

local function urlencode(str)
    if str then
        -- 只替换不在末尾的 "."
        str = string.gsub(str, "%.(.+)", ",%1")

        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w%-%.%_%~ ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end


local function extract_embedded_subtitles(video_file, output_sub_file, stream_index, sub_format)
    local args
    if sub_format == "mov_text" then
        -- 使用专门用于提取mov_text格式字幕的命令
        args = {
            "ffmpeg", "-i", video_file, "-map", "0:s:0" , output_sub_file .. ".srt"
        }
    else
        args = {
            "ffmpeg", "-y", "-loglevel", "quiet", "-nostdin", "-i", video_file,
            "-c:s", "copy", "-vn", "-an", "-map", "0:" .. tostring(stream_index) .. "?", output_sub_file .. "." .. sub_format
        }
    end
    local ffmpeg_cmd = table.concat(args, " ")
    mp.msg.info("ffmpeg command: " .. ffmpeg_cmd)

    local res = utils.subprocess({ args = args })
    if res.status ~= 0 then
        mp.msg.error("Failed to extract embedded subtitles using ffmpeg")
        mp.msg.error(res.stdout)
        mp.msg.error(res.stderr)
        return false
    end

    if sub_format == "srt" or sub_format == "mov_text" then
        local sub_file = output_sub_file .. ".srt"
        local sub_content = read_file(sub_file)

        local processed_content = ""
        local current_sub = ""
        local current_time_frame = ""
        local current_index = 0

        for line in sub_content:gmatch("[^\r\n]+") do
            if tonumber(line) then
                -- 这一行是索引号，忽略它
            elseif line:match("^%d+:%d+:%d+,%d+ %-%-> %d+:%d+:%d+,%d+$") then
                if current_sub ~= "" then
                    current_sub = current_sub:gsub("\n", " ")
                    processed_content = processed_content .. tostring(current_index) .. "\n" .. current_time_frame .. "\n" .. current_sub .. "\n\n"
                end

                current_time_frame = line
                current_sub = ""
                current_index = current_index + 1
            else
                current_sub = remove_extra_spaces(current_sub) .. remove_extra_spaces(line) .. "\n" -- 删除多余的空格
            end
        end

        if current_sub ~= "" then
            current_sub = current_sub:gsub("\n", " ")
            current_sub = remove_extra_spaces(current_sub)
            processed_content = processed_content .. tostring(current_index) .. "\n" .. current_time_frame .. "\n" .. current_sub .. "\n\n"
        end

        local file = io.open(sub_file, "w")
        if file then
            file:write(processed_content)
            file:close()
        end
    end
    -- mov_text不需要后处理

    return true
end


local function print_current_and_next_translated_subs(movie_time)
    print("Current and next 4 translated subtitles:")
    local found_count = 0

    for _, sub in ipairs(subs) do
        local start_time_seconds = convert_time_to_seconds(sub.start_time)
        local end_time_seconds = convert_time_to_seconds(sub.end_time)

        if found_count < 10 and movie_time <= end_time_seconds then
            local translated_text = translated_subs[sub.start_time] or ""
            print("[" .. sub.start_time .. "] " .. translated_text)
            found_count = found_count + 1
        end
    end
end

local function translate(text, target_language)
    local encodetl = urlencode(text)
    --print('translate encodetl:',encodetl)
    local url_request = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" .. target_language .. "&dt=t&q=" .. encodetl
    --print('translate url:',url_request)
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

local function baidu_translate(text, target_language)
    local app_id = "" -- Replace with your Baidu API App ID
    local secret_key = "" -- Replace with your Baidu API Secret Key
    local salt = tostring(os.time())

    --local openssl = require("openssl")
    local sign = app_id .. text .. salt .. secret_key
    local sign_md5 = md5.sumhexa(sign)

    local url_request = string.format("https://fanyi-api.baidu.com/api/trans/vip/translate?q=%s&from=auto&to=%s&appid=%s&salt=%s&sign=%s",
                                      urlencode(text), target_language, app_id, salt, sign_md5)
    local response_body, response_code, response_headers, response_status = http.request(url_request)
    if not response then
        print("Error in translation request:", error_message)
        return nil
    end

    local result = utils.parse_json(response)
    if result and result.trans_result then
        return table.concat(result.trans_result, " ", function(item) return item.dst end)
    end

    return nil
end

local function should_display_subtitle(sub, movie_time)
    local start_time_seconds = convert_time_to_seconds(sub.start_time)
    local end_time_seconds = convert_time_to_seconds(sub.end_time)
    local result = movie_time >= (start_time_seconds - tolerance) and movie_time <= end_time_seconds

    if result then
        print("Subtitle match found - movie_time:", movie_time, " start_time_seconds:", start_time_seconds, " end_time_seconds:", end_time_seconds)
    end

    return result
end

local function format_ass_time(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    local centisecs = math.floor((seconds * 100) % 100)
    return string.format("%02d:%02d:%02d.%02d", hours, minutes, secs, centisecs)
end
local function escape_special_characters(str)
    --local final_str = string.gsub(string.gsub(string.gsub(string.gsub(str, '(%b{})', ''), '(%b[])', ''), '\\i%d+', ''),'(%b())', '')
    local final_str = string.gsub(string.gsub(string.gsub(str, '(%b{})', ''), '\\i%d+', ''),'(%b())', '')
    final_str = string.gsub(final_str, "<i>", "") -- Remove <i> tag
    final_str = string.gsub(final_str, "</i>", "") -- Remove </i> tag

    return final_str
end
-- Initialize the flag
local is_display_subtitle_called = false

local function display_subtitles(original_text, translated_text, start_time, end_time)
    local duration = math.floor((end_time - start_time) * 1000)
    local formatted_original_text = string.gsub(original_text, "\\N", " ")
    local formatted_original_text = string.gsub(original_text, "-", "")
    --formatted_original_text = remove_extra_spaces(formatted_original_text)
    local formatted_translated_text = string.gsub(translated_text, "\\N", " ")
    local formatted_translated_text = string.gsub(translated_text, "-", "")
    --print('display_subtitles formatted_original_text:',formatted_original_text)
    local text_to_show = string.format("%s\n%s", escape_special_characters(formatted_original_text), escape_special_characters(formatted_translated_text))
    --text_to_show = escape_special_characters(text_to_show)
    text_to_show = string.gsub(text_to_show, "'", "’")

    local command_string = string.format("show-text '${osd-ass-cc/0}{\\an2}{\\fs15}${osd-ass-cc/1}%s' %i", text_to_show, duration)
    print('display_subtitles command_string: ', command_string, 'duration:', duration)
    mp.command(command_string)
    is_display_subtitle_called = true
end

local function display_subtitle(subs, movie_time)
    for i, sub in ipairs(subs) do
        if should_display_subtitle(sub, movie_time) then
            local translated_text = translated_subs[sub.start_time] or sub.text
            --print("translated_text",translated_text)
            --if translated_text then
            translated_subs[sub.start_time] = translated_text
            local start_time_seconds = convert_time_to_seconds(sub.start_time)
            local end_time_seconds = convert_time_to_seconds(sub.end_time)

            -- Check if the next subtitle's start time is now
            local next_sub = subs[i + 1]
            if next_sub then
                local next_start_time_seconds = convert_time_to_seconds(next_sub.start_time)
                if next_start_time_seconds <= movie_time then
                    -- Remove current subtitle
                    table.remove(subs, i)

                    -- Display and translate the next subtitle
                    --display_subtitle(subs, movie_time)
                    return
                end
            end
            if not is_display_subtitle_called then
                display_subtitles(sub.text, translated_text, start_time_seconds, end_time_seconds)
            end

            --end
            break
        end
    end
    is_display_subtitle_called = false
end

local lfs = require("lfs")

local function subtitles_to_string(subs)
    local result = "{"
    for i, sub in ipairs(subs) do
        result = result .. string.format("\n[%d] start_time: %s, end_time: %s, text: %s", i, sub.start_time, sub.end_time, sub.text)
        if i < #subs then
            result = result .. ","
        end
    end
    result = result .. "\n}"
    return result
end

local function parse_ass(subtitle_content)
    local subs = {}

    for layer, start_time, end_time, style, name, marginL, marginR, marginV, effect, text in string.gmatch(subtitle_content, "Dialogue: (%d+),(%d+:%d+:%d+[,.]%d+),(%d+:%d+:%d+[,.]%d+),([^,]*),([^,]*),(%d+),(%d+),(%d+),([^,]*),([^%s].-)\n") do
        table.insert(subs, { start_time = start_time, end_time = end_time, text = text })
    end

    return subs
end

local function parse_srt(subtitle_content)
    local subs = {}

    for index, start_time, end_time, text in string.gmatch(subtitle_content, "(%d+)\r?\n(%d+:%d+:%d+[,.]%d+)%s+-%-%>%s+(%d+:%d+:%d+[,.]%d+)\r?\n(.-)\r?\n\r?\n") do
        text = remove_extra_spaces(text) -- 删除多余的空格
        table.insert(subs, { start_time = start_time, end_time = end_time, text = text })
    end

    return subs
end

local function get_subtitles_from_file(sub_file)
    mp.msg.info('function get_subtitles_from_file sub file:' .. sub_file)
    local subtitle_content = read_file(sub_file)

    local subs = {}

    if not subtitle_content then
        print("get_subtitles_from_file Failed to load subtitles from file")
    else
        local ext = sub_file:match("^.+(%..+)$")
        if ext == ".ass" then
            subs = parse_ass(subtitle_content)
        elseif ext == ".srt" then
            subs = parse_srt(subtitle_content)
        else
            print("Unsupported subtitle format")
            return nil
        end
    end
    --print('get_subtitles_from_file subs:',table_to_string(subs))
    return subs
end

function extract_all_subtitles(video_file, output_sub_file_base)
    local args = {
        "ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", "-select_streams", "s", "-i", video_file
    }
    local res = utils.subprocess({ args = args })

    if res.status ~= 0 then
        mp.msg.error("Failed to get subtitle streams information")
        return false
    end

    local streams_info = utils.parse_json(res.stdout)
    if not streams_info or not streams_info["streams"] then
        mp.msg.error("Failed to parse subtitle streams information")
        return false
    end

    for _, stream in ipairs(streams_info["streams"]) do
        local sub_index = stream["index"]
        local sub_lang = stream["tags"]["language"] or "unknown"
        local sub_format = stream["codec_name"]
        local sub_ext = sub_format == "subrip" and ".srt" or ".ass"
        local is_sdh = stream["tags"]["title"] and stream["tags"]["title"]:lower():find("sdh") and "_SDH" or ""
        mp.msg.info("Stream object: " .. utils.to_string(stream))
        mp.msg.info("Subtitle index: " .. tostring(sub_index))

        local output_sub_file = string.format("%s_%02d_%s%s%s", output_sub_file_base, sub_index, sub_lang, is_sdh, sub_ext)
        mp.msg.info("Extracting subtitle stream with language: " .. sub_lang)

        if not extract_embedded_subtitles(video_file, output_sub_file, sub_index, sub_ext) then
            mp.msg.error("Failed to extract subtitle stream with language: " .. sub_lang)
        end
    end

    return true
end

-- Replace the extract_english_subtitles function call with extract_all_subtitles in the main function
local function main2()
    local video_file = mp.get_property("path")
    if not video_file then
        mp.msg.error("No video file loaded")
        return
    end

    local video_dir, video_name = utils.split_path(video_file)
    local video_name_no_ext = video_name:match("(.+)%..+$")
    local output_sub_file_base = utils.join_path(video_dir, video_name_no_ext)

    mp.msg.info("output_sub_file_base: " .. output_sub_file_base)

    if not extract_all_subtitles(video_file, output_sub_file_base) then
        mp.msg.error("Failed to extract all subtitles")
    end
end

--mp.register_event("file-loaded", main2)
function extract_english_subtitles(video_file, output_sub_file)
    -- Get information about subtitle streams
    local args = {
        "ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", "-select_streams", "s", "-i", video_file
    }
    local res = utils.subprocess({ args = args })

    if res.status ~= 0 then
        mp.msg.error("Failed to get subtitle streams information")
        return false
    end

    local streams_info = utils.parse_json(res.stdout)
    if not streams_info or not streams_info.streams then
        mp.msg.error("Failed to parse subtitle streams information")
        return false
    end

    -- Print all available subtitle streams and their language tags
    for i, stream in ipairs(streams_info.streams) do
        print(string.format("Stream Index: %d, Language: %s", stream.index, stream.tags and stream.tags.language or "unknown"))
    end

    -- Find the indices of English subtitle streams and their formats
    local eng_stream_indices = {}
    for i, stream in ipairs(streams_info.streams) do
        if stream.tags and string.lower(stream.tags.language) == "eng" then
            print(string.format("eng Stream Index: %d, Language: %s", stream.index, stream.tags and stream.tags.language or "unknown"))
            table.insert(eng_stream_indices, { index = stream.index, format = stream.codec_name })
        end
    end

    if #eng_stream_indices == 0 then
        mp.msg.error("No English subtitle stream found")
        return false
    end

    -- Prioritize selecting the SDH stream if available
    local selected_stream = nil
    print(table_to_string(eng_stream_indices))
    for _, stream in ipairs(eng_stream_indices) do
        if string.lower(stream.format) == "subrip" and stream.tags and string.lower(stream.tags.title) == "SDH" then
            selected_stream = stream
            break
        end
    end

    -- If SDH stream is not found, use the first English stream
    if not selected_stream then
        selected_stream = eng_stream_indices[#eng_stream_indices]
    end

    local eng_stream_index = selected_stream.index
    local eng_sub_format = selected_stream.format

    -- 检查字幕格式是否支持
    if eng_sub_format ~= "ass" and eng_sub_format ~= "subrip" and eng_sub_format ~= "mov_text" then
        mp.msg.error("Unsupported subtitle format: " .. eng_sub_format)
        return false
    end

    -- 根据字幕格式设置输出文件的扩展名
    local sub_ext
    if eng_sub_format == "subrip" then
        sub_ext = "srt"
    elseif eng_sub_format == "mov_text" then
        sub_ext = "mov_text" -- 假设mov_text应保存为srt文件
    else
        sub_ext = "ass"
    end

    mp.msg.info("...Extract the English subtitle stream",eng_sub_format)

    -- 提取英文字幕流
    return extract_embedded_subtitles(video_file, output_sub_file, eng_stream_index, sub_ext)
end

local function check_sub_file_exists(path)
    local file = io.open(path, "r")
    if file ~= nil then
        io.close(file)
        return true
    else
        return false
    end
end
local function check_sub_file_exists(path, extensions)
    for _, ext in ipairs(extensions) do
        local file = io.open(path .. ext, "r")
        if file ~= nil then
            io.close(file)
            return true, ext
        end
    end
    return false, nil
end

local function main()
    local video_file = mp.get_property("path")
    if not video_file then
        mp.msg.error("No video file loaded")
        return
    end

    -- Generate the output_sub_file path based on the video_file path
    local video_dir, video_name = utils.split_path(video_file)
    local video_name_no_ext = video_name:match("(.+)%..+$")
    local output_sub_file = utils.join_path(video_dir, video_name_no_ext)

    mp.msg.info("output_sub_file: ".. output_sub_file)
    local sub_extensions = {'.ass', '.srt'}
    local subs_exist, sub_ext = check_sub_file_exists(output_sub_file, sub_extensions)

    if not subs_exist then
        if extract_english_subtitles(video_file, output_sub_file) then
            subs_exist, sub_ext = check_sub_file_exists(output_sub_file, sub_extensions)
            if not subs_exist then
                mp.msg.error("main Failed to load subtitles from file")
                return
            end
        else
            mp.msg.error("Failed to extract embedded subtitles")
            return
        end
    end

    subs = get_subtitles_from_file(output_sub_file .. sub_ext)
    if not subs then
        mp.msg.error("main Failed to load subtitles from file")
        return
    end
end

local function async_translate(sub, target_language)
    coroutine.wrap(function()
        if not is_translated(sub) then
            local translated_text = translate(sub.text, target_language)
            if translated_text then
                translated_subs[sub.start_time] = translated_text
            end
        end
    end)()
end

-- Event handler for the "time-pos" property
local function on_time_pos_change(_, movie_time)
    if not movie_time then return end
    if not subs or #subs == 0 then
        print("on_time_pos_change no subs")
        return
    end

    local current_subtitles = {}
    local next_subs_count = 0
    for i, sub in ipairs(subs) do
        local start_time_seconds = convert_time_to_seconds(sub.start_time)
        local end_time_seconds = convert_time_to_seconds(sub.end_time)

        if movie_time >= start_time_seconds and movie_time <= end_time_seconds then
            table.insert(current_subtitles, sub)
        elseif movie_time < start_time_seconds then
            if next_subs_count < 30 or (start_time_seconds - movie_time) < min_time_diff then
                table.insert(current_subtitles, sub)
                next_subs_count = next_subs_count + 1
            else
                break
            end
        end
    end
    -- Sort the current_subtitles by start_time
    table.sort(current_subtitles, function(a, b)
        return convert_time_to_seconds(a.start_time) > convert_time_to_seconds(b.start_time)
    end)

    --print("on_time_pos_change:",table_to_string(current_subtitles))
    print("on_time_pos_change translated_subs:",table_to_string(translated_subs))
    display_subtitle(current_subtitles, movie_time)
    if #current_subtitles > 0 then
        for i, sub in ipairs(current_subtitles) do
            async_translate(sub, target_language)
        end
    else
        -- print("No matching subtitle found for movie_time:", movie_time)
    end
end


-- Observe the "time-pos" property to display subtitles at the correct time
--mp.observe_property("time-pos", "number", on_time_pos_change)
local function timer_callback()
    local movie_time = mp.get_property_number("time-pos")
    on_time_pos_change(nil, movie_time)
end

local timer = mp.add_periodic_timer(0.2, timer_callback)

mp.register_event("file-loaded", main)
mp.register_event("file-loaded", on_file_loaded)

