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

   ; controls:
   ; exit "Q"

   ; addresses
DefaultInterruptHandler:
   .word $0000

message:
   .byte "use keyboard (a,w,s,...) to play, press q to quit"
end_message:


   ; handles the sound generation
MyInterruptHandler:
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








   ; continue until buffer is full
   ;lda VERA_audio_ctrl     ; check if buffer is full
   ;and #$80
   ;beq @loop
   ; continue until counter says it's enough
   dex
   bne @loop

@continue:
   ; call default interrupt handler
   ; for keyboard service
   jmp (DefaultInterruptHandler)




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
   ; print newline
   lda #$0D ; newline
   jsr CHROUT

   ; Set Oscillator 1 frequency
   lda #1
   sta freq1+1
   lda #128
   sta freq1
   ; Set Oscillator 2 frequency
   lda #1
   sta freq2+1
   lda #125
   sta freq2

   ; copy address of default interrupt handler
   lda IRQVec
   sta DefaultInterruptHandler
   lda IRQVec+1
   sta DefaultInterruptHandler+1
   ; replace irq handler
   sei            ; block interrupts
   lda #<MyInterruptHandler
   sta IRQVec
   lda #>MyInterruptHandler
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
   inx
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

   ; main loop ... wait until "Q" is pressed. Playback is maintained by interrupts.
mainloop:
   jsr GETIN      ; get charakter from keyboard
   cmp #65        ; check if pressed "A"
   beq @keyboard_a
   cmp #87        ; check if pressed "W"
   beq @keyboard_w
   cmp #83        ; check if pressed "S"
   beq @keyboard_s
   cmp #69        ; check if pressed "E"
   beq @keyboard_e
   cmp #68        ; check if pressed "D"
   beq @keyboard_d
   cmp #70        ; check if pressed "F"
   beq @keyboard_f
   cmp #84        ; check if pressed "T"
   beq @keyboard_t
   cmp #71        ; check if pressed "G"
   beq @keyboard_g
   cmp #89        ; check if pressed "Y"
   beq @keyboard_z
   cmp #72        ; check if pressed "H"
   beq @keyboard_h
   cmp #85        ; check if pressed "U"
   beq @keyboard_u
   cmp #74        ; check if pressed "J"
   beq @keyboard_j
   cmp #75        ; check if pressed "K"
   beq @keyboard_k
   cmp #79        ; check if pressed "O"
   beq @keyboard_o
   cmp #76        ; check if pressed "L"
   beq @keyboard_l
   cmp #81        ; exit if pressing "Q"
   beq done
   jmp @continue1

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
@keyboard_z:
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

@play_note:
   sta freq1+1
   sta freq2+1
@continue1:
   ;lda LastSample
   ;jsr CHROUT

   jmp mainloop


done:
   ; stop playback
   lda #0
   sta VERA_audio_rate

   ; restore interrupt handler
   sei            ; block interrupts
   lda #<DefaultInterruptHandler
   sta IRQVec
   lda #>DefaultInterruptHandler
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


.include "sine_8_8.inc"