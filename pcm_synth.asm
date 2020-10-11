.include "x16.inc"

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

   ; controls:
   ; exit "Q"
   ; play beep "A"

   ; TODOs
   ; learn how to use AFLOW interrupt to facilitate continuous playback
   ; make playback timed
   ; reduce latency

DefaultInterruptHandler:
   .word $0000

MyInterruptHandler:
@loop:
   ; fill up FIFO buffer up to the top
   inx
   stx VERA_audio_data     ; and append it to the buffer
   lda VERA_audio_ctrl     ; check if buffer is full
   and #$80
   beq @loop
   jmp DefaultInterruptHandler


start:
   ; startup code

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
   ; fill buffer once with zeroes
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

   ; main loop ... wait until "Q" is pressed. Playback is maintained by interrupts.
mainloop:
   jsr GETIN      ; get charakter from keyboard
   cmp #81        ; exit if pressing "Q"
   beq done
   ; cmp #65        ; branch if pressing "A"
   ; bne somewhere
   jmp mainloop





playback:         ; start playback
   lda #128
   sta VERA_audio_rate

   jmp start

done:
   rts            ; return to BASIC
