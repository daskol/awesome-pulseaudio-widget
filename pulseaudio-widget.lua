--[[
    \file get-volume.lua
]]--

local lgi = require("lgi")
local Gio = lgi.Gio
local GLib  = lgi.GLib

local awful = require("awful")
local wibox = require("wibox")

--[[
    PulseAudio
]]--
local PulseAudio = {}

function PulseAudio:new()
    return setmetatable({}, {
        __index = self,
        __tostring = self.tostring,
        __gc = self.destroy,
    }):init()
end

function PulseAudio:init()
    local bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    self.conn, self.err = self:connect(bus)
    self.closed = self.conn:is_closed()
    self.sinks = {}
    self.sub_ids = {}
    return self
end

function PulseAudio:connect(bus)
    local arg = GLib.Variant("(ss)", {"org.PulseAudio.ServerLookup1", "Address"})
    local res, err = bus:call_sync(
        "org.PulseAudio1",
        "/org/pulseaudio/server_lookup1",
        "org.freedesktop.DBus.Properties",
        "Get",
        arg,
        nil,
        Gio.DBusCallFlags.NONE,
        -1)

    if err ~= nil then
        return nil, err
    end

    local addr = res.value[1].value  -- Unpack tuple of variant type.
    local flag = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
    local conn = Gio.DBusConnection.new_for_address_sync(addr, flag)
    return conn, nil
end

function PulseAudio:destroy()
    for signal, sub_id in pairs(self.sub_ids) do
        self.conn:unsubscribe(self.sub_id)
    end
end

function PulseAudio:list_sinks()
    local arg = GLib.Variant("(ss)", {"org.PulseAudio.Core1", "Sinks"})
    local res, err = self.conn:call_sync(
        nil,
        "/org/pulseaudio/core1",
        "org.freedesktop.DBus.Properties",
        "Get",
        arg,
        nil,
        Gio.DBusCallFlags.NONE,
        -1)

    if err ~= nil then
        return {}, err
    end

    local sinks = {}
    for _, path in ipairs(res.value[1].value) do
        local sink, err = self:get_sink(path)
        if err ~= nil then
            return sinks, err
        end
        sinks[path] = sink
    end

    self.sinks = sinks

    return sinks, nil
end

function PulseAudio:get_sink(path)
    local tpl, err = self.conn:call_sync(
        nil,
        path,
        "org.freedesktop.DBus.Properties",
        "GetAll",
        GLib.Variant("(s)", {"org.PulseAudio.Core1.Device"}),
        nil,
        Gio.DBusCallFlags.NONE,
        -1)

    if err ~= nil then
        return res, err
    end

    local res = tpl.value[1]
    local sink = Sink:new()
    sink.path = path
    sink.name = res.Name
    sink.muted = res.Mute
    sink.volume = {}

    for i, value  in ipairs(res.Volume) do
        sink.volume[i] = value / 65536
    end

    return sink, nil
end

function PulseAudio:handle_volume_updated(conn, sender_name, object_path, interface_name, signal_name, params)
    local volume = {}
    for i, value in ipairs(params.value[1]) do
        volume[i] = value / 65536
    end

    if self.sinks ~= nil and self.sinks[object_path] ~= nil then
        self.sinks[object_path].volume = volume
    end
end

function PulseAudio:subscribe_to_volume_updates(callback)
    local tpl, err = self.conn:call_sync(
        nil,
        "/org/pulseaudio/core1",
        "org.PulseAudio.Core1",
        "ListenForSignal",
        GLib.Variant("(sao)", {"org.PulseAudio.Core1.Device.VolumeUpdated", {}}),
        nil,
        Gio.DBusCallFlags.NONE,
        -1)

    if err ~= nil then
        return err
    end

    self.sub_ids = {}
    self.sub_ids["VolumeUpdated"] = self.conn:signal_subscribe(
        nil,
        "org.PulseAudio.Core1.Device",
        nil,
        nil,
        nil,
        Gio.DBusSignalFlags.NONE,
        function(...)
            self:handle_volume_updated(...)
            if callback then
                callback(self.volume)
            end
        end)

    return nil
end

function PulseAudio:tostring()
    return "<PulseAudio closed=" .. tostring(self.closed) .. ">"
end

--[[
    Sink is a simple wrapping object in order to provide more convinient
    interface to PulseAudio sink object over D-Bus.
]]--
Sink = {}

function Sink:new()
    return setmetatable({}, {
        __index = self,
        __tostring = Sink.tostring,
    }):init()
end

function Sink:init()
    return self
end

function Sink:update_volume(conn)
    local tpl, err = conn:call_sync(
        nil,
        self.path,
        "org.freedesktop.DBus.Properties",
        "Get",
        GLib.Variant("(ss)", {"org.PulseAudio.Core1.Device", "Volume"}),
        nil,
        Gio.DBusCallFlags.NONE,
        -1)

    if err ~= nil then
        return self.volume
    end

    for i, value in ipairs(tpl.value[1]) do
        self.volume[i] = value / 65536
    end

    return self.volume
end

function Sink:tostring()
    return "<Sink[" .. tostring(self.path) .. "] muted=" .. tostring(self.muted) .. ">"
end

--[[
    PulseAudioWidget
]]--
local PulseAudioWidget = {}

function PulseAudioWidget:new(args)
    return setmetatable({}, {__index = self}):init(args)
end

function PulseAudioWidget:init(args)
    self.pa = PulseAudio:new()
    self.sinks = self.pa:list_sinks()
    self.volume = nil

    -- If there is no any sink specified by user then use the first sink in a
    -- sink list.
    if args.sink == nil then
        for k, v in pairs(self.sinks) do
            self.sink = k
            break
        end
    end

    self.pa:subscribe_to_volume_updates(function(...) self:update(...) end)

    self.widget = wibox.widget.textbox()
    self.widget.set_align("right")
    self.widget.font = args.widget_font
    self.widget:set_markup("000%")

    self.tooltip = awful.tooltip({objects={self.widget}})
    self.tooltip:set_text("Volume.")

    self:update()

    return self
end

function PulseAudioWidget:update()
    local sink = self.sink
    local volume = self.sinks[sink].volume[1]
    self.volume = math.floor(volume * 100)
    self.widget:set_markup(tostring(self.volume) .. "%")
end

return setmetatable(PulseAudioWidget, {
    __call = PulseAudioWidget.new,
})

--local main_loop = GLib.MainLoop()
--pa = PulseAudio:new()
--pa:list_sinks()
--pa:subscribe_to_volume_updates(nil)
--main_loop:run()
