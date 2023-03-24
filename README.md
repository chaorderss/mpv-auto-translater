# README.md

## MPV Plugin: Real-Time Subtitle Translator

This MPV plugin provides real-time subtitle translations, fetching translations from the Google Translate API. You can set your desired target language, and the plugin will automatically display the translated subtitles on top of the original subtitles. It's a great way to enjoy foreign-language movies and TV shows without relying on pre-translated subtitles.

### Features

- Real-time subtitle translation
- Target language customization
- Pre-fetch subtitles in advance
- Automatic subtitle display

### Requirements

- MPV media player
- curl

### Installation

1. Copy the `subtitle_translator.lua` file into your MPV scripts directory. You can find this directory by running `mpv --help` and looking for the "Config dir" path, which usually looks like `~/.config/mpv/scripts/` on Unix systems, or `%APPDATA%\mpv\scripts\` on Windows systems.

2. Install the required dependencies. On Unix systems, you can use your package manager, like `apt-get`, `yum`, or `pacman` to install `curl`. On Windows, you can download a precompiled binary from the [curl website](https://curl.se/windows/).

### Usage

To start using the plugin, open a video file in MPV. The plugin will automatically translate and display subtitles in the target language you set in the script. By default, the target language is set to Simplified Chinese (zh-CN).

To change the target language, open the `subtitle_translator.lua` file in a text editor, and modify the `target_language` variable to the desired language code (e.g., "en" for English, "fr" for French, "es" for Spanish, etc.). Save the file and restart MPV to apply the changes.

### Known Limitations

- This plugin relies on the Google Translate API, which is subject to rate limits and may fail if too many requests are made in a short period.
- Translations may not always be accurate, as they are dependent on the quality of the Google Translate API.
- This plugin assumes that the original subtitles are well-timed and synchronized with the video.

### License

This plugin is released under the GNU General Public License v3.0 (GPLv3). See the LICENSE file for more information.
