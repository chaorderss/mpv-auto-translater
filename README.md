# MPV Subtitle Translator

This Lua script for the MPV player extracts embedded subtitles from a video, translates them into a target language, and displays the translated subtitles alongside the original subtitles. The script supports both .ass and .srt subtitle formats.

## Features

- Extracts embedded subtitles from video files
- Translates subtitles into a target language using an external translation API
- Displays translated subtitles alongside the original subtitles
- Supports both .ass and .srt subtitle formats

## Requirements

- [MPV](https://mpv.io) media player
- Lua 5.1 or higher
- [LuaFileSystem (LFS)](https://keplerproject.github.io/luafilesystem/) library
- FFmpeg and FFprobe installed and available in the system PATH

## Installation

1. Install the MPV media player, Lua 5.1 or higher, and LuaFileSystem (LFS) library.
2. Install FFmpeg and FFprobe and ensure they are available in the system PATH.
3. Save the provided Lua script (first part and second part combined) as `subtitle_translator.lua` in your MPV scripts directory. The default location is `~/.config/mpv/scripts/` on Linux and macOS or `%APPDATA%\mpv\scripts\` on Windows.

## Usage

1. Play a video file with embedded subtitles in MPV.
2. The script will automatically extract the subtitles, translate them into the target language, and display the translated subtitles alongside the original subtitles.
3. if subtitles has in the same directary and is the same name of the video.script can load automaticly

## Configuration

You can customize the target language by modifying the `target_language` variable in the script. Change its value to the desired language code (e.g., 'en' for English, 'es' for Spanish, etc.).

You can also modify the translation function (`translate()`) to use a different translation API or service by replacing the current implementation with the appropriate API calls.

## Limitations

- The script may not work correctly if the subtitle timings are incorrect.
- The translation quality depends on the translation service used.
- Baidu api not working at this moment.

## License

This script is provided under the GPLv3 License. For more information, please see the [LICENSE](LICENSE) file.
