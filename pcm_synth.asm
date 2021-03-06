; Tiny PCM Synth
; --------------
;
; This is a simple PCM synthesizer.
; It generates a sweet tone from three sine waves, coated in a thin shiny
; silver layer of aliasing. It is spiced up with a builtin delay effect.
;
; The source code is organized as follows.
; All code that gets executed is contained in this source file.
; Some CX16-specific addresses are retrieved from Matt Hethernan's x16.inc
; A wavetable containing the sine function is in sine_8_8.inc
; and the table with each MIDI note's frequency is contained in pitch_data.inc
;
; The main program (starting at the label "start") sets up the synthesizer and
; performs the keyboard polling in a loop. It also controls the parameters
; that the playback algorithm uses to generate the tone.
;
; The tone generation is performed in a custom ISR (starting at the label
; "My_isr"). Blocks of 256 samples each are synthesized and pushed into the
; VERA's FIFO buffer.
;
; The oscillators function as follows. From the current phase, only the high
; byte is used to read a sample. The sample from the wavetable is then scaled
; down by a power of two (by right shifting) and mixed with the other
; oscillators. Eventually, the phase is advanced by the amount specified in
; the oscillator's frequency variable.
; If the low byte overflows, the high byte is advanced by one. (by NOT using
; clc in between the low and high byte addition)
;
; The delay functions as follows:
; The sample from the current buffer location is read, scaled down twice, and
; mixed to the oscillator signal. The resulting signal is then fed back into
; the delay buffer, and also used as output to the FIFO buffer.
; The buffer location is incremented for each sample.
; Each of the 256 byte blocks uses one page of memory for delay buffer.
; Currently, there are 64 pages of memory used as delay buffer. They are used 
; in a cyclic fashion.

.include "x16.inc"


.zeropage
   ; DSP variables on ZP for moar shpeeed
my_zp_ptr:
   .word 0
csample:
   .byte 0     ; current sample
dly_sample:
   .byte 0     ; delay sample
dly_ptr:
   .word 0
freq1:
   .word 0
phase1:
   .word 0
freq2:
   .word 0
phase2:
   .word 0
freq3:
   .word 0
phase3:
   .word 0


.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

Default_isr:
   .word $0000

message:
   .byte $0D, "controls", $0D
   .byte "--------", $0D, $0D
   .byte "a,w,s,...   play notes", $0D
   .byte "z,x         toggle octaves", $0D
   .byte "space       stop note", $0D
   .byte "q           quit", $0D
end_message:

   ; keyboard values
Octave:
   .byte 60
Note:
   .byte 0
Frequency:
   .word 0
OFFSET = 0

   ; oscillator 2 detuning
DETUNING = 4
   ; oscillator 3 pitch offset
OSC3_OFFSET = 12  

   ; delay memory locations (only MSB are read. assumes whole pages are available)
DLY_BUFFER_START = $0E00
DLY_BUFFER_END   = $4DFF   ; that's 16 kB ... yessss! :-D


   ; handles the sound generation
My_isr:
   ; first check if interrupt is an AFLOW interrupt
   lda VERA_isr
   and #$08
   bne @do_fillup
   jmp @end_aflow

@do_fillup:
   ; fill up FIFO buffer with 256 samples (not until full) -- this improves latency
   ; (the remaining latency might be due to the emulator itself)
   ; register y serves both as counter in the current 256 sample frame
   ; and as offset in the delay buffer.
   lda #0
   tay
@loop:

   ; Oscillator 1 (1/2 volume)
   ldx phase1+1
   lda full_sine_8_8, x
   bmi @osc1_minus
   lsr
   jmp @osc1_continue
@osc1_minus:
   sec
   ror
@osc1_continue:
   sta csample
   ; advance phase
   ; LSB first, then MSB
   lda freq1
   clc
   adc phase1
   sta phase1
   lda freq1+1
   adc phase1+1
   sta phase1+1
   ; Oscillator 1: roughly 40 cycles


   ; Oscillator 2 (1/4 volume)
   ldx phase2+1
   lda full_sine_8_8, x
   bmi @osc2_minus
   lsr
   lsr
   jmp @osc2_continue
@osc2_minus:
   sec
   ror
   sec
   ror
@osc2_continue:
   clc
   adc csample
   sta csample
   ; advance phase
   ; LSB first, then MSB
   lda freq2
   clc
   adc phase2
   sta phase2
   lda freq2+1
   adc phase2+1
   sta phase2+1
   ; Oscillator 2: roughly 44 cycles

   ; Oscillator 3 (1/8 volume)
   ldx phase3+1
   lda full_sine_8_8, x
   bmi @osc3_minus
   lsr
   lsr
   lsr
   jmp @osc3_continue
@osc3_minus:
   sec
   ror
   sec
   ror
   sec
   ror
@osc3_continue:
   clc
   adc csample
   sta csample
   ; advance phase
   ; LSB first, then MSB
   lda freq3
   clc
   adc phase3
   sta phase3
   lda freq3+1
   adc phase3+1
   sta phase3+1
   ; Oscillator 3: roughly 48 cycles

   ; delay effect
   ; first, read sample and mix it with current signal
   ; then feed it back into the buffer
   ; the feedback signal is reduced by factor 1/4 (-6dB) before mixing with oscillator signal
   lda (dly_ptr),y
   bmi @dly_minus
   lsr
   lsr
   jmp @dly_continue
@dly_minus:
   sec
   ror
   sec
   ror
@dly_continue:
   clc
   adc csample
   ; sample is done, store it in feedback buffer
   sta (dly_ptr),y  
   ; and to the FIFO buffer
   sta VERA_audio_data


   ; continue until counter says it's enough
   iny
   bne @loop

   ; advance the delay buffer
   ldx dly_ptr+1
   cpx #>DLY_BUFFER_END
   bne @dly_advance
   ; rewind
   lda #>DLY_BUFFER_START
   sta dly_ptr+1
   jmp @end_aflow
@dly_advance:
   inc dly_ptr+1

@end_aflow:
   ; call default interrupt handler
   ; for keyboard service
   jmp (Default_isr)




start:
   ; startup code
   ; print message
   lda #<message
   sta my_zp_ptr
   lda #>message
   sta my_zp_ptr+1
   ldy #0
@loop_msg:
   cpy #(end_message-message)
   beq @done_msg
   lda (my_zp_ptr),y
   jsr CHROUT
   iny
   bra @loop_msg
@done_msg:

   ; Mute Oscillators 1, 2 and 3
   lda #0
   sta freq1+1
   sta freq1
   sta freq2+1
   sta freq2
   sta freq3+1
   sta freq3

   ; Initialize delay
   lda #<DLY_BUFFER_START
   sta dly_ptr
   lda #>DLY_BUFFER_END
   sta dly_ptr+1

   ; copy address of default interrupt handler
   lda IRQVec
   sta Default_isr
   lda IRQVec+1
   sta Default_isr+1
   ; replace irq handler
   sei            ; block interrupts
   lda #<My_isr
   sta IRQVec
   lda #>My_isr
   sta IRQVec+1
   cli            ; allow interrupts

   ; prepare playback
   lda #$8F       ; reset PCM buffer, 8 bit mono, max volume
   sta VERA_audio_ctrl

   lda #0         ; set playback rate to zero
   sta VERA_audio_rate
   tax            ; initial audio sample

   ; fill buffer once
   lda #0
   tax
@loop:
   stx VERA_audio_data     ; and append it to the buffer
   lda VERA_audio_ctrl     ; check if buffer is full
   and #$80
   beq @loop

   ; start playback
   lda #64
   sta VERA_audio_rate

   ; enable AFLOW interrupt
   ; TODO: disable other interrupts for better performance
   ; (and store which ones were activated in a variable to restore them on exit)
   lda VERA_ien
   ora #$08
   sta VERA_ien

   ; main loop ... wait until "Q" is pressed. Playback is maintained by ISR.
mainloop:
   jsr GETIN      ; get charakter from keyboard
   cmp #65        ; check if pressed "A"
   bne @skip_a
   jmp @keyboard_a
@skip_a:
   cmp #87        ; check if pressed "W"
   bne @skip_w
   jmp @keyboard_w
@skip_w:
   cmp #83        ; check if pressed "S"
   bne @skip_s
   jmp @keyboard_s
@skip_s:
   cmp #69        ; check if pressed "E"
   bne @skip_e
   jmp @keyboard_e
@skip_e:
   cmp #68        ; check if pressed "D"
   bne @skip_d
   jmp @keyboard_d
@skip_d:
   cmp #70        ; check if pressed "F"
   bne @skip_f
   jmp @keyboard_f
@skip_f:
   cmp #84        ; check if pressed "T"
   bne @skip_t
   jmp @keyboard_t
@skip_t:
   cmp #71        ; check if pressed "G"
   bne @skip_g
   jmp @keyboard_g
@skip_g:
   cmp #89        ; check if pressed "Y"
   bne @skip_y
   jmp @keyboard_y
@skip_y:
   cmp #72        ; check if pressed "H"
   bne @skip_h
   jmp @keyboard_h
@skip_h:
   cmp #85        ; check if pressed "U"
   bne @skip_u
   jmp @keyboard_u
@skip_u:
   cmp #74        ; check if pressed "J"
   bne @skip_j
   jmp @keyboard_j
@skip_j:
   cmp #75        ; check if pressed "K"
   bne @skip_k
   jmp @keyboard_k
@skip_k:
   cmp #79        ; check if pressed "O"
   bne @skip_o
   jmp @keyboard_o
@skip_o:
   cmp #76        ; check if pressed "L"
   bne @skip_l
   jmp @keyboard_l
@skip_l:
   cmp #32        ; check if pressed "SPACE"
   bne @skip_space
   jmp @keyboard_off
@skip_space:
   cmp #90        ; check if pressed "Z"
   bne @skip_z
   jmp @keyboard_z
@skip_z:
   cmp #88        ; check if pressed "X"
   bne @skip_x
   jmp @keyboard_x
@skip_x:
   cmp #81        ; exit if pressing "Q"
   bne @end_keychecks
   jmp done
@end_keychecks:
   jmp @end_mainloop

@keyboard_a:
   lda #0
   jmp @play_note
@keyboard_w:
   lda #1
   jmp @play_note
@keyboard_s:
   lda #2
   jmp @play_note
@keyboard_e:
   lda #3
   jmp @play_note
@keyboard_d:
   lda #4
   jmp @play_note
@keyboard_f:
   lda #5
   jmp @play_note
@keyboard_t:
   lda #6
   jmp @play_note
@keyboard_g:
   lda #7
   jmp @play_note
@keyboard_y:
   lda #8
   jmp @play_note
@keyboard_h:
   lda #9
   jmp @play_note
@keyboard_u:
   lda #10
   jmp @play_note
@keyboard_j:
   lda #11
   jmp @play_note
@keyboard_k:
   lda #12
   jmp @play_note
@keyboard_o:
   lda #13
   jmp @play_note
@keyboard_l:
   lda #14
   jmp @play_note
@keyboard_off:
   lda #0
   sta freq1
   sta freq1+1
   sta freq2
   sta freq2+1
   sta freq3
   sta freq3+1
   ; TODO: reset phase?
   jmp @end_mainloop
@keyboard_z:
   lda Octave
   beq @end_mainloop
   sec
   sbc #12
   sta Octave
   jmp @end_mainloop
@keyboard_x:
   lda Octave
   cmp #108
   beq @end_mainloop
   clc
   adc #12
   sta Octave
   jmp @end_mainloop

@play_note:
   ; determine MIDI note
   sta Note
   lda Octave
   clc
   adc Note
   adc #OFFSET
   ; multiply by 2 to get memory address of frequency data
   asl
   tax

   ; set oscillator 1 and 2 frequencies (inclusive osc 2 detuning)
   lda pitch_data,x
   sta freq1
   clc
   adc #DETUNING
   sta freq2
   inx
   lda pitch_data,x
   sta freq1+1
   adc #0   ; add carry flag from earlier
   sta freq2+1
   ; set oscillator 3 frequencies
   txa
   clc
   adc #(OSC3_OFFSET*2-1)
   tax
   lda pitch_data,x
   sta freq3
   inx
   lda pitch_data,x
   sta freq3+1
@end_mainloop:
   ;lda LastSample
   ;jsr CHROUT

   jmp mainloop


done:
   ; stop playback
   lda #0
   sta VERA_audio_rate

   ; restore interrupt handler
   sei            ; block interrupts
   lda #<Default_isr
   sta IRQVec
   lda #>Default_isr
   sta IRQVec+1
   cli            ; allow interrupts

   ; reset FIFO buffer
   lda #$8F
   sta VERA_audio_ctrl

   ; disable AFLOW interrupt
   lda VERA_ien
   and #$F7
   sta VERA_ien

   rts            ; return to BASIC
   ; NOTE
   ; The program gets corrupted in memory after returning to BASIC
   ; If running again, reLOAD the program!

.include "sine_8_8.inc"
.include "pitch_data.inc"