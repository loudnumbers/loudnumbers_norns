-- loud numbers
-- data sonification with norns
-- @duncangeere
-- v0.1
--
-- KEY 1 + ENC 1 select data column 
-- KEY 2 toggle play/pause
-- KEY 3 toggle loop
-- ENC 1 select bpm
-- ENC 2 select root note
-- ENC 3 select scale
--
-- Currently only supports 
-- datasets up to 512 values
-- 
-- TODO
-- - Figure out why particularly large numbers (>1000) don't work
-- - Crow support
-- - Grid support
-- - Sonify to things that aren't 
-- pitch - amp, cutoff, FX, more
--
musicutil = require("musicutil")
-- Import musicutil library: https://monome.org/docs/norns/reference/lib/musicutil

local p_option = require "core/params/option"
-- Import library to update parameters (Thanks Eigen!)

csv = require(_path.code .. "loudnumbers/lib/csv")
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

    -- Sound variables
    sync = 1 / 2

    -- SETTING UP
    -- Get list of file names in folder
    file_names = {}
    headers = {}
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
            redraw()
        end)

    -- Create table of highlights
    highlight = {}
    for i = 1, #data do table.insert(highlight, 0) end

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

    -- clear the screen
    screen.clear()

    -- update the highlight table
    highlight = {}
    for i = 1, #data do table.insert(highlight, 0) end
    highlight[position] = 1

    -- calculate width of bars
    rectWidth = ((127 - spacing) / #data) - spacing

    -- loop over the data and draw the bars
    for i = 1, #data do

        -- calculate height and xy positions
        h = map(data[i], 0, math.max(table.unpack(data)), 0, 44, true)
        x = 1 + spacing + ((i - 1) * (rectWidth + spacing))
        y = 64 - 10 - h

        -- highlight the active datapoint
        if (highlight[i] == 1) then
            screen.level(15)
        else
            screen.level(4)
        end

        -- draw the rectangle
        screen.rect(x, y, rectWidth, h)

        -- fill the active datapoint
        if (highlight[i] == 1) then
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
        clock.sync(sync)
        redraw()
        engine.hz(notes_freq[scaled_data[position]])
        increment_position()
    end
end

-- stops the coroutine playing the notes
function stop_play()
    redraw()
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
    redraw()
end

-- when an encoder is twiddled
function enc(n, d)
    -- ENC 1 select bpm when key1 is not down
    if (n == 1) and (key1_down == false) then
        params:set("clock_tempo", params:get("clock_tempo") + d)
        redraw()
    end

    -- ENC 1 select column when key1 is down
    if (n == 1) and (key1_down == true) then
        params:set("column", util.clamp(params:get("column") + d, 1, #headers))
        redraw()
    end

    -- ENC 2 select root note
    if n == 2 then
        params:set("root_note", params:get("root_note") + d)
        redraw()
    end

    -- ENC 3 select scale
    if n == 3 then
        params:set("scale", util.clamp(params:get("scale") + d, 1, #scale_names))
        redraw()
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
                             params:get("note_pool_size"), true)))
    end
end

-- Adds 1 to the position and resets if it gets to the end of the data
-- Then updates the highlight table
function increment_position()
    if ((position == #data) and params:get("looping") == 1) then
        position = 1
    elseif ((position == #data) and (params:get("looping") == 0)) then
        position = 1
        stop_play()
    else
        position = position + 1
    end
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
    norns.system_cmd('find ' .. _path.data .. 'loudnumbers -name *.csv', cb)
end

-- Reloads the data once selected
function reload_data()
    print("reloading data")
    headers = {}
    columns = {}

    -- open the file
    f = csv.open(_path.data .. "loudnumbers/" ..
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
            table.insert(columns[i], v)
        end
    end

    print("column headers found:")
    tab.print(headers)
end

-- Runs when a new column is selected
function update_data()
    data = columns[headers[params:get("column")]]
    position = 1
    scale_data()
    redraw()
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
