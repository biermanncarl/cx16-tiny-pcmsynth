; PCM Sawtooth With Volume Control Demo
; -------------------------------------
;
; This program plays back a sawtooth waveform which can be controlled via the
; keyboard. Press "A" for decreasing volume, "S" for increasing volume and "Q"
; to quit.
; The main program sets up a custom interrupt handler that handles the AFLOW
; interrupt and passes on to the default interrupt handler.
; The main program also checks the keyboard input and performs actions
; accordingly, mainly increase and decrease of volume.
; The interrupt handler creates a sawtooth waveform by continuusly increasing
; a byte in each cycle. This byte is then used as input for a volume scaling
; algorithm.
; Since the 6502 has no intrinsic multiplication algorithm, multiplication is
; always computationally expensive, especially for two's complement numbers,
; in this demo, there is an alternative approach to do volume scaling, which
; tries to be computationally more feasible than the general two's complement
; multiplication approach.
;
; The volume scaling is performed in two steps.
; The first step scales the signal down by a negative power of two. This is
; achieved by simply right shifting the signal.
; The second step scales the signal up to one of five logarithmically spaced
; sub-levels.
; The result is a nearly seamless volume scaling, except for the artifacts
; resulting from the 8-bit precision.
;
; This sub-level method in details:
; By simple right-shifting, we can approximate the multiplication of the signal
; with negative powers of two.
; The goal of the sub-level method is to fill in this relatively coarse set of
; possible volumes. It adds four sub-level between each pair of powers of two.
; The idea is as follows. We approximate the following numbers
; 2^0     = 1.00          = 1.000(binary)
; 2^(1/5) = 1.15 ~= 1.125 = 1.001(binary)
; 2^(2/5) = 1.32 ~= 1.25  = 1.010(binary)
; 2^(3/5) = 1.52 ~= 1.5   = 1.100(binary)
; 2^(4/5) = 1.74 ~= 1.75  = 1.110(binary)
; Since multiplication with one of these numbers is easy, we can select one of
; these sub-levels and perform a hard-coded multiplication with one of these
; binary approximations of powers of 2^(1/5).
;
; In order to understand how this multiplication works, consider the case of
; multiplication with 2^(1/5) ~= 1.125.
; First, we take the original sample, and make a copy of it, to use it later.
; This is the 1.000(binary) part.
; Then we shift the sample right three times, to get the 0.001(binary) part.
; Eventually, we add this right-shifted value to the original value, and get
; the original sample multiplied by 1.001(binary).
;
; With this method, the X16 is still running at very high CPU loads for 48 kHz
; 8-bit audio output. One could decrease the sample rate to regain some CPU
; cycles to do other stuff, for example waveform generation or sample playback.
; One could also simplify this algorithm and strip off the sub-level scaling
; if it is not needed. This would render even more CPU cycles available for
; other stuff.


; TODO: actually look at Booth's algorithm and try to implement it.


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
my_zp_ptr:
   .word 0

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







   ; takes a sample and applies volume scaling
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
   ; these are the hard-coded multiplications with powers of 2^(1/5)
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
