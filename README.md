# Loud Numbers

Loud Numbers is a [data sonification](https://en.wikipedia.org/wiki/Sonification) script for Norns. It turns .csv files into melodies and control voltages.

You can select the root note and scale with encoders 2 and 3. Encoder 1 selects the bpm. Key 2 toggles play/pause, and key 3 toggles whether the melody should loop when you reach the end of the dataset or not.

The script comes with a default set of data - temperature.csv, which contains global temperature anomalies since 1950 for the globe, tropics, and northern and southern hemispheres, via [Our World in Data](https://ourworldindata.org/grapher/temperature-anomaly?time=1950..2019&country=~Global). Swap between data columns by turning encoder 1 while holding down key 1. Selecting a new data column will reset the sequence.

## Requirements

Monome Norns or Norns Shield

## Instructions

Place data files in the /data folder - the same folder as temperatures.csv. Once you've loaded your file, restart the script and select it through the parameters menu.

- KEY 2: toggle play/pause
- KEY 3: toggle loop
- ENC 1: select bpm
- ENC 2: select root note
- ENC 3: select scale

- KEY 1 + ENC 1: select data column
- KEY 1 + KEY 2: listen for triggers in Crow's IN2 port

## Crow support

- OUT1 = note (1V/oct)
- OUT2 = trigger out
- OUT3 = data value scaled to -5V-5V
- OUT4 = data value scaled to 0V-10V

- IN2 = play next note when a trigger is receieved

Note: Crow trigger support must be turned on in the parameters menu, or by holding KEY1 and pressing KEY2.

When looping is turned off (KEY3), Crow trigger support will automatically deactivate when you reach the end of your dataset and you'll need to turn it on again.

## Tips

- The script assumes that your .csv file has headers. If it doesn't, it'll read the first row of data as headers.
- The script is a little fragile at the moment. Don't feed it anything too weird. If it breaks, please let me know (attach the CSV you're using) and I'll try to figure out why.
- Looking for some data to sonify? [Step this way](https://docs.google.com/spreadsheets/d/1wZhPLMCHKJvwOkP4juclhjFgqIY8fQFMemwKL2c64vk/edit#gid=0).

## Changelog

### v0.14

- Connect a grid and get a visualization of your data. 
- Should support grids of any size and hot-plugging, but let me know if you run into difficulties.

### v0.13

- Loud Numbers now accepts triggers receieved in Crow's IN2 port to advance notes.
- Crow input monitoring must be toggled on in the parameters menu or by holding KEY1 and pressing KEY2.
- When looping is turned off (KEY3), Crow trigger support will automatically deactivate when you reach the end of your dataset and you'll need to turn it on again.
- Bar rendering has been tweaked slightly to improve display of small values.
- The screen now only redraws when something has changed.
- Crow OUT3 now scales from -5V to 5V, rather than 0V to 10V. OUT4 still scales from 0V to 10V.

### v0.12

- The screen now shows just 16 bars at a time, with the leftmost bar being the one that's being played. This solves the problem of displaying too many bars on the screen, and also paves the way for adding visualization on Grid.
- The screen redraw function is now detached from the main clock. It runs at a constant 10fps. This helps with some display timing issues that were annoying me and simplifies the code a little.

### v0.11

- Added basic crow support

### v0.1

- Initial release

## Loud Numbers?

It's the name of my [data sonification podcast](https://www.loudnumbers.net/). Worth a listen if you want to see what's possible with sonification.
