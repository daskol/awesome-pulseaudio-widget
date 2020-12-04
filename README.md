# Awesome PulseAudio Volume Widget

*Awesome WM text widget to display volume which leverages D-Bus PulseAudio
interface.*

## Overview

This is a simple text widget which is updates volume information as soon as
volume level was changed. Such approch is the most preferred and the most
efficient.

Under the hood it connects to D-Bus daemon which is provided by PulseAudio
daemon. After that it subscribes to `VolumeUpdated` signal on the bus. So, it
redraw the widget (actually, textbox) as it receives an signal message.

## Installation

The simplest way to get widget is to use `luarocks` for installation.
```bash
luarocks install awesome-pulseaudio-widget
```
Then one should update Awesome WM configuration file in the following manner.
```lua
-- rc.lua

-- Volume level indicator.
local pulseaudio_widget = required("pulseaudio-widget")
local pulseaudio = pulseaudio_widget()

...

-- Add widgets to the wibox.
s.mywibox:setup {
    ...,
    { -- Right widgets
        ...,
        pulseaudio,
    },
}
```

## Configuration

At the moment the widget does not allow fine adjustment. So the only available
option is a PulseAudio sink which should be used to display volume level.
```lua
local pulseaudio = pulseaudio_widget {
    sink = "/org/pulseaudio/core1/sink1",
}
```
