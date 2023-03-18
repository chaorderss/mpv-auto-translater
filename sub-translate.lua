local mp = require 'mp'
local utils = require 'mp.utils'
local json = require 'dkjson'

-- Set your desired target language here
local target_language = "zh-CN"

-- Set the pre-fetch delay in seconds
local pre_fetch_delay = 1

-- Set the path to the output subtitle file
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


-- Set the stream index of the embedded subtitle you want to extract
local stream_index = 0

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

local function extract_embedded_subtitles(video_file, output_sub_file)
    local args = {
        "ffmpeg", "-y", "-nostdin", "-i", video_file,
        "-c:s", "copy", "-vn", "-an", "-map", "0:s", output_sub_file
    }

    local res = utils.subprocess({ args = args })
    if res.status ~= 0 then
        mp.msg.error("Failed to extract embedded subtitles using ffmpeg")
        mp.msg.error(res.stdout)
        mp.msg.error(res.stderr)
        return false
    end

    return true
end


local function translate(text, target_language)
    local url_request = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" .. target_language .. "&dt=t&q=" .. urlencode(text)

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

local function display_translated_subtitle(translated_text, start_time, end_time)
    local duration = tonumber(end_time - start_time) * 1000
    local command_string = string.format("show-text '${osd-ass-cc/0}{\\an5}${osd-ass-cc/1}%s' %i", translated_text, duration)
    mp.command(command_string)
end

local lfs = require("lfs")

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

local function get_subtitles_from_file(sub_file)
    mp.msg.info('function get_subtitles_from_file sub file:' .. sub_file)
    -- local subtitle_file_path = "/Users/xmxx/Downloads/Star.Trek.Picard.S03E04.1080p.WEB.H264-CAKES[rarbg]/star.trek.picard.s03e04.1080p.web.h264-cakes.ass"
    local subtitle_content = read_file(sub_file)

    local subs = {} -- Add this line to initialize the subs table

    if not subtitle_content then
        print("get_subtitles_from_file Failed to load subtitles from file")
    else
        print("Subtitle content:")
        print(subtitle_content)
    end

    for start_time, end_time, text in string.gmatch(subtitle_content, "Dialogue: [%d,]*:(%d%d:%d%d:%d%d%.%d%d),(%d%d:%d%d:%d%d%.%d%d),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^%s].-)\n") do
        table.insert(subs, { start_time = start_time, end_time = end_time, text = text })
    end

    print("Size of subs table: " .. #subs)
    for i, sub in ipairs(subs) do
        print("Subtitle entry " .. i .. ":")
        print("Start time: " .. sub.start_time)
        print("End time: " .. sub.end_time)
        print("Text: " .. sub.text)
    end

    return subs
end

local function convert_time_to_seconds(time)
    local hours, minutes, seconds, milliseconds = string.match(time, "(%d+):(%d+):(%d+),(%d+)")
    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) + tonumber(milliseconds) / 1000
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
        local output_sub_file = utils.join_path(video_dir, video_name_no_ext .. ".ass")

    mp.msg.info("output_sub_file: ".. output_sub_file)

    if not extract_embedded_subtitles(video_file, output_sub_file, stream_index) then
        mp.msg.error("Failed to extract embedded subtitles")
        return
    end

    local subs = get_subtitles_from_file(output_sub_file)
    if not subs or #subs == 0 then
        mp.msg.error("main Failed to load subtitles from file")
        return
    end

    for i, sub in ipairs(subs) do
        mp.msg.info('sub:', sub)
        local start_time = convert_time_to_seconds(sub.start_time) - pre_fetch_delay
        local end_time = convert_time_to_seconds(sub.end_time)

        mp.add_timeout(start_time, function()
            local translated_text = translate(sub.text, target_language)
            if translated_text then
                display_translated_subtitle(translated_text, start_time + pre_fetch_delay, end_time)
            end
        end)
    end
end



mp.register_event("file-loaded", main)
mp.register_event("file-loaded", on_file_loaded)
