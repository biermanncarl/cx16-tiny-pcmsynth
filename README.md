Tiny PCM Synth
--------------

is a simple PCM synthesizer.
It generates a sweet tone from three sine waves, coated in a thin shiny
silver layer of aliasing. It is spiced up with a builtin delay effect.

To run it on the Commander X16, copy the PCMSYNTH.PRG file into the folder
where you execute the x16emu. Then enter LOAD "PCMSYNTH.PRG", and then RUN.
The instructions on how to use the synth with your keyboard should appear.

The source code is organized as follows.
All code that gets executed is contained in this source file.
Some CX16-specific addresses are retrieved from Matt Hethernan's x16.inc
A wavetable containing the sine function is in sine_8_8.inc
and the table with each MIDI note's frequency is contained in pitch_data.inc

The main program (starting at the label "start") sets up the synthesizer and
performs the keyboard polling in a loop. It also controls the parameters
that the playback algorithm uses to generate the tone.

The tone generation is performed in a custom ISR (starting at the label
"My_isr"). Blocks of 256 samples each are synthesized and pushed into the
VERA's FIFO buffer.

The oscillators function as follows. From the current phase, only the high
byte is used to read a sample. The sample from the wavetable is then scaled
down by a power of two (by right shifting) and mixed with the other
oscillators. Eventually, the phase is advanced by the amount specified in
the oscillator's frequency variable.
If the low byte overflows, the high byte is advanced by one. (by NOT using
clc in between the low and high byte addition)

The delay functions as follows:
The sample from the current buffer location is read, scaled down twice, and
mixed to the oscillator signal. The resulting signal is then fed back into
the delay buffer, and also used as output to the FIFO buffer.
The buffer location is incremented for each sample.
Each of the 256 byte blocks uses one page of memory for delay buffer.
Currently, there are 64 pages of memory used as delay buffer. They are used 
in a cyclic fashion.
