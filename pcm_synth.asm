.include "x16.inc"

.zeropage
   ; DSP variables on ZP for moar shpeeed

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

   ; controls:
   ; exit "Q"
   ; make sound quieter "A"
   ; make sound louder "S"

   ; addresses
DefaultInterruptHandler:
   .word $0000

message:
   .byte "press a to decrease volume, s to increase volume, q to quit"
end_message:


   ; handles the sound generation
MyInterruptHandler:
   ; first check if interrupt is an AFLOW interrupt
   lda VERA_isr
   and #$08
   beq @continue

   ; fill up FIFO buffer with 256 samples (not until full) -- this improves latency
   ; (the remaining latency might be due to the emulator itself)
   ldx LastSample
   lda #0
   tay
@loop:
   phy
   inx
   stx CurrentSample
   jsr ApplyVolume ; doesn't change x
   sta VERA_audio_data     ; and append it to the buffer
   ; continue until buffer is full
   ;lda VERA_audio_ctrl     ; check if buffer is full
   ;and #$80
   ;beq @loop
   ; continue until counter says it's enough
   ply
   dey
   bne @loop

   stx LastSample
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


   ; set volume to max
   lda #0
   sta VolumePowerTwo
   lda #0
   sta VolumeSubLevel

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
   ; TODO: disable other interrupts for better performance
   ; (and store which ones were activated in a variable to restore them on exit)
   lda VERA_ien
   ora #$08
   sta VERA_ien

   ; main loop ... wait until "Q" is pressed. Playback is maintained by interrupts.
mainloop:
   jsr GETIN      ; get charakter from keyboard
   cmp #81        ; exit if pressing "Q"
   beq done
   cmp #65        ; check if pressed "A": decrease Volume
   bne @continue1
   ldx VolumeSubLevel
   dex
   dex
   stx VolumeSubLevel
   bpl @continue2  ; in case VolumeSubLevel was still 0 or higher, skip ahead
   lda #8
   sta VolumeSubLevel
   inc VolumePowerTwo ; more quiet
   lda VolumePowerTwo
   cmp #MIN_VOLUME+1          ; check if minimum Volume reached
   bne @continue1
   lda #MIN_VOLUME
   sta VolumePowerTwo
   lda #0
   sta VolumeSubLevel
   jmp @continue2
@continue1:
   cmp #83        ; check if pressed "S": increase Volume
   bne @continue2
   lda VolumePowerTwo
   beq @continue2    ; skip ahead if maximum volume has been reached
   ldx VolumeSubLevel
   inx
   inx
   stx VolumeSubLevel
   txa
   cmp #10
   bne @continue2 ; in case VolumeSubLevel has not been increased to 10, skip ahead
   lda #0
   sta VolumeSubLevel
   dec VolumePowerTwo

@continue2:
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
