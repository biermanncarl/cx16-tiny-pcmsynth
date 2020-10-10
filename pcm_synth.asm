.include "x16.inc"

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

start:
   ; very basic audio "hello world"
   lda #$8F       ; reset PCM buffer, 8 bit mono, max volume
   sta VERA_audio_ctrl

   lda #0         ; set playback rate to zero
   sta VERA_audio_rate
   tax            ; initial audio sample

loop:
   inx
   stx VERA_audio_data     ; and append it to the buffer
   lda VERA_audio_ctrl     ; check if buffer is full
   and #$80
   beq loop

playback:
   lda #128
   sta VERA_audio_rate

done:
   rts            ; return to BASIC
