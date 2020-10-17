.include "x16.inc"


.zeropage
   ; DSP variables on ZP for moar shpeeed
my_zp_ptr:
   .word 0
csample:
   .byte 0     ; current sample
freq1:
   .word 0
phase1:
   .word 0
freq2:
   .word 0
phase2:
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
DETUNING = 3


   ; handles the sound generation
My_isr:
   ; first check if interrupt is an AFLOW interrupt
   lda VERA_isr
   and #$08
   beq @continue

   ; fill up FIFO buffer with 256 samples (not until full) -- this improves latency
   ; (the remaining latency might be due to the emulator itself)
   lda #0
   tax
@loop:

   ; Oscillator 1 (1/2 volume)
   ldy phase1+1
   lda full_sine_8_8, y
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


   ; Oscillator 2 (1/4 volume)
   ldy phase2+1
   lda full_sine_8_8, y
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


   lda csample
   sta VERA_audio_data     ; and append it to the buffer


   ; continue until counter says it's enough
   dex
   bne @loop

@continue:
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

   ; Set Oscillator 1 frequency
   lda #0
   sta freq1+1
   lda #0
   sta freq1
   ; Set Oscillator 2 frequency
   lda #0
   sta freq2+1
   lda #0
   sta freq2

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
   lda #128
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

   ; acquire frequency (and set osc 2 detuning)
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