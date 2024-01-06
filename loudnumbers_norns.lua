-- loudnumbers_norns
-- v0.17 @duncangeere
-- https://llllllll.co/t/51353
--
-- data sonification with Norns
--
-- K1 + E1 select data column
-- KEY 2 toggle play/pause
-- KEY 3 toggle loop
-- ENC 1 select bpm
-- ENC 2 select root note
-- ENC 3 select scale
--
-- Crow support
-- IN1 = clock
-- IN2 = play next note when a
--      trigger is received
--
-- OUT1 = note (1V/oct)
-- OUT2 = trigger
-- OUT3 = control voltage
-- OUT4 = control voltage
--
--
music = require("musicutil")
-- Import musicutil library: https://monome.org/docs/norns/reference/lib/musicutil

-- Move files to data folder if not there already
if not util.file_exists(_path.data .. "loudnumbers_norns/csv/_temperature.csv") then
    os.execute("mkdir " ..
        _path.data ..
        "loudnumbers_norns/csv/ && mv " ..
        _path.code ..
        "loudnumbers_norns/ignorethisfolder/_temperature.csv " .. _path.data .. "loudnumbers_norns/csv/_temperature.csv")
end
-- Import library to update parameters (Thanks Eigen!)
local p_option = require "core/params/option"

-- Import csv library: https://github.com/geoffleyland/lua-csv
local csv = include("lib/csv")

-- Specify csv separator (defaults to ",")
local sep = ",";

-- Import chart library:
local Graph = include("lib/lightergraph")
chart = {}       -- line chart
chart_point = {} -- highlighting active point
spacing = 2

engine.name = "PolyPerc"

-- Init grid
g = grid.connect()

-- Init midi
if midi.devices ~= nil then my_midi = midi.connect() end

function init()
    -- DEFINING SYSTEM VARIABLES
    -- Data variables

    -- placeholder data
    data = { 1, 2, 3, 4, 5, 6, 7, 8 }

    columns = {}

    -- Sound variables
    sync = 1 / 2

    -- SETTING UP
    -- Get list of file names in folder
    file_names = {}
    headers = {}
    grid_drawn = {}
    loaded = false

    list_file_names(
        function() -- this runs slowly, so we need a callback for what happens next
            params:add {
                type = "option",
                id = "column",
                name = "data column",
                options = headers,
                default = 1,
                action = function() update_data() end
            }

            -- Load the data column
            update_data()
            scale_data()

            loaded = true -- track whether data is loaded yet for UI purposes
        end)

    -- setting root note using params
    params:add {
        type = "number",
        id = "root_note",
        name = "root note",
        min = 0,
        max = 127,
        default = math.random(50, 70),
        formatter = function(param)
            return music.note_num_to_name(param:get(), true)
        end,
        action = function() build_scale() end
    } -- by employing build_scale() here, we update the scale every time the rootnote changes

    -- setting scale type using params
    scale_names = {}
    for i = 1, #music.SCALES do
        table.insert(scale_names, music.SCALES[i].name)
    end

    params:add {
        type = "option",
        id = "scale",
        name = "scale",
        options = scale_names,
        default = math.random(#scale_names),
        action = function() build_scale() end -- update the scale when it's changed
    }

    -- setting how many notes from the scale can be played
    params:add {
        type = "number",
        id = "note_pool_size",
        name = "note pool size",
        min = 1,
        max = 32,
        default = 16,
        action = function() -- update the scale when it's changed
            build_scale()
            scale_data()    -- we also need to scale the data again
        end
    }

    -- setting the whether it loops or not
    params:add {
        type = "binary",
        id = "looping",
        name = "looping",
        behavior = "toggle",
        default = 1
    }

    -- CROW
    params:add_separator("crow")

    -- Set up Crow to accept pulses
    -- setting whether crow accepts pulses or not
    params:add {
        type = "binary",
        id = "crowpulses",
        name = "accept crow pulses",
        behavior = "toggle",
        default = 0
    }

    -- Report when turned on and off
    params:set_action("crowpulses", function()
        if params:get("crowpulses") == 1 then
            print("Listening for triggers on crow IN2...")
        elseif params:get("crowpulses") == 0 then
            print("No longer listening for triggers on crow IN2.")
        end
    end)

    crow.input[2].change = crow_pulse
    crow.input[2].mode("change", 2.0, 0.25, "rising")

    -- Setting length of gates sent by crow
    params:add_control("crow_length", "crow note length (s)",
        controlspec.new(0.01, 1, "lin", 0.01, 0.05))

    -- MIDI
    params:add_separator("MIDI")

    -- Midi channel number
    params:add {
        type = "number",
        id = "midi_channel",
        name = "MIDI channel number",
        min = 1,
        max = 16,
        default = 1
    }

    -- Midi options
    params:add_binary("send_midi_notes", "Play MIDI notes?", "toggle", 1)
    params:add_binary("send_midi_cc", "Send MIDI CC?", "toggle", 0)

    -- Midi gate length
    params:add_control("midi_length", "MIDI note length (s)",
        controlspec.new(0.01, 5, "lin", 0.01, 0.1))

    params:add {
        type = "number",
        id = "midi_cc",
        name = "MIDI CC number",
        min = 0,
        max = 127,
        default = 1
    }

    params:add {
        type = "number",
        id = "midi_cc_min",
        name = "MIDI CC output min",
        min = 0,
        max = 126,
        default = 0
    }

    params:add {
        type = "number",
        id = "midi_cc_max",
        name = "MIDI CC output max",
        min = 1,
        max = 127,
        default = 127
    }


    -- DATA
    params:add_separator("data")

    -- add datamin and datamax parameters
    params:add {
        type = "number",
        id = "datamin",
        name = "data min",
        min = -999999,
        max = 999999,
        default = 0,
        action = function() -- update the scale when it's changed
            if loaded then
                scale_data()
                update_chart_axes()
            end
            screen_dirty = true
            grid_dirty = true
        end
    }
    params:add {
        type = "number",
        id = "datamax",
        name = "data max",
        min = -999999,
        max = 999999,
        default = 0,
        action = function() -- update the scale when it's changed
            if loaded then
                scale_data()
                update_chart_axes()
            end
            screen_dirty = true
            grid_dirty = true
        end
    }

    build_scale()         -- builds initial scale
    update_data_range()   -- updates the range of the data
    scale_data()          -- scales the data to the notes

    position = 1          -- Set initial position at start of data
    clock_playing = false -- whether notes are playing
    key1_down = false     -- whether key1 is depressed
    screen_dirty = true   -- track whether screen needs redrawing
    grid_dirty = true     -- track whether grid needs redrawing

    -- Start a clock to refresh the screen
    redraw_clock_id = clock.run(redraw_clock)
    redraw_grid_clock_id = clock.run(redraw_grid_clock)
end

function redraw()
    -- clear the screen
    screen.clear()

    if loaded then
        -- Redraw background chart
        chart:redraw()
        chart_point:redraw()
    end

    -- Text bits
    screen.level(15)

    screen.move(spacing + 1, 5)
    screen.text(loaded and (headers[params:get("column")]) or "loading...")

    screen.move(spacing + 1, 62)
    screen.text(clock_playing and "||" or "▶")

    screen.move(10, 62)
    screen.text((params:get("looping") == 1) and "&" or "")

    screen.move(128 - 6 - screen.text_extents(scale_names[params:get("scale")]),
        62)
    screen.text_right(music.note_num_to_name(params:get("root_note"), true))

    screen.move(128 - 2, 62)
    screen.text_right(scale_names[params:get("scale")])

    screen.move(128 - 2, 5)
    crow_dot = params:get("crowpulses") == 1 and "." or ""
    screen.text_right(crow_dot .. string.format("%.0fbpm", clock.get_tempo()))

    -- trigger a screen update
    screen.update()
end

function redraw_grid()
    -- clear the grid
    g:all(0)

    -- loop over the data and draw the bars
    for i = 1, #grid_drawn do
        -- calculate height and x positions
        local h = map(grid_drawn[i], params:get("datamin"), params:get("datamax"), 0, g.rows, true)
        h = math.ceil(h) -- round up for sub-pixel values
        local x = i
        local brightness = i == 1 and 15 or 7

        -- Light the column
        for j = 0, h do
            y = g.rows + 1 - h + j
            g:led(x, y, brightness)
        end
    end

    -- trigger a grid update
    g:refresh()
end

-- start playing the notes
function play_note()
    -- Get the note
    note = scaled_data[position]
    volts = map(note, 1, params:get("note_pool_size"), 0, 10, true)
    volts = map(data[position], params:get("datamin"), params:get("datamax"), 0, 10, true)

    -- Play note from Norns
    engine.hz(notes_freq[note])

    -- Send trigger to Crow
    crow.output[2].action = "pulse(" .. params:get('crow_length') .. ")"
    crow.output[2]() -- thanks zbs & eigen <3

    -- Output v/oct
    crow.output[1].volts = (notes_nums[note] - 48) / 12

    -- Output voltage
    crow.output[3].volts = -5 + volts
    crow.output[4].volts = volts

    -- Play midi
    if midi.devices ~= nil then
        -- If midi note is being sent, send it
        if params:get("send_midi_notes") == 1 then
            play_midi_note(notes_nums[note])
        end
        -- If midi cc is being sent, send it
        if params:get("send_midi_cc") == 1 then
            -- Calculate CC value to send
            local cc_val = math.floor(
                map(
                    data[position],
                    params:get("datamin"),
                    params:get("datamax"),
                    params:get("midi_cc_min"),
                    params:get("midi_cc_max"),
                    true
                )
            );
            -- Send it
            my_midi:cc(params:get("midi_cc"), cc_val, params:get("midi_channel"))
        end
    end
end

function crow_pulse()
    -- Check if crow should be playing
    if params:get("crowpulses") == 1 then
        play_note()
        increment_position()
    else
        -- Otherwise print an error message
        print(
            "Crow is not expecting to receieve triggers, turn it on in parameters.")
    end
end

-- stops the coroutine playing the notes
function stop_play()
    clock.cancel(play)
    if midi.devices ~= nil then my_midi:stop() end
    clock_playing = false
end

-- when a key is depressed
function key(n, z)
    -- Button 1: track whether it's pressed
    if n == 1 and z == 1 then key1_down = true end
    if n == 1 and z == 0 then key1_down = false end

    -- Button 2: play/pause and toggle accepting crow triggers if key1 is pressed
    if n == 2 and z == 1 then
        if (key1_down == true) then
            -- Toggle accepting crow triggers
            if params:get("crowpulses") == 0 then
                params:set("crowpulses", 1)
            elseif params:get("crowpulses") == 1 then
                params:set("crowpulses", 0)
            end
        elseif (key1_down == false) then
            if not clock_playing then
                if midi.devices ~= nil then my_midi:start() end
                play = clock.run(function()
                    while true do
                        -- Sync to the clock
                        clock.sync(sync)

                        -- Play a note
                        play_note()

                        -- Increment position
                        increment_position()
                    end
                end) -- starts the clock coroutine
                clock_playing = true
            elseif clock_playing then
                stop_play()
            end
        end
    end

    if n == 3 and z == 1 then
        if params:get("looping") == 0 then
            params:set("looping", 1)
        elseif params:get("looping") == 1 then
            params:set("looping", 0)
        end
    end

    screen_dirty = true
    grid_dirty = true
end

-- when an encoder is twiddled
function enc(n, d)
    -- ENC 1 select bpm when key1 is not down
    if (n == 1) and (key1_down == false) then
        params:set("clock_tempo", params:get("clock_tempo") + d)
    end

    -- ENC 1 select column when key1 is down
    if (n == 1) and (key1_down == true) then
        params:set("column", util.clamp(params:get("column") + d, 1, #headers))
    end

    -- ENC 2 select root note
    if n == 2 then params:set("root_note", params:get("root_note") + d) end

    -- ENC 3 select scale
    if n == 3 then
        params:set("scale", util.clamp(params:get("scale") + d, 1, #scale_names))
    end

    screen_dirty = true
end

-- Function to map values from one range to another
function map(n, start, stop, newStart, newStop, withinBounds)
    local value = ((n - start) / (stop - start)) * (newStop - newStart) +
        newStart

    -- // Returns basic value
    if not withinBounds then return value end

    -- // Returns values constrained to exact range
    if newStart < newStop then
        return math.max(math.min(value, newStop), newStart)
    else
        return math.max(math.min(value, newStart), newStop)
    end
end

-- Build the scale
function build_scale()
    notes_nums = music.generate_scale_of_length(params:get("root_note"),
        params:get("scale"),
        params:get("note_pool_size")) -- builds scale
    -- converts note numbers to an array of frequencies
    notes_freq = music.note_nums_to_freqs(notes_nums)
end

-- Scale the data to the pool size
function scale_data()
    scaled_data = {}

    for i = 1, #data do
        table.insert(scaled_data, math.floor(
            map(data[i], params:get("datamin"), params:get("datamax"), 1,
                params:get("note_pool_size"), true)))
    end
    grid_drawn = { table.unpack(data, 1, g.device ~= nil and g.cols or 16) }
end

-- Updates graph y-axes
function update_chart_axes()
    chart:set_y_min(params:get("datamin"))
    chart:set_y_max(params:get("datamax"))
    chart_point:set_y_min(params:get("datamin"))
    chart_point:set_y_max(params:get("datamax"))

    chart:redraw()
    chart_point:redraw()
end

-- Adds 1 to the position and resets if it gets to the end of the data
function increment_position()
    chart_point:remove_all_points()
    chart_point:add_point(position, data[position], "lin", true)

    if ((position == #data) and params:get("looping") == 1) then
        position = 1
    elseif ((position == #data) and (params:get("looping") == 0)) then
        position = 1
        stop_play()
        params:set("crowpulses", 0)
    else
        position = position + 1
    end
    grid_drawn = { table.unpack(data, position, position + 15) }

    screen_dirty = true
    grid_dirty = true
end

-- Lists out available CSV files then reloads the data
function list_file_names(callback)
    local cb = function(text)
        -- Get a list of filenames
        for line in string.gmatch(text, "/[%w%s_]+.csv") do
            name = string.sub(line, 2, -5)
            table.insert(file_names, name)
        end
        table.sort(file_names)

        -- Log to the console the csv files it's seeing
        print("CSV files found:")
        tab.print(file_names)

        -- setting the filename to use
        params:add {
            type = "option",
            id = "data file",
            name = "data filename",
            options = file_names,
            default = 1,
            action = function()
                reload_data()
                update_param_options("column", headers)
                update_data()
            end
        }

        reload_data() -- get the data
        callback()
    end

    norns.system_cmd('find ' .. _path.data ..
        'loudnumbers_norns/csv -name *.csv', cb)
end

-- Reloads the data once a new csv file is selected
function reload_data()
    print("reloading data")
    headers = {}
    columns = {}
    counter = 1;

    -- open the file
    f = csv.open(_path.data .. "loudnumbers_norns/csv/" ..
        file_names[params:get("data file")] .. ".csv",
        { separator = sep, header = true })

    -- loop through each line
    for fields in f:lines() do
        for i, v in pairs(fields) do
            -- if the header isn't already in the columns table, add it
            if columns[i] == nil then
                columns[i] = {}
                headers[counter] = i
                counter = counter + 1
            end

            -- otherwise add the data
            table.insert(columns[i], tonumber(v) ~= nil and tonumber(v) or nil)
        end
    end

    table.sort(headers)

    print("column headers found:")
    tab.print(headers)
end

-- Runs when a new column is selected and when a new csv file is selected in params
function update_data()
    print("Loading column " .. headers[params:get("column")])
    data = columns[headers[params:get("column")]]
    position = 1

    update_data_range()

    -- Define the chart
    chart = Graph.new(1, #data, "lin", params:get("datamin"), params:get("datamax"), "lin", "line", false, false)
    chart:set_position_and_size(1 + spacing, 10, 128 - (spacing * 2), 44)
    -- Add data to it
    for i = 1, #data do chart:add_point(i, data[i]) end

    -- Make a chart with a single point
    chart_point = Graph.new(1, #data, "lin", params:get("datamin"), params:get("datamax"), "lin", "point", false,
        false)
    chart_point:set_position_and_size(1 + spacing, 10, 128 - (spacing * 2), 44)
end

-- Runs in the update_data function and on initial script load
function update_data_range()
    -- calculate default min and max for the data
    dMin = math.min(table.unpack(data)) -- min of the table
    dMax = math.max(table.unpack(data)) -- max of the table
    params:set("datamin", dMin)
    params:set("datamax", dMax)
    print("dMin is now " .. params:get("datamin"))
    print("dMax is now " .. params:get("datamax"))
end

-- Updates the options of a parameter dynamically (Thanks Eigen!)
-- This is used to refresh the list of columns in the param menu
-- when a new file is selected
function update_param_options(id, options, default)
    local p_i_id = params.lookup[id]
    if p_i_id ~= nil then
        local p = params.params[p_i_id]
        local new_p = p_option.new(p_id, id, options, default)
        params.params[p_i_id] = new_p
        params:set_action(id, p.action)
    end
end

-- Check if the screen needs redrawing 15 times a second
function redraw_clock()
    while true do
        clock.sleep(1 / 15)
        if screen_dirty then
            redraw()
            screen_dirty = false
        end
    end
end

-- Check if the grid needs redrawing 10 times a second
function redraw_grid_clock()
    while true do
        clock.sleep(1 / 10)
        if grid_dirty and g.device ~= nil then
            redraw_grid()
            grid_dirty = false
        end
    end
end

-- MIDI support
function play_midi_note(midi_note)
    if midi.devices ~= nil then
        stopping = clock.run(function()
            my_midi:note_on(midi_note, 100, params:get("midi_channel"))
            clock.sleep(params:get("midi_length"))
            my_midi:note_off(midi_note, 100, params:get("midi_channel"))
        end)
    end
end
