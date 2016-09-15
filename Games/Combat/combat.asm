; ****************************************************************************
; ****************************************************************************
;
;                          RCA Studio II Combat
;
;                    Written by Paul Robson October 2000
;
; ****************************************************************************
; ****************************************************************************
;
;       Register usage :
;
;       R0 R8 R9 RB.0   [Used in Interrupt Routine]
;       R1              [Interrupt Vector]
;       R2              [Stack Pointer]
;       R3              Program Counter (normal)
;       R4              Subroutine Pointer
;       R5              Points to page $07
;       R6              Scrap for sprite drawing routine
;       RC.0            Game Type [Bit 7 = 0:Tank/1:Plane]
;                                 [Bit 6 = 0:Short/1:Long missiles]
;                                 [Bit 5 = 0:Fast/1:S< missiles]
;                                 [Bit 4 = 1:Frame Screen]
;                                 [Bit 3 = 1:Tank Defences]
;                                 [Bit 2 = 1:Defences and Barriers]
;                                 [Bit 1 = 1:Balloons]
;                                 [Bit 0 = 1:Mines]
;       RD              Points to current object (e.g. it is $800 or $810)
;       RE              Points to video RAM at $900
;       RF              Points to program RAM at $800
;
;       x = $00 (Player 1), $10 (Player 2)
;
;       $8x0            Graphic, Vehicle
;       $8x1            Byte Position, Vehicle
;       $8x2            Bit Position, Vehicle
;       $8x3            Direction, Vehicle
;       $8x4            Graphic, Missile
;       $8x5            Byte Position, Missile
;       $8x6            Bit Position Missile
;       $8x7            Direction, Missile
;       $8x8            Life, Missile ($00 = No Missile)
;
;       $8F0,8F1        Scores for $800,$810 respectively

GameTest = $81


TankSpeed = 20/5
PlaneSpeed = 5

SndTmr  = $8CD
MovTmr  = $8CE                          ; Movement timer
MisTmr  = $8CF                          ; Missile timer

MVUp    = $80                           ; Movement bits
MVDown  = $40
MVLeft  = $20
MVRight = $10

        .include "1802.inc"
        .org    400h                    ; where RCA Studio II games start
        .db     >(Start),<(Start)  ; Internal Code call to Machine Code
        nop

; ****************************************************************************
;
;                    Draw Digit D at screen position RE
;
; ****************************************************************************

DrawDigit:
        ori     $10                     ; set R6 to $0210 Ý D
        plo     r6
        ldi     $02
        phi     r6
        ldn     r6                      ; read the digit address
        plo     r6                      ; R6 now points to the digit
        ldi     5                       ; do 5 lines
_DDLoop:phi     rb
        lda     r6                      ; read byte from data
        str     re                      ; write it out
        glo     re                      ; next line down
        adi     8
        plo     re
        ghi     rb                      ; decrement rb
        smi     1
        bnz     _DDLoop
        sep     r3                      ; return
        br     DrawDigit                ; reenter

; ****************************************************************************
;
;       Check Keyboard Key depressed. Already set up in OUT2 so return
;       EF3/4 dependent on RD.
;
; ****************************************************************************

CHKKey:
        glo     rd                      ; look at RD
        bz      CHKEF3                  ; if zero check EF3
        b4      CHKExit                 ; if key pressed return non-zero
        ghi     r1                      ; else return zero
        br      CHKExit
CHKEF3: bn3     CHKExit                 ; if not pressed return zero
        glo     r1                      ; return a non-zero value
CHKExit:sep     r3                      ; return
        br      CHKKey                  ; reentrant

; ****************************************************************************
;
;       XOR Draw a Sprite. Sprite Data is at RF.
;               +0 = Data Pointer, +1 = Screen Byte, +2 = Bit Offset.
;       Changes
;               R5,R6,RB.1,RE.0
;       Returns
;               D <> 0 if collision took place
;
; ****************************************************************************

XORDraw:
        dec     r2                      ; space on stack for the collision byte
        ghi     r1                      ; zero it
        str     r2
        lda     rf                      ; make R5 point to the graphic data
        plo     r5                      ; which is in page R5
        lda     rf                      ; Read the Byte position
        plo     re                      ; RE now points to the video byte
_XDrawLoop:
        lda     r5                      ; Read the next graphic byte
        bz      _XDrawExit              ; if zero, then exit
        phi     r6                      ; R6 := [Graphic Data]:$00
        ghi     r1
        plo     r6
        ldn     rf                      ; Read the bit shift
        bz      _XDNoBitShift           ; if zero, nothing required.
_XShiftLoop:
        phi     rb                      ; write back counter
        ghi     r6                      ; shift R6 right one as a word
        shr
        phi     r6
        glo     r6
        shrc
        plo     r6
        ghi     rb                      ; decrement the counter
        smi     1
        bnz     _XShiftLoop
_XDNoBitShift:
        sex     re                      ; video = index
        ghi     r6                      ; and byte with scren
        and
        sex     r2                      ; or that with the collision byte
        or
        str     r2

        sex     re                      ; video = index
        ghi     r6                      ; XOR R6.1 with screen byte
        xor
        str     re

        ghi     re                      ; next screen byte, stop wrap around
        inc     re
        phi     re

        glo     r6                      ; and byte with scren
        and
        sex     r2                      ; or that with the collision byte
        or
        str     r2
        sex     re                      ; video = index
        glo     r6                      ; XOR R6.0 with screen byte
        xor
        str     re

        glo     re                      ; add 7 to RE
        adi     7
        plo     re
        br      _XDrawLoop              ; and do the next byte
_XDrawExit:
        dec     rf                      ; fix RF
        dec     rf
        lda     r2
        sep     r3                      ; return
        br      XORDraw                 ; reentrant routine

; ****************************************************************************
;
;       Move a Sprite Object in the current direction
;               +0 = Data Pointer, +1 = Screen Byte, +2 = Bit Offset,+3 = Dir
;       Changes
;               R5,R6,RB.1
;
; ****************************************************************************

MOVObj:
        inc     rf                      ; skip graphic byte, point at screenbyte
        lda     rf                      ; R6.0 = Screenbyte, point at bit offset
        plo     r6

        inc     rf                      ; skip over bit offset, pt to direction
        ldn     rf                      ; read it
        ori     $F8                     ; force into $F8-$FF range
        plo     r5                      ; make R5 point to $07F8-$07FF
        ldn     r5                      ; read it
        phi     rb                      ; save the movement byte
        dec     rf                      ; point RF to the bit offset

        ldn     rf                      ; R5.0 = Bit Offset ored with $80. This
        ori     $80                     ; We can INC and DEC R5 and keep R5.1
        plo     r5

        ghi     rb                      ; look at direction byte
        shl
        bnf     _MONotUp                ; bit 7 is "up" $80
        phi     rb                      ; subtract 8 from position
        glo     r6
        smi     8
        plo     r6
        ghi     rb
_MONotUp:
        shl                             ; bit 6 is "down" $40
        bnf     _MONotDown
        phi     rb                      ; subtract 8 from position
        glo     r6
        adi     8
        plo     r6
        ghi     rb
_MONotDown:
        shl                             ; bit 5 is "left" $20
        bnf     _MONotLeft
        dec     r5                      ; decrement bit offset
        glo     r5
        ani     7
        xri     7
        bnz     _MOExit
        dec     r6                      ; if = 7, decrement byte
        br      _MOExit
_MONotLeft:
        shl                             ; bit 4 is "right" $10
        bnf     _MOExit
        inc     r5                      ; increment bit offset
        glo     r5
        ani     7
        bnz     _MOExit                 ; skip if not 00
        inc     r6                      ; if zero, next byte
_MOExit:
        glo     r5                      ; read it back
        ani     7                       ; only 3 bits relevant
        sex     rf                      ; use RF as index
        stxd
        glo     r6                      ; read screen byte
        stxd                            ; write that back too,points at original
        sep     r3                      ; return
        br      MOVObj                  ; reentrant

; ****************************************************************************
;
;                               Start a new fight
;
; ****************************************************************************

NewBattle:
        ghi     r1
        plo     rd
        plo     re
_ClearGame:
        ghi     r1                      ; Zero all Memory from $800 to $8EF
        str     rd
        inc     rd
        glo     rd
        xri     $F0
        bnz     _ClearGame
_InitVehicle:
        plo     rd                      ; RD points to vehicle
        plo     rf                      ; RF points to $800 or $810
        inc     rd                      ; point RD to $801/$811 [Screen Byte]
        glo     rd                      ; D = $01/$11
        shr                             ; D = $00/$08
        shr                             ; D = $00/$04
        phi     rb                      ; save this value
        bz      _IV1
        ldi     $16                     ; RD = $00/$16
_IV1:   adi     $70                     ; RD = $70/$86
        str     rd                      ; Set Screen Byte Position
        inc     rd
        ldi     $06                     ; Set sub position to the middle
        str     rd
        inc     rd                      ; set the initial direction
        ghi     rb
        adi     2
        str     rd
        inc     rd                      ; set the missile graphic
        ldi     MissileGraphic & 255
        str     rd
        str     rf
        ldi     XORDraw & 255           ; Draw the sprite (initially a dot)
        plo     r4
        sep     r4
        glo     rf                      ; go to the next one
        adi     $10
        ani     $1F
        bnz     _InitVehicle            ; do two of them
        plo     rd                      ; RD now is $800
        br      MainLoop                ; jump to background drawing bit here

; ****************************************************************************
;
;                               Main Loop
;
; ****************************************************************************

MainLoop:
        ldi     MovTmr & 255            ; Point RF Movement timer
        plo     rf
        ldn     rf
        lbnz    CheckMissiles           ; if non-zero try the missiles

; ****************************************************************************
;                               Move vehicle
; ****************************************************************************

        ldi     TankSpeed               ; reset the movement timer
        str     rf
        glo     rc                      ; check if plane
        shl
        bnf     _NotPlane1
        ldi     PlaneSpeed              ; if so, different speed
        str     rf
_NotPlane1:
        glo     rd                      ; switch to the next vehicle
        xri     $10
        plo     rd
        plo     rf                      ; RF points to its graphic
        ldi     XORDraw & 255           ; erase the old graphic
        plo     r4
        sep     r4

        inc     rf                      ; point RF to direction
        inc     rf
        inc     rf

        ldi     CHKKey & 255            ; set up subroutine for key check
        plo     r4
        sex     r3                      ; select keys using PC as Index
        out     2                       ; check key 4
        .db     4
        sep     r4                      ; read the key status
        bz      NoTurnLeft
        ldn     rf                      ; turn ship left
        smi     1
        ani     7
        str     rf
NoTurnLeft:
        out     2                       ; check key 6
        .db     6
        sep     r4
        bz      NoTurnRight
        ldn     rf                      ; turn ship right
        adi     1
        ani     7
        str     rf
NoTurnRight:
        sex     rf                      ; Direction pointed to by index reg.
        ldn     rf                      ; read direction
        shl
        shl                             ; x 4
        add                             ; x 5
        adi     TankGraphic & 255       ; Add to tank graphic
        str     rd                      ; update the display graphic

        glo     rc                      ; see if plane
        shl
        bnf     NotPlane2
        ldn     rd                      ; if so use the plane graphics
        adi     5*8
        str     rd
NotPlane2:
        glo     rd                      ; point RF to the vehicle
        plo     rf

        sex     r3                      ; use PC as Index
        out     2                       ; check 2 (forward)
        .db     2
        sep     r4                      ; check the key
        bz      NoForward
        ldi     MOVObj & 255            ; move it forward
        plo     r4
        sep     r4
        br      EndMove
NoForward:
        out     2                       ; check 8 (backward)
        .db     8
        sep     r4                      ; check the key
        bz      EndMove

        inc     rd                      ; point RD to direction
        inc     rd
        inc     rd

        ldn     rd                      ; reverse direction
        adi     4
        ani     7
        str     rd

        ldi     MOVObj & 255            ; move it forward - backwards
        plo     r4
        sep     r4

        ldn     rd                      ; reverse the direction again
        adi     4
        ani     7
        str     rd

        glo     rf                      ; fix RD back
        plo     rd
EndMove:
        glo     rc                      ; see if plane
        shl
        bnf     _NoAutoMove
        ldi     MOVObj & 255            ; if plane do an extra move
        plo     r4
        sep     r4
_NoAutoMove:

        ldi     XORDraw & 255           ; draw the new graphic
        plo     r4
        sep     r4
        lbz     MainLoop                ; go back if no collision
        br      Dead                    ; if collision current player is dead

; ****************************************************************************
;                            Move missile
; ****************************************************************************

CheckMissiles:
        inc     rf                      ; RF now points to missile timer @$8CF
        ldn     rf                      ; check if this is zero
        lbnz    MainLoop                ; if not, loop back
        glo     rc                      ; get missile speed bit
        ani     $20                     ; 0/32
        bz      _NotSlow
        ldi     2                       ; 0/2
_NotSlow:
        adi     1                       ; 1/3
        str     rf
        glo     rd                      ; point RA to the missile life value
        adi     8
        plo     ra
        ghi     rd
        phi     ra
        ldn     ra                      ; read missile life
        bnz     MoveMissile
        sex     r3                      ; use PC to test fire
        out     2                       ; select key 0 (fire)
        .db     0
        ldi     CHKKey & 255            ; test the key press
        plo     r4
        sep     r4
        lbz     MainLoop                ; not pressed, main loop
        ldi     SndTmr & 255            ; short beep
        plo     rf
        ldi     3
        str     rf
        glo     rd                      ; point RB to RD+5
        adi     4
        plo     rf                      ; point RF to RD+4
        plo     ra
        inc     ra
        ghi     rd
        phi     ra
        inc     rd                      ; skip the graphic
        lda     rd                      ; read byte position
        str     ra                      ; copy to missile info
        inc     ra
        lda     rd                      ; read bit posiion
        str     ra                      ; copy to missile info
        ldn     rd                      ; get movement direction
        phi     rc                      ; save in RC.1
        inc     ra                      ; set the missile movement direction
        ldi     3                       ; to down and right to roughly centre it
        str     ra
        dec     rd                      ; fix RD back to $8x0
        dec     rd
        dec     rd
        ldi     MOVObj & 255            ; move it down and right twice
        plo     r4
        sep     r4
        sep     r4
        ghi     rc                      ; set the real direction
        str     ra
        sep     r4                      ; and move it three times
        sep     r4
        sep     r4
        sep     r4
        ldi     XORDraw & 255           ; draw the initial missile
        plo     r4
        sep     r4
        inc     ra                      ; point RA to the missiles life
        glo     rc
        ani     $40                     ; get the 'missile size' (00/64)
        shr                             ; 00/32
        shr                             ; 00/16
        adi     14                      ; 14/30 size
        str     ra                      ; set the missiles life
        lbr     MainLoop                ; and loop back.

MoveMissile:
        glo     rd                      ; point RF to missile sprite record
        adi     4
        plo     rf
        ldi     XORDraw & 255           ; erase the old missile
        plo     r4
        sep     r4
        ldn     ra                      ; subtract 1 from missile life
        smi     1
        str     ra
        lbz     MainLoop                ; if zero, that's it.
        ldi     MOVObj & 255            ; move the object
        plo     r4
        sep     r4
        ldi     XORDraw & 255           ; redraw the object
        plo     r4
        sep     r4
        lbz     MainLoop                ; and loop around

        glo     rd                      ; point RF to the *OTHER* baddie
        xri     $10
        plo     rf
        sep     r4                      ; erase and redraw
        sep     r4
        bnz     _KillMe
        glo     rd                      ; point to the missile again
        adi     4
        plo     rf
        sep     r4                      ; erase it
        ghi     r1                      ; kill the missile by zeroing life
        str     ra
        lbr     MainLoop

_KillMe:glo     rf                      ; set to destroy the right one.
        plo     rd

; ****************************************************************************
;        Vehicle (RD) has collided with missile or something else
; ****************************************************************************

Dead:   glo     rd                      ; D = 0/$10
        bz      _NotRight
        ldi     1                       ; D = 0/1
_NotRight:
        adi     $F0                     ; D = $F0/$F1
        xri     $01                     ; switch so right one gets score
        plo     rf                      ; point RF to score
        ldn     rf                      ; bump score
        adi     1
        str     rf
        phi     rc                      ; save this in RC
        ldi     $F0                     ; point RF to $08F0
        plo     rf
        ldi     $11                     ; point RE to $0911
        plo     re
        ldi     DrawDigit & 255         ; draw the digit
        plo     r4
        lda     rf                      ; read the digit
        sep     r4                      ; draw it.
        ldi     $16                     ; point RE to $0916
        plo     re
        ldn     rf                      ; read the other digit
        sep     r4                      ; draw the other digit
        ldi     SndTmr & 255            ; long beep
        plo     rf
        ldi     30
        str     rf
        ldi     MisTmr & 255            ; delay for 3.5 seconds
        plo     rf
        str     rf
WaitTmr:ldn     rf                      ; wait for it to time out
        bnz     WaitTmr
        ghi     rc                      ; look at the score
        xri     9                       ; reached 10 ?
        bnz     InitGame                ; if not 10 then start the game again
GameOver:                               ; we now stop, game over. Reset to
        br      GameOver                ; Restart

; ****************************************************************************
;
;                       Draw the frame/background etc.
;
; ****************************************************************************

InitGame:
        ghi     r1
        plo     re
_ClearScreen:                           ; Clear the screen, possibly w/frame
        ghi     r1                      ; zero it.
        str     re
        glo     rc                      ; check if framed ?
        ani     $10
        bz      _CSNext
        glo     re                      ; RE = offset
        adi     8                       ; $F8-$07 => $00-$0F
        ani     $F0                     ; if zero, then top and tail screen
        bz      _CSEdge
        glo     re                      ; check if left edge
        ani     7
        bz      _CSLSd
        xri     7                       ; check if right edge
        bnz     _CSNext
        ldi     $01
        br      _CSWNxt
_CSLSd: ldi     $80                     ; left side
        br      _CSWNxt
_CSEdge:ldi     $FF                     ; solid bar
_CSWNxt:str     re                      ; write it out
_CSNext:inc     re                      ; next screen byte
        glo     re
        bnz     _ClearScreen
        dec     re                      ; fixes RE wrapping around to $A00
        glo     rc
        ani     $04                     ; analyse bits 3,2,1,0 of game desc
        bnz     _DefAndBar
        glo     rc
        ani     $08
        bnz     _DefOnly
        glo     rc
        ani     $02
        bnz     _Balloons
_CheckMines:
        glo     rc
        shr
        lbnf    NewBattle               ; draw the mines
        ldi     DrawMines & 255
        br      _DrawSprites
_Balloons:
        ldi     DrawBalloon & 255
        br      _DrawSprites
_DefOnly:                               ; just the ][ barriers
        ldi     DrawDefence & 255
        br      _DrawSprites
_DefAndBar:                             ; all the barriers
        ldi     DrawBarDefence & 255
_DrawSprites:
        plo     rf                      ; store in RF.0
        ghi     r5                      ; make RF point to where the info is
        phi     rf
_DSLoop:ldi     XORDraw & 255           ; draw it
        plo     r4
        sep     r4
        inc     rf                      ; move to next
        inc     rf
        inc     rf
        ldn     rf
        bnz     _DSLoop                 ; loop back if not completed.
        ghi     rd                      ; fix RF to point to RAM
        phi     rf
        lbr     NewBattle
      
; ****************************************************************************
;
;                               New game
;
; ****************************************************************************

Start:  ldi     $09                     ; RE points to video RAM
        phi     re
        ldi     $08                     ; RD points to data RAM/current ship
        phi     rd
        ldi     $07                     ; R5 points to page $07 [tabs/gfx]
        phi     r5
        phi     rf                      ; RF points here briefly
        ldi     $04                     ; R4 points to page $04 [subroutines]
        phi     r4
        ldi     DrawPrompt & 255
        plo     rf
        ldi     XORDraw & 255
        plo     r4
        sep     r4
        ghi     rd
        phi     rf
        ldi     $F0                     ; Zero scores in $F0 and $F1
        plo     rf
        ghi     r1
        str     rf
        inc     rf
        str     rf
        plo     rc                      ; Zero the game selector value.
        inc     rf                      ; use this byte as working ($2F2)
        str     rf                      ; zero it
_WaitKey:
        sex     r3                      ; check pad 2 key 0 (start)
        out     2
        .db     0
        b4      _StartGame              ; if pressed, start the game
        ldn     rf                      ; bump the value, wrap round at 15
        adi     1
        ani     15
        str     rf
        sex     rf                      ; prepare to "out" it.
        out     2
        dec     rf                      ; fix RF
        bn3     _WaitKey                ; if not pressed, go back
        inc     rf                      ; point RF to next byte
        glo     rc                      ; get game ID
        str     rf                      ; save it there
        shl                             ; multiply by four
        shl
        add                             ; multiply by five
        shl                             ; multiply by ten
        dec     rf                      ; point to new key
        add                             ; multiply by ten + new key
        plo     rc                      ; update RC
        ldi     SndTmr & 255            ; point RD to sound timer
        plo     rd
        ldi     10                      ; short beep
        str     rd
_WaitRel:
        b3      _WaitRel                ; wait for key release
        br      _WaitKey                ; go back and wait for another key

_StartGame:
        b4      _StartGame              ; wait for release
        lbr     InitGame                ; and run the game !

; ****************************************************************************
;
;       Graphic Data. The ORG must be set so the memory is filled through
;       to $7FF (e.g. the table is at $7F8)
;
; ****************************************************************************

        .org    $744
DrawPrompt:
        .db     Prompt & 255,13*8+3,5,0
DrawMines:
        .db     MissileGraphic & 255, 7*8+3,5
        .db     MissileGraphic & 255, 17*8+2,4
        .db     MissileGraphic & 255, 13*8+6,5
        .db     MissileGraphic & 255, 27*8+4,4
        .db     MissileGraphic & 255, 4*8+1,5
        .db     MissileGraphic & 255, 19*8+0,4
        .db     MissileGraphic & 255, 22*8+5,1
        .db     MissileGraphic & 255, 6*8+6,5
        .db     MissileGraphic & 255, 11*8+5,4
        .db     0
DrawBalloon:
        .db     Balloon & 255,4*8+2,0
        .db     Balloon & 255,24*8+6,0
        .db     Balloon & 255,14*8+3,4
        .db     0
DrawBarDefence:
        .db     VLine & 255,4*8+3,7
        .db     VLine & 255,22*8+3,7
        .db     HLine & 255,16*8+3,3
DrawDefence:
        .db     LeftSqGraphic & 255,12*8+1,4
        .db     RightSqGraphic & 255,12*8+5,4
        .db     0
; xxxx.xxx
; x......x
; x.xx.xxx
; x..x....
; xxxx.x..
Prompt:
        .db     $F7,$81,$B7,$90,$F4,$00
Balloon:
        .db     $70,$F8,$F8,$F8,$70,$00
VLine:
        .db     $80,$80,$80,$80,$80,$00
HLine:
        .db     $FE,$00
LeftSqGraphic:
        .db     $F0,$10,$10,$10,$10,$10,$10,$10,$F0,$00
RightSqGraphic:
        .db     $0F,$08,$08,$08,$08,$08,$08,$08,$0F,$00

;    ....x...  ...x....  .xxx....
;    ..xxx...  ..xxx...  ..xxx...
;    .xxx....  ..xxx...  .xxx....
;    x.x.....  ..x.x...  ........

MissileGraphic:
        .db     $80,$00
TankGraphic:
        .db     $10,$38,$38,$28,$00     ; (Tank, up)
        .db     $10,$38,$70,$A0,$00     ; (Tank, up right)
        .db     $70,$38,$70,$00,$00     ; (Tank, right)
        .db     $A0,$70,$38,$08,$00     ; (Tank, down right)
        .db     $28,$38,$38,$10,$00     ; (Tank, down)
        .db     $28,$70,$E0,$80,$00     ; (Tank, down left)
        .db     $38,$70,$38,$00,$00     ; (Tank, left)
        .db     $80,$E0,$70,$28,$00     ; (Tank, up left)

;    x.......    ..xxx...    ....x...
;    xxxx....    ..xx....    ..xx....
;    xxxxx...    ..xx....    xxx.....
;    ........    ..x.....    xx......

PlaneGraphic:
        .db     $20,$30,$30,$38,$00     ; (Plane, up)
        .db     $08,$30,$E0,$C0,$00     ; (Plane, up right)
        .db     $80,$F0,$F8,$00,$00     ; (Plane, right)
        .db     $C0,$E0,$30,$08,$00     ; (Plane, down right)
        .db     $38,$30,$30,$20,$00     ; (Plane, down)
        .db     $18,$38,$60,$80,$00     ; (Plane, down left)
        .db     $08,$78,$F8,$00,$00     ; (Plane, left)
        .db     $80,$60,$38,$18,$00     ; (Plane, up left)

        .db     MVUp                    ; table converts direction to
        .db     MVUp+MVRight            ; movement bit collection
        .db     MVRight
        .db     MVDown+MVRight
        .db     MVDown
        .db     MVDown+MVLeft
        .db     MVLeft
        .db     MVUp+MVLeft
        .end
;

