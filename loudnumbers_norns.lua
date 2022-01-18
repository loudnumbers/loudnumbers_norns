-- loudnumbers_norns
-- v0.12 @duncangeere
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
-- OUT1 = note (1V/oct)
-- OUT2 = trigger
-- 
-- TODO
-- - Preserve ordering of columns
-- - Grid support
-- - Sonify to things that aren't 
-- pitch - amp, cutoff, FX, more
--
musicutil = require("musicutil")
-- Import musicutil library: https://monome.org/docs/norns/reference/lib/musicutil

local p_option = require "core/params/option"
-- Import library to update parameters (Thanks Eigen!)

csv = require(_path.code .. "loudnumbers_norns/lib/csv")
-- Import csv library: https://github.com/geoffleyland/lua-csv

engine.name = "PolyPerc"

function init()

    -- DEFINING SYSTEM VARIABLES
    -- Data variables

    -- placeholder data
    data = {1, 2, 3, 4, 5, 6, 7, 8}

    columns = {}

    -- Visual variables
    spacing = 2 -- spacing between bars
    rectWidth = ((127 - spacing) / 16) - spacing

    -- Sound variables
    sync = 1 / 2

    -- SETTING UP
    -- Get list of file names in folder
    file_names = {}
    headers = {}
    drawn = {}
    loaded = false

    list_file_names(
        function() -- this runs slowly, so we need a callback for what happens next

            params:add{
                type = "option",
                id = "column",
                name = "data column",
                options = headers,
                default = 1,
                action = function() update_data() end
            }

            -- Load the data column
            update_data()

            loaded = true -- track whether data is loaded yet for UI purposes

            -- Start a clock to redraw the screen 10 times a second
            clock.run(function()
                while true do
                    clock.sleep(1 / 10)
                    redraw()
                end
            end)
        end)

    -- setting root note using params
    params:add{
        type = "number",
        id = "root_note",
        name = "root note",
        min = 0,
        max = 127,
        default = math.random(50, 70),
        formatter = function(param)
            return musicutil.note_num_to_name(param:get(), true)
        end,
        action = function() build_scale() end
    } -- by employing build_scale() here, we update the scale

    -- setting scale type using params
    scale_names = {}
    for i = 1, #musicutil.SCALES do
        table.insert(scale_names, musicutil.SCALES[i].name)
    end

    params:add{
        type = "option",
        id = "scale",
        name = "scale",
        options = scale_names,
        default = math.random(#scale_names),
        action = function() build_scale() end -- update the scale when it's changed
    }

    -- setting how many notes from the scale can be played
    params:add{
        type = "number",
        id = "note_pool_size",
        name = "note pool size",
        min = 1,
        max = 32,
        default = 16,
        action = function() -- update the scale when it's changed
            build_scale()
            scale_data()
        end
    }

    -- Setting length of gates sent by crow
    params:add{
        type = "number",
        id = "crow_gate",
        name = "crow gate length",
        min = 0.01,
        max = 0.50,
        default = 0.01
    }

    -- setting the whether it loops or not
    params:add{
        type = "binary",
        id = "looping",
        name = "looping",
        behavior = "toggle",
        default = 1
    }

    build_scale() -- builds initial scale
    scale_data() -- scales the data to the notes

    position = 1 -- Set initial position at start of data
    playing = false -- whether notes are playing
    key1_down = false -- whether key1 is depressed

end

function redraw()

    clock.sync(sync)

    -- clear the screen
    screen.clear()

    -- loop over the data and draw the bars
    for i = 1, #drawn do

        -- calculate height and xy positions
        h = map(drawn[i], dMin, dMax, 0, 44)
        x = 1 + spacing + ((i - 1) * (rectWidth + spacing))
        y = 64 - 10 - h

        -- highlight the active datapoint
        if (i == 1) then
            screen.level(15)
        else
            screen.level(4)
        end

        -- draw the rectangle (making height 1 if it's 0)
        screen.rect(x, y, rectWidth, h > 0 and h or 1)

        -- fill the active datapoint
        if (i == 1) then
            screen.fill()
        else
            screen.stroke()
        end

    end

    -- Text bits
    screen.level(15)

    screen.move(spacing + 1, 5)
    screen.text(loaded and (headers[params:get("column")]) or "loading...")

    screen.move(spacing + 1, 62)
    screen.text(playing and "||" or "▶")

    screen.move(10, 62)
    screen.text((params:get("looping") == 1) and "&" or "")

    screen.move(128 - 6 - screen.text_extents(scale_names[params:get("scale")]),
                62)
    screen.text_right(musicutil.note_num_to_name(params:get("root_note"), true))

    screen.move(128 - 2, 62)
    screen.text_right(scale_names[params:get("scale")])

    screen.move(128 - 2, 5)
    screen.text_right(string.format("%.0fbpm", clock.get_tempo()))

    -- trigger a screen update
    screen.update()
end

-- start playing the notes
function play_notes()
    while true do
        -- Sync to the clock
        clock.sync(sync)

        -- Get the note
        note = scaled_data[position]
        volts = map(note, 1, params:get("note_pool_size"), 0, 10, true)
        -- Play note from Norns
        engine.hz(notes_freq[note])
        -- Send trigger to Crow
        crow "output[1](pulse(0.05))"
        -- Output v/oct
        crow.output[2].volts = (notes_nums[note] - 48) / 12
        -- Output voltage
        crow.output[3].volts = volts
        crow.output[4].volts = volts

        increment_position()
    end
end

-- stops the coroutine playing the notes
function stop_play()
    clock.cancel(play)
    playing = false
end

-- when a key is depressed
function key(n, z)

    -- Button 1: track whether it's pressed
    if n == 1 and z == 1 then key1_down = true end

    if n == 1 and z == 0 then key1_down = false end

    -- Button 2: play/pause
    if n == 2 and z == 1 then
        if not playing then
            play = clock.run(play_notes) -- starts the clock coroutine
            playing = true
        elseif playing then
            stop_play()
        end
    end

    if n == 3 and z == 1 then
        if params:get("looping") == 0 then
            params:set("looping", 1)
        elseif params:get("looping") == 1 then
            params:set("looping", 0)
        end
    end
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
    notes_nums = musicutil.generate_scale_of_length(params:get("root_note"),
                                                    params:get("scale"),
                                                    params:get("note_pool_size")) -- builds scale
    notes_freq = musicutil.note_nums_to_freqs(notes_nums) -- converts note numbers to an array of frequencies
end

-- Scale the data to the pool size
function scale_data()
    scaled_data = {}
    dMin = math.min(table.unpack(data)) -- min of the table
    dMax = math.max(table.unpack(data)) -- max of the table
    for i = 1, #data do
        table.insert(scaled_data, math.floor(
                         map(data[i], dMin, dMax, 1,
                             params:get("note_pool_size"))))
    end
    drawn = {table.unpack(data, 1, 16)}
end

-- Adds 1 to the position and resets if it gets to the end of the data
function increment_position()
    if ((position == #data) and params:get("looping") == 1) then
        position = 1
    elseif ((position == #data) and (params:get("looping") == 0)) then
        position = 1
        stop_play()
    else
        position = position + 1
    end
    drawn = {table.unpack(data, position, position + 15)}
end

-- Lists out available CSV files then reloads the data
function list_file_names(callback)
    local cb = function(text)
        -- Get a list of filenames
        for line in string.gmatch(text, "/[%w%s]+.csv") do
            name = string.sub(line, 2, -5)
            table.insert(file_names, name)
        end
        table.sort(file_names)

        -- Log to the console the csv files it's seeing
        print("CSV files found:")
        tab.print(file_names)

        -- setting the filename to use
        params:add{
            type = "option",
            id = "filename",
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
    norns.system_cmd('find ' .. _path.code ..
                         'loudnumbers_norns/data -name *.csv', cb)
end

-- Reloads the data once selected
function reload_data()
    print("reloading data")
    headers = {}
    columns = {}

    -- open the file
    f = csv.open(_path.code .. "loudnumbers_norns/data/" ..
                     file_names[params:get("filename")] .. ".csv",
                 {separator = ",", header = true})

    -- loop through each line
    for fields in f:lines() do
        for i, v in pairs(fields) do

            -- if the header isn't already in the columns table, add it
            if columns[i] == nil then
                columns[i] = {}
                table.insert(headers, i)
            end

            -- otherwise add the data
            table.insert(columns[i], tonumber(v) ~= nil and tonumber(v) or 0)
        end
    end

    print("column headers found:")
    tab.print(headers)
end

-- Runs when a new column is selected
function update_data()
    print("Loading column " .. headers[params:get("column")])
    data = columns[headers[params:get("column")]]
    dMin = math.min(table.unpack(data)) -- min of the table
    dMax = math.max(table.unpack(data)) -- max of the table
    position = 1
    scale_data()
end

-- Updates the options of a parameter dynamically (Thanks Eigen!)
function update_param_options(id, options, default)
    local p_i_id = params.lookup[id]
    if p_i_id ~= nil then
        local p = params.params[p_i_id]
        -- tab.print(p) -- for debugging
        local new_p = p_option.new(p_id, id, options, default)
        params.params[p_i_id] = new_p
        params:set_action(id, p.action)
    end
end
