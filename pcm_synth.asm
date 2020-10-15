.include "x16.inc"


.zeropage
   ; DSP variables on ZP for moar shpeeed
LastSample:
   .byte $00
CurrentSample:
   .byte $00
Negative:            ; stores whether current sample is negative
   .byte $00
VolumePowerTwo:      ; how many RSHIFTs should be applied (0-8)
   .byte $00
VolumeSubLevel:      ; upscaling to which sublevel (0 to 4)  (that is: 0,2,4,6 or 8)
   .byte $00

MIN_VOLUME = 5

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

JumpAddress:
   .word $0000

   ; address tables to subroutines which do intermediate scaling
VolumeSublevelTablePositive:       
   .word VHPos0
   .word VHPos1
   .word VHPos2
   .word VHPos3
   .word VHPos4
VolumeSublevelTableNegative:
   .word VHNeg0
   .word VHNeg1
   .word VHNeg2
   .word VHNeg3
   .word VHNeg4





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







   ; takes a sample in a and applies volume scaling
   ; returns scaled sample in a
   ; preserves register x
   ; volume scaling can be performed with negative powers of 2
   ; and 4 sublevels between two integer powers of 2
ApplyVolume:
   lda CurrentSample
   bmi AV_negative        ; branch if sample is negative
   ; positive sample
   ; perform RSHIFTs
   ldy VolumePowerTwo
   beq @continue1       ; 12 cycles
@loop1:
   lsr
   dey
   bne @loop1           ; max 55 cycles + 12 cycles = 67 cycles
@continue1:
   sta CurrentSample
   ; call sublevel scaling
   ; copy the correct address to indirect jump location
   ldy VolumeSubLevel
   lda VolumeSublevelTablePositive,Y
   sta JumpAddress
   iny
   lda VolumeSublevelTablePositive,Y
   sta JumpAddress+1
   lda CurrentSample
   jmp (JumpAddress)
VolumeReturnPositive:
   ; sta CurrentSample
   rts ; return in a

AV_negative:
   ; negative sample
   ; perform RSHIFTs
   ldy VolumePowerTwo
   beq @continue2       ; 13 cycles
@loop2:
   sec                  
   ror
   dey
   bne @loop2
@continue2:             ; max 71 cycles + 13 cycles = 84 cycles
   ; call sublevel scaling
   ; copy the correct address to indirect jump location
   sta CurrentSample
   ldy VolumeSubLevel
   lda VolumeSublevelTableNegative,Y
   sta JumpAddress
   iny
   lda VolumeSublevelTableNegative,Y
   sta JumpAddress+1
   lda CurrentSample
   jmp (JumpAddress)
VolumeReturnNegative:
   ; sta CurrentSample 
   rts ; return in a



   ; create volume sublevels. expects sample in accumulator
VHPos0:
   jmp VolumeReturnPositive ; 5 cycles

VHPos1:
   sta CurrentSample
   lsr
   lsr
   lsr
   clc
   adc CurrentSample
   jmp VolumeReturnPositive ; 21 cycles

VHPos2:
   sta CurrentSample
   lsr
   lsr
   clc
   adc CurrentSample
   jmp VolumeReturnPositive ; 19 cycles

VHPos3:
   sta CurrentSample
   lsr
   clc
   adc CurrentSample
   jmp VolumeReturnPositive ; 17 cycles

VHPos4:
   sta CurrentSample
   lsr
   tay
   clc
   adc CurrentSample
   sta CurrentSample
   tya
   lsr
   clc
   adc CurrentSample
   jmp VolumeReturnPositive ; 33 cycles

VHNeg0:
   jmp VolumeReturnNegative ; 5 cycles

VHNeg1:
   sta CurrentSample
   sec
   ror
   sec
   ror
   sec
   ror
   clc
   adc CurrentSample
   jmp VolumeReturnNegative ; 27 cycles

VHNeg2:
   sta CurrentSample
   sec
   ror
   sec
   ror
   clc
   adc CurrentSample
   jmp VolumeReturnNegative ; 23 cycles

VHNeg3:
   sta CurrentSample
   sec
   ror
   clc
   adc CurrentSample
   jmp VolumeReturnNegative ; 19 cycles

VHNeg4:
   sta CurrentSample
   sec
   ror
   tay
   clc
   adc CurrentSample
   sta CurrentSample
   tya
   sec
   ror
   clc
   adc CurrentSample
   jmp VolumeReturnNegative ; 37 cycles













start:
   ; startup code

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
   ; NOTE: the binary program will be destroyed once returned to BASIC
   ; and needs to be loaded again in order to run properly.
