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

LastSample:
   .byte $00

DefaultInterruptHandler:
   .word $0000

MyInterruptHandler:
   ; first check if interrupt is an AFLOW interrupt
   lda VERA_isr
   and #$08
   beq @continue

   ; fill up FIFO buffer up to the top
   ldx LastSample
@loop:
   inx
   stx VERA_audio_data     ; and append it to the buffer
   ; continue until buffer is full
   lda VERA_audio_ctrl     ; check if buffer is full
   and #$80
   beq @loop

   stx LastSample
@continue:
   ; call default interrupt handler
   ; for keyboard service
   jmp (DefaultInterruptHandler)


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
   ; fill buffer once
   lda #0
   tax
@loop:
   inx
   stx VERA_audio_data     ; and append it to the buffer
   lda VERA_audio_ctrl     ; check if buffer is full
   and #$80
   beq @loop
   stx LastSample

   ; start playback
   lda #128
   sta VERA_audio_rate

   ; enable AFLOW interrupt
   lda VERA_ien
   ora #$08
   sta VERA_ien

   ; main loop ... wait until "Q" is pressed. Playback is maintained by interrupts.
mainloop:
   jsr GETIN      ; get charakter from keyboard
   cmp #81        ; exit if pressing "Q"
   beq done
   ; cmp #65        ; branch if pressing "A"
   ; bne somewhere

   lda LastSample
   jsr CHROUT

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
   ; NOTE: the binary program will be destroyed once returned to BASIC
   ; and needs to be loaded again in order to run properly.
