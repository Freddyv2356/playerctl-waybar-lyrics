# playerctl-waybar-lyrics
Basic ``.sh`` script that help you display lyrics fetching from lrclib and displaying on waybar (mostly used on youtube for KR,JP,CN songs) currently still testing and debugging the hell out of it [Expect that it will be a bit delay on displaying lyrics compare to the orignal player]. 

Required `mpris` or `playerctl` to read the player status (I forgot which one is used to read the player status.)

You are free to use this script and modify or upgrade it as much as you want. As my script is not much valueable or anything just please keep my name in the file is okay.

## Dependencies
```
playerctl mpris jq zenity
```
For Debian/Ubuntu: ``sudo apt install jq playerctl mpris zenity``

For Arch: ``sudo pacman -Sy playectl mpris zenity jq``

Note: ``zenity`` is required for the script that use zenity to display only.

## HOW TO INSTALL
Download the .sh file and set it as executable. (sudo chmod +x lyric_bars.sh)

And also copy this as the module:
```json
"modules-right": ["custom/lyrics"], // Feel free to edit this as modules-left, right or center to your liking.
"custom/lyrics": {
        "exec": "/home/username/.config/waybar/lyric_bars.sh", // Remember to change the directory to your.
       "interval": 1,
        "tooltip": true,
        "on-click": "/home/username/.config/waybar/lyric_bars.sh right",
        "on-click-right": "/home/username/.config/waybar/lyric_bars.sh right",
        "on-click-middle": "/home/username/.config/waybar/lyric_bars.sh middle",
        "on-click-left": "/home/username/.config/waybar/lyric_bars.sh left",
        "signal": 10,
        "max-length": 80, // Basically how much characters do you want to display on the bar.
        "smooth-scrolling-threshold": 1, // Useless value I forgor to delete.
        "exec-on-event": true,
```
After setup successfully on your waybar and it display `No song playing` then you're good to go I guess.

## HOW TO USE
``Status: No song playing``

![image](https://github.com/user-attachments/assets/3b6a938c-cd93-4987-9276-f5d639f41df1)

Then just start up some songs out on youtube.

You can try Mili - Tian Tian out for testing out the options when there are multiple choices of lyrics. (Your mouse have to be on the bar to change selection of the displayed subtitle.)

``Status: Song Selection`` [Note: The value 248 after the song name is the total duration of lyric file]

![image](https://github.com/user-attachments/assets/cd81ec79-8f9d-4748-ad1d-3d896ce8a967)

RIGHT CLICK = Go up 1

MIDDLE CLICK = CHOOSE

LEFT CLICK = Go down by 1 

``Status: No song title available``

Then I guess is probably one or two thing that is the search function of this script are not good enough to find it or it doesn't exist in the lrclib database so you can go add that in using ``LRCGET``(https://github.com/tranxuanthang/lrcget).

Extra info: You can also edit the style.css file to customize the display.

```css
#custom-lyrics {
    color: #ffffff;
    font-family: "Noto Sans CJK JP", sans-serif;
    font-size: 14px;
    padding: 0 0px;
    background: transparent;
    border-bottom: 2px solid #ffffff;
    margin: 0 5px;
    }

#custom-lyrics.empty {
    color: #5c6370;
    border-bottom: none;
    }
```

## DEBUGGING
You can run ``bash -x ./lyric_bar.sh middle > debug.txt 2>&1`` so that it will output the debug value or just read the outputted error.log in the folder to read the log that it write.
You can also check the cached lyric folder to add the lyric by yourself using correct .lrc type basically ``[00:00:00] Bruh`` which the number in [] is the timestamp to read from the file and sync it with playerctl status.
