; ***************************************************************************
;
;                     Hockey / Soccer / Pong / Squash
;
;                   An RCA Studio II Game by Paul Robson
;
;       Keys:   1,2,3,4 select Hockey,Soccer,Pong or Squash
;               8,9 select Easy or Hard Game
;               either 0 serves ; 2 and 8 move the bats
;
; ***************************************************************************
;
;       Reserved        R0,R1,R2,R8,R9,RB.0
;       R3      PC
;       R4      Ball Plot Routine
;       R5      Result (Ball Plot)
;       R6      Work (Ball Plot)
;       RA      Beep Timer
;       RE.1    points to video memory
;       RF.1    points to data memory
;
;       All Paddles are : Position, Height, Mask, 3 bytes each.
;
;       $800    Left Score (0-9)
;       $801    Right Score (0-9)
;       $802    Type (0=Hockey,1=Soccer,2=Pong,3 = Squash)
;       $803    Bat Size
;       $804    Left Goalie
;       $807    Left Striker
;       $80A    Right Goalie
;       $80D    Right Striker
;       $810    Ball X Position (0-63)
;       $811    Ball X Increment
;       $812    Ball Y Position (0-63)
;       $813    Ball Y Increment
;

WinScore   = 10
ServePoint = 6
BallSpeed  = 2
BatSpeed   = 2
HBatSize   = 3
EBatSize   = 5

LeftSc  = $800
RightSc = $801
Type    = $802
BatSize = $803
VideoPage = $11                         
ColourPage = $13                        

Paddles = $804
BallX   = $810
BallXI  = $811
BallY   = $812
BallYI  = $813
SndTmr  = $8CD
BallTmr = $8CE
BatTmr  = $8CF

        .include "1802.inc"
        .org    800h                    
        .db     >(InitJump),<(InitJump)

Start:  ldi     $10                     
        phi     rf
        phi     ra
        ldi     0                       
        plo     rf
        str     rf                      ; Zero Left Score
        inc     rf
        str     rf                      ; Zero Right Score
        inc     rf
        ldi     <(SndTmr)             ; Set RA to beep timer
        plo     ra

        sex     r3                      ; decide on which game
_SelectGame:
        out     2                       ; key 4 (Squash)
        .db     4
        ldi     3
        b3      _SetGame
        out     2                       ; key 3 (Pong)
        .db     3
        ldi     2
        b3      _SetGame
        out     2                       ; key 1 (Soccer)
        .db     1
        ldi     1
        b3      _SetGame
        out     2                       ; key 2 (Hockey)
        .db     2
        bn3     _SelectGame
        ldi     0                       
_SetGame:                               ; Set Game Type
        str     rf
        ldi     30                      ; beep to player
        str     ra
        ldi     <(BallX)              ; Set Ball Position (default value)
        plo     rf                      ; on the left hand side first time
        ldi     ServePoint              ; around
        str     rf

        ldi     <(BatSize)            ; Bat size 8 (Easy,5) 9 (Hard,3)
        plo     rf
_SelectSize:
        out     2
        .db     8
        ldi     EBatSize
        b3      _SetSize
        out     2
        .db     9
        ldi     HBatSize
        bn3     _SelectSize
_SetSize:
        str     rf                      ; Save the bat size
        ldi     30                      ; beep to player
        str     ra

; ***************************************************************************
;                                New Point
; ***************************************************************************

NewPoint:

; ***************************************************************************
;                             Draw the game frame
; ***************************************************************************

        ldi     <(Type)               ; Read game type into RB.1
        plo     rf
        ldn     rf
        phi     rb
        ldi     $11                     
        phi     rd
        phi     rc                      ; Point RC there too
        phi     re                      ; and RE is set up for later
        ldi     0                       
        plo     rd
_DrawFrame:                             
        sep     r7           
        .dw     DrawFrameBoth
_DFBack:                                
                                        
                                        
        glo     rd
        ani     $F8
        bz      _DrawSolid              ; top line
        xri     $F8
        bz      _DrawSolid              ; bottom line

        glo     rd                      ; check for squash back wall
        ani     7
        xri     7
        bnz     _NotSquash
        ghi     rb
        xri     3
        bnz     _NotSquash
        ldi     $01
        br      _DrawIt
_NotSquash:

        ghi     rb                      ; drawing a "football" game
        bnz     _DrawNext

        glo     rd                      ; check in goal area
        shl
        glo     rd
        bnf     _NotNeg
        sdi     0
_NotNeg:adi     $B8
        bdf     _DrawNext

        glo     rd                      ; check front or back
        ani     7
        bz      _DrawEdge1
        xri     7
        bnz     _DrawNext
        ldi     $01
        br      _DrawIt
_DrawEdge1:
        ldi     $80
        br      _DrawIt
_DrawSolid:
        ldi     $FF                     ; filled video square
_DrawIt:
        str     rd
_DrawNext:                              ; paint the whole screen
        inc     rd
        glo     rd
        bnz     _DrawFrame
        dec     rd                      ; RE points to Video RAM page again

        ldi     $14                     ; RF points to the centre bar
_CentreBar:
        plo     rc
        ldi     $80
        str     rc
        glo     rc
        adi     $10
        bnf     _CentreBar

        ldi     0             ; point RF to score
        plo     rf
        ldi     $13                     ; point RE to the display position
        plo     re
_WriteScore:
        lda     rf                      ; read score digit
        ori     $80                     
        plo     rd                      ; not $210 -- the same table, $270 higher
        ldi     $04
        phi     rd
        ldn     rd                      ; read the offset
        plo     rd                      ; RD now points to the graphic data
        ldi     5                       ; there are 5 bytes
        plo     rc
_CopyDigit:
        lda     rd                      ; read a byte
        shr
        shr
        phi     r6
        glo     rf
        shr
        ghi     r6
        bnf     _NoBalance
        shr
_NoBalance:
        sex     re                      ; or into screen
        or
        str     re
        glo     re                      ; next position down
        adi     8
        plo     re
        dec     rc                      ; do it 5 times
        glo     rc
        bnz     _CopyDigit
        ldi     $14                     ; second position
        plo     re
        glo     rf                      ; done both
        shr
        bdf     _WriteScore
_EndScore:

; ***************************************************************************
;                       Initialise the paddles
; ***************************************************************************

		ldi		<padInfo
		plo		rc
		ldi 	>padInfo
		phi 	rc

        ldi     <(BatSize)            ; Read Batsize into R5.1
        plo     rf
        ldn     rf
        phi     r5

        ldi     <(Paddles)            ; RF to point to paddle position memory
        plo     rf

        ghi     rf                      ; Make R6 point to the game type
        phi     r6
        ldi     <(Type)
        plo     r6
     
InitPaddle:
        ldn     r6                      ; read game type
        ani     2
        sep     r7                ; all 4 if not "pong"
        .dw     _NotPong+$8000
        ldn     rc                      ; read position
        sep     r7                ; if in square 0, draw if pong or squash
        .dw     _NotPong+$8000
        ldn     r6                      ; if squash, only square 0
        xri     3
        sep     r7
        .dw     _KillPaddle+$8000
        ldn     rc
        xri     7                       ; if in square 7, draw if pong ONLY
        sep     r7
        .dw     _NotPong+$8000

_KillPaddle:
        inc     rc                      ; skip RC past the table data
        inc     rc
        ldi     0             ; zero the "position" of the paddle
        str     rf
        inc     rf                      ; skip over three bytes
        inc     rf
        inc     rf
        sep     r7
        .dw     _NextPDraw
_NotPong:
        lda     rc                      ; read the offset
        adi     $70                     ; centre it, roughly
        str     rf                      ; store it in "position"
        inc     rf
        plo     re                      ; RE points to it
        ghi     r5                      ; get height
        str     rf                      ; store that as well
        inc     rf
        plo     rd                      ; save height in RD.0
        lda     rc                      ; get mask
        str     rf
        inc     rf
        phi     rb                      ; save mask in RB.1
_DrawPaddle:                            
        sep     r7          ; the $B00 page, which draws player 2's paddles
        .dw     DrawPaddleBoth
        .db     0,0,0,0,0,0,0,0,0       ; into both planes. Twelve bytes either way, so
                                        ; nothing below here moves.
_NextPDraw:
        glo     rf                      ; do all four paddles
        ani     $0F
        sep     r7
        .dw     InitPaddle+$4000

; ***************************************************************************
;                  Initialise the Ball (Ball X already set up)
; ***************************************************************************

        ldi     <(BallX)              ; access X Ball at RF
        lda     rf                      ; read the X Ball position
        ani     $F8                     ; look at "byte" value of position
        bz      _IsLeft                 ; if zero, on the left hand side
        ldi     2                       ; now 0 left, 2 right
_IsLeft:sdi     1                       ; now 1 left, -1 right
        str     rf                      ; store at Ball X increment
        inc     rf
        glo     r9                      ; get value from frame counter
        ani     15                      ; 0-15
        adi     8                       ; 8-24
        shl                             ; 16-48
        str     rf                      ; this is Ball Y position
        inc     rf
        ldi     -1                      ; Ball always serves "up"
        str     rf

		ldi 	>BallDraw				; R4 is the drawing subroutine
		phi 	r4
		ldi 	<BallDraw
		plo 	r4
        sep     r4                      ; call it to draw Ball

        sex     r3                      ; wait for either key '0'
        out     2
        .db     0
_Wait0: b3      _Start0
        bn4     _Wait0
_Start0:sep     r7
        .dw     MainLoop

; ***************************************************************************
;
;       Ball Draw Subroutine. XOR Plots Ball at Current Position.
;
;       On Exit,
;               R5 contains the address, RB.1 mask, D = 0 = Collision
;               DF,R6 undefined values
;
; ***************************************************************************

BallDraw:
        ghi     re                      ; point R5 to the video display
        phi     r5
        ghi     rf                      ; point R6 to the Y Ball Position
        phi     r6
        ldi     <(BallY)
        plo     r6
        ldn     r6                      ; read Y position
        ani     $3E                     ; value 0,2,4,6,8...62
        shl                             ; multiply by 4
        shl
        dec     r2                      ; make room on the stack and save it
        str     r2
        dec     r6                      ; point R6 to the X Ball Position
        dec     r6
        ldn     r6                      ; read it
        ani     63
        shr                             ; divide by 8
        shr
        shr
        sex     r2                      ; add to Y * 8 on the stack
        add
        inc     r2                      ; fix the stack
        plo     r5                      ; put into R5

        ldn     r6                      ; read X position
        ori     <(MaskTable)          ; make R6 point to the mask
        plo     r6
        ldi     >(MaskTable)
        phi     r6
        ldn     r6                      ; read mask
        phi     rb                      ; put in RB.1
        sex     r5                      ; XOR with the screen
        xor
        str     r5
        ghi     rb                      ; re read the mask
        and                             ; AND with the screen. Zero if collision
        sep     r3
        br     BallDraw


; ***************************************************************************
;                               Start up
; ***************************************************************************

StartGame:
        ldi     $11                     
        phi     re
        phi     rc
        ldi     0             ; clear the screen
        plo     re
_SGClear:
        ldi     0                       
        str     re
        inc     re
        glo     re
        bnz     _SGClear

        ldi 	>Banner                 ; RE := Banner
		phi		re
		ldi 	<Banner
		plo 	re

        ldi     2*8+1                   ; RC := Banner Position
        plo     rc
_CopyBanner:
        ldn     re                      ; if first is $01 then exit
        xri     1
        sep     r7
        .dw     Start+$8000
        lda     re                      ; copy three bytes
        str     rc
        inc     rc
        lda     re
        str     rc
        inc     rc
        lda     re
        str     rc
        glo     rc                      ; then a new line
        adi     6
        plo     rc
        br      _CopyBanner

;       xxxx..xx!xx..x..x!..xxxx..
;       x..x..x.!.x..xx.x!..x.....
;       xxxx..x.!.x..x.xx!..x.xx..
;       x.....x.!.x..x..x!..x..x..
;       x.....xx!xx..x..x!..xxxx..

Banner: .db     $FF,$FF,$FC
        .db     $00,$00,$00
        .db     $F3,$C9,$3C
        .db     $92,$4D,$20
        .db     $F2,$4B,$2C
        .db     $82,$49,$24
        .db     $83,$C9,$3C
        .db     $00,$00,$00
        .db     $FF,$FF,$FC
        .db     $01
;
PadInfo:                                ; pairs of positions, masks
        .db     0,$10                   ; Left Goalie [$804]
        .db     5,$40                   ; Left Striker [$807]
        .db     7,$08                   ; Right Goalie [$80A]
        .db     2,$02                   ; Right Striker [$80D]

        .org    $09F0
ByteToAddr:
        .db     $04                     ; comes from the table above
        .db     $00                     ; convert the byte address to an
        .db     $0D                     ; address of the paddle record
        .db     $00
        .db     $00
        .db     $07
        .db     $00
        .db     $07

        .org    $09F8
MaskTable:
        .db     $80,$40,$20,$10,$8,$4,$2,$1
    
; ***************************************************************************
;
;                               Main Game Loop
;
; ***************************************************************************

        .org    $A00
MainLoop:

; ***************************************************************************
;                             Move the paddles
; ***************************************************************************

        ldi     <(BatTmr)             ; time to move the bats
        plo     rf
        ldn     rf
        bnz     _EndMovePaddles
        ldi     BatSpeed
        str     rf
        ldi     <(Paddles)            ; set RF to point to the paddles
        plo     rf
_MovePaddles:
        ghi     rf                      ; copy RF to RD, points to position
        phi     rd
        glo     rf
        plo     rd
        lda     rf                      ; position in RE, RE points paddle top
        plo     re
        lda     rf                      ; read height
        shl                             ; multiply by 8
        shl
        shl
        sex     rd                      ; add to paddle position
        add
        plo     rc                      ; RC points to byte after paddle
        ghi     re                      ; in video RAM
        phi     rc
        lda     rf                      ; read mask
        phi     rb                      ; put in RB.1

        ldn     rd                      ; read position
        bz      _NextPaddle             ; if zero, don't move

        sex     r3                      ; starting to scan keyboard
        out     2                       ; scan key 2 (up)
        .db     2

        glo     rd                      ; if this is $04 or $07 it is player 1
        ani     $08                     ; if it is $0A or $0D it is player 2
        bnz     _Player2

        b3      _PaddleUp
        out     2                       ; scan key 8 (down)
        .db     8
        b3      _PaddleDown
        br      _NextPaddle
_Player2:
        b4      _PaddleUp
        out     2                       ; scan key 8 (down)
        .db     8
        b4      _PaddleDown
_NextPaddle:
        glo     rf                      ; done all paddles
        ani     $0F
        bnz     _MovePaddles
        br      _EndMovePaddles

_PaddleUp:
        glo     re                      ; moving up, move both top and bottom
        smi     8
        plo     re
        glo     rc
        smi     8
        plo     rc
        sex     re
        ghi     rb                      ; see if can move up
        and
        bnz     _NextPaddle             ; if pixel set, can't move
        glo     re                      ; update the position
        str     rd
        br      _PMoveNow
_PaddleDown:
        sex     rc                      ; see if can move down
        ghi     rb
        and
        bnz     _NextPaddle             ; if pixel set, can't move
        glo     re                      ; update position
        adi     8
        str     rd
_PMoveNow:                              
        sep     r7               ; tint with the paddle, or the red stays behind at
        .dw     PMoveBoth
        .db     0,0,0,0,0,0,0           ; the old position. Ten bytes either way.

_EndMovePaddles:

; ***************************************************************************
;                               Move the Ball
; ***************************************************************************

        ldi     <(BallTmr)            ; read the ball timer
        plo     rf
        ldn     rf
        bnz     _EndMoveBall
        ldi     BallSpeed               ; timed out, update timer
        str     rf
        sep     r4                      ; erase the old ball

        ldi     <(BallYI)+1           ; prepare to move coordinates
        plo     rf
_AdjustCoords:
        dec     rf
        ldn     rf                      ; read the increment
        dec     rf                      ; add to the position
        sex     rf
        add
        str     rf                      ; update the position
        glo     rf
        ani     $0F                     ; done all of them ?
        bnz     _AdjustCoords
        sep     r4                      ; redraw it
        bnz     _EndMoveBall            ; if non-zero no collision

        glo     r5                      ; look at the address
        ani     $F8                     ; which row is it on ?
        bz      _VertBounce             ; if 0 it is vertical bounce
        xri     $F8                     ; if 31 it is vertical bounce
        bz      _VertBounce

        glo     r5                      ; look at the columns ; if 3 or 4
        ani     $07                     ; there is no bounce
        xri     3
        bz      _EndMoveBall
        xri     7
        bz      _EndMoveBall

        ldi     <(BallX)              ; read the real X position
        plo     rf
        ldn     rf
        bz      _WallBounce             ; if 0 or 63 then bouncing off a wall
        xri     63                      ; otherwise bouncing off a bat, so
        bnz    _AdjustYI               ; need to adjust YI

_WallBounce:
        ldi     <(BallXI)             ; horizontal bounce
        br      _Bounce

_VertBounce:                            ; vertical bounce
        ldi     <(BallYI)
_Bounce:
        plo     rf                      ; bounce the value
        ldn     rf                      ; read it
        sdi     0                       ; negate it
        str     rf                      ; write it back
        ldi     3                       ; Short Beep
        str     ra
_EndMoveBall:
        ldi     <(BallX)              ; Read new ball X position
        plo     rf                      ; (point RF *and* RC)
        plo     rc
        ldn     rf
        ani     $C0                     ; if off either left or right
        bz     MainLoop
        sep     r4                      ; Erase the ball
        ldi     30                      ; Long Beep
        str     ra
        ldn     rf                      ; Read Ball X position
        shr                             ; shift MSB into DF
        ldi     0                       
        shlc                            ; now 0 for right, 1 for left
        plo     rf                      ; RF points to score
        ldn     rf                      ; bump the score
        adi     1
        str     rf
        xri     WinScore                ; game over
        sep     r7
        .dw     StartGame+$8000
        ghi     rf                      ; RC points to the Ball X value
        phi     rc
        glo     rf                      ; RF = 0 (left won) 1 (right won)
        xri     $01
        bz      _LServe
        adi     62-ServePoint-ServePoint; Shift to the right
_LServe:adi     ServePoint
        str     rc                      ; Write it back
        sep     r7
        .dw     NewPoint

; ***************************************************************************
;         Ball has hit a bat. Figure out the new vertical direction
; ***************************************************************************

_AdjustYI:
        glo     r5                      ; read the byte address where hit
        ani     $07
        ori     $F0                     ; in RD make pointer to table
        plo     rd                      ; to get the appropriate paddle
        ldi     $05
        phi     rd
        ldn     rd                      ; read the paddle
        plo     rf                      ; RF now points to the paddle record
        lda     rf                      ; read the address, point to height
        bz     _WallBounce             ; (safety) no paddle there.....
        ldn     rf                      ; read the height
        shr                             ; divide by 2
        shl                             ; multiply by 8
        shl
        shl
        dec     rf                      ; point to address again
        sex     rf                      ; add the top of the paddle
        add                             ; this is the centre address
        dec     r2                      ; save centre addresss on stack space
        str     r2
        sex     r2
        glo     r5                      ; get collision address
        sm                              ; calculate collision-centre
        inc     r2                      ; fix the stack
        bz      _SetYI                  ; work out the angle to go at
        shl
        ldi     $FF
        bdf     _SetYI
        ldi     $01
_SetYI: phi     rb
        ldi     <(BallYI)
        plo     rf
        ghi     rb
        str     rf
        br     _WallBounce

        .org    0BFFh                   ; fill it
        .db     0FFh

        .org    $B00

; On entry RD -> the byte of the rink being painted. Clear the matching byte of plane 1.
DrawFrameBoth:
        ldi     0
        str     rd                      ; the plane 0 default, as before
        ghi     rd                      ; $11 -> $13
        adi     2
        phi     rd
        ldi     0
        str     rd                      ; and wipe plane 1 at the same offset
        ghi     rd
        smi     2
        phi     rd
        ldi     0                       ; leave D as _DrawFrame left it
        sep     r7
        .dw     _DFBack

; On entry: RB.1 = mask, RE -> the paddle in plane 0, RD.0 = height, RF.0 = record base + 3.
DrawPaddleBoth:
        ghi     rb                      ; xor mask into plane 0, as before
        sex     re
        xor
        str     re
        glo     rf                      ; RF is at base+3 here; bit 3 of the base says
        smi     3                       ; which player owns this paddle
        ani     8
        bz      _DPBNoTint
        ghi     re                      ; $11 -> $13
        adi     2
        phi     re
        ghi     rb                      ; the same mask into plane 1
        xor
        str     re
        ghi     re
        smi     2
        phi     re
_DPBNoTint:
        glo     re                      ; bump pointer to next line
        adi     8
        plo     re
        dec     rd                      ; do it for the height
        glo     rd
        bnz     DrawPaddleBoth
        sep     r7
        .dw     _NextPDraw

; On entry: RB.1 = mask, RE -> the new end, RC -> the old end, RD -> the paddle record.
PMoveBoth:
        sex     re                      ; toggle top and bottom pixels
        ghi     rb
        xor
        str     re
        sex     rc
        ghi     rb
        xor
        str     rc
        glo     rd                      ; player 2 owns $0A and $0D
        ani     8
        bz      _PMBDone
        ghi     re                      ; the same two toggles in plane 1
        adi     2
        phi     re
        sex     re
        ghi     rb
        xor
        str     re
        ghi     re
        smi     2
        phi     re
        ghi     rc
        adi     2
        phi     rc
        sex     rc
        ghi     rb
        xor
        str     rc
        ghi     rc
        smi     2
        phi     rc
_PMBDone:
        sep     r7             ; and do the next one
        .dw     _NextPaddle


; R7 stays on this reentrant jump routine. All instructions take two cycles,
; keeping the BIOS raster loop aligned when an interrupt arrives during a jump.
; Inline target bits: $8000 = if zero, $4000 = if nonzero, neither = always.
; D, DF, X and all registers except the two program counters are preserved.
        .org    $B80
InitJump:
        ldi     >Jump
        phi     r7
        ldi     <Jump
        plo     r7
        sep     r7
        .dw     StartGame
Jump:
        dec     r2
        str     r2
        bz      _JumpZero
        lda     r3
        ani     $80
        bnz     _JumpSkip
        br      _JumpTake
_JumpZero:
        lda     r3
        ani     $40
        bnz     _JumpSkip
_JumpTake:
        dec     r3
        lda     r3
        dec     r2
        str     r2
        ldn     r3
        plo     r3
        ldn     r2
        ani     $0F
        phi     r3
        inc     r2
        br      _JumpDone
_JumpSkip:
        inc     r3
_JumpDone:
        ldn     r2
        inc     r2
        sep     r3
        br      Jump

        .end
