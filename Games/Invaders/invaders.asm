; ****************************************************************************
; ****************************************************************************
;
;                        RCA Studio II Space Invaders
;
;                    Written by Paul Robson September 2000
;
;	Modified September 2016 to not use Long Branches which cause display 
;	glitches. PSR.
;
; ****************************************************************************
; ****************************************************************************
;
;       Register usage :
;
;       R0 R8 R9 RB.0   [Used in Interrupt Routine]
;       R1              [Interrupt Vector]
;       R2              [Stack Pointer]
;       RE              Points to video RAM at $900
;       RF              Points to program RAM at $800
;       R5              Random Number Generator
;
IOffset = $00                           ; Invader Offset ($800)
POffset = $01                           ; Player offset ($801)
ICount  = $02                           ; Invader Count ($802)
IStatus = $03                           ; Invader Status ($803)
IBase   = $04                           ; Bottom Scrolling Line ($804)
RSeed   = $05                           ; Random Seed ($805)
PScore  = $0B                           ; Player Score ($80B...$80E)
PLives  = $0F                           ; Player lives ($80)
FButton = $10                           ; Fire Button ($810)
;
MTable  = $20                           ; Missile table ($20-$27, Offset,Mask)
                                        ; 4 pairs of 2 byte data. Mask=0 => none

Lives  =  3                             ; Number of lives
BaseSpd = 2                             ; Speed of base

MCount =  8*2                           ; Total number of missiles, x 2

SndTmr =  $CD                           ; $8CD is the Beep Timer
TmrInv =  $CE                           ; Use $8CE as invader timer
TmrPly =  $CF                           ; Use $8CF as player timer

ISLeft = 0                              ; Invader Status Mode (how it is moving)
ISDownLeft = 1
ISRight = 2
ISDownRight = 3
   
        .include "1802.inc"
        .org    400h                    ; where RCA Studio II games start
        .db     >(Start),<(Start)  ; Internal Code call to Machine Code

; ****************************************************************************
;                               Invader Graphics
;
;       .x.....x!.....x..!...x....!             ; $41 $04 $10
;       xxx...xx!x...xxx.!..xxx...!             ; $E3 $8E $38
; ****************************************************************************

InvaderGr:
        .db     $38,$8E,$E3             ; bytes are right to left bottom to top
        .db     $10,$04,$41             ; this corresponds to the above graphic
        .db     $FF                     ; this means "miss a line"

        .db     $28,$8A,$A2
        .db     $10,$04,$41
        .db     $FF

        .db     $10,$04,$41
        .db     $38,$8E,$E3
        .db     $FF

        .db     $10,$04,$41
        .db     $28,$8A,$A2

        .db     0                       ; end of the invaders

; ****************************************************************************
;     Scroll line at RE left 1 pixel. On exit RE points to previous line
; ****************************************************************************

ScrollLeft:
        inc     re              ; get next byte
        ldn     re
        dec     re
        shl                     ; shift into carry
        ldn     re              ; read original byte
        shlc                    ; shift it left, shift in new.
        str     re              ; write back
        inc     re              ; next
        glo     re
        ani     $07
        bnz     ScrollLeft      ; do complete line
        dec     re              ; zero right most pixel
        ldn     re
        ani     $FE
        str     re
        glo     re              ; previous line
        smi     16-1
        plo     re
        sep     r3              ; return
        br      ScrollLeft


; ****************************************************************************
;     Scroll line at RE right 1 pixel. On exit RE points to previous line
; ****************************************************************************

ScrollRight:
        adi     $00             ; clear DF
_SRight0:
        ldn     re              ; read byte
        shrc                    ; shift it right, including old carry
        str     re              ; save it, old carry goes through
        inc     re              ; next byte
        glo     re
        ani     $07             ; done whole row ?
        bnz     _SRight0
        dec     re
        glo     re              ; previous line
        smi     15
        plo     re
        sep     r3              ; return
        br      ScrollRight

; ****************************************************************************
;        XORPlot all the missiles. This is done to move the invaders
; ****************************************************************************

XORMissiles:
        ldi     MTable                  ; RF points to missiles
        plo     rf
        sex     re
_XOR1:  lda     rf                      ; Read offset
        plo     re                      ; RE now points to video byte
        lda     rf                      ; Read bitmask
        bz      _XOR2
        xor                             ; toggle bit
        str     re                      ; update
_XOR2:  glo     rf                      ; done the lot ?
        ani     MCount-1
        bnz     _XOR1                   ; if not, do all 4 possibles
        sep     r3                      ; return
        br      XORMissiles             ; loop back for next call

; ****************************************************************************
;
;                           Start of main program.
;
; ****************************************************************************

Start:  ldi     $08                     ; access data memory
        phi     rf
        ldi     PLives
        plo     rf
        ldi     Lives                   ; set lives to 3
        sex     rf
        stxd
        ghi     r1                      ; zero four score bytes
        stxd
        stxd
        stxd
        stxd

; ****************************************************************************
;                              Start a new level
; ****************************************************************************

NewLevel:

; ****************************************************************************
;                               Clear the screen
; ****************************************************************************

        ghi     r1                      ; D = 0
        plo     re
        sex     re                      ; use RF as index register
_Clear: ldi     $09                     ; RF = $0900
        phi     re                      ; initialise RE.1, stays $09
        ghi     r1                      ; Write zero there
        stxd
        glo     re
        bnz     _Clear

; ****************************************************************************
;                       Draw All Invaders in Start Position
; ****************************************************************************

        ldi     11*8+6                  ; base position of invaders in RF
        plo     re
        ldi     InvaderGr / 256         ; set RE to point to the graphic data
        phi     rc
        ldi     InvaderGr & 255

_HalfLine:
        plo     rc
        plo     rd                      ; save the copy of it.
        lda     rc                      ; copy three bytes
        stxd
        lda     rc
        stxd
        lda     rc
        stxd
        glo     re                      ; get the pointer. if LSBit is
        shr                             ; non-zero, go back.
        glo     rd                      ; and restore the pointer
        bdf     _HalfLine
        dec     re                      ; fix for next line
        dec     re

        ldn     rc                      ; look at next byte
        bz      _EndDrawInv             ; done if zero
        xri     $FF                     ; check if $FF
        bnz     _NoSkip
        inc     rc                      ; if so, skip byte and go up a line
        glo     re
        smi     8
        plo     re
_NoSkip:                                ; go back
        glo     rc                      ; prepare for PLO RE
        br      _HalfLine
_EndDrawInv:

; ****************************************************************************
;                               Draw Shields
; ****************************************************************************

        ldi     9                       ; Fix RE.1 again
        phi     re
        ldi     28*8+7                  ; RF point to shield area
        plo     re
_ShieldLoop:
        ldi     $F0                     ; draw a shield
        stxd
        ldi     $0F
        stxd
        glo     re
        xri     24*8+7                  ; do four rows
        bnz     _ShieldLoop

; ****************************************************************************
;                               Draw Player
; ****************************************************************************

        ldi     30*8                    ; draw the player
        plo     re
        ldi     $70
        str     re
        ldi     31*8
        plo     re
        ldi     $50
        str     re

; ****************************************************************************
;                               Reset data areas
; ****************************************************************************

        ghi     r1                      ; set up variables (start at $800)
        plo     rf

        ldi     9                       ; set invader offset ($800)
        str     rf
        inc     rf
        ldi     2                       ; set player offset ($801)
        str     rf
        inc     rf
        ldi     8*4                     ; set invader count ($802)
        str     rf
        inc     rf
        ldi     ISRight                 ; set invader status ($803)
        str     rf
        inc     rf
        ldi     12*8                    ; set bottom scrolling line ($804)
        str     rf

        ldi     MTable                  ; erase all missiles
        plo     rf
_MClear:ghi     r1                      ; fill the missile table with all zeroes
        str     rf
        inc     rf
        glo     rf
        ani     MCount-1
        bnz     _MClear

        ldi 	LongBranchRoutine/256	; R6 is the long branch routine.
        phi 	r6
        ldi 	LongBranchRoutine&255 
        plo 	r6
        sep 	r6 						; and enter the main timer loop
        dw 		_SetMainTmr

; ****************************************************************************
;
;				Code replacement for LBR, SEP R6 ; DW nnnnn
;
; ****************************************************************************

LongBranchRoutine:
		lda 	r3 						; get high byte
		plo 	ra 						; save in RA.0
		ldn 	r3						; get low byte
		plo 	r3						; put in R3.0
		glo 	ra 						; put high byte in R3.1
		phi 	r3
		sep 	r3 						; and go there.
		br 		LongBranchRoutine 		; it is re-entrant

; ****************************************************************************
;
;                                 MAIN LOOP
;
; ****************************************************************************

		.org 	$500
        br      _SetMainTmr
MainLoop:
        glo     r9                      ; wait for loop to be >= 0
        shl
        bdf     MainLoop
_SetMainTmr:
        ldi     $FE
        plo     r9

; ****************************************************************************
;                               Move Invaders
; ****************************************************************************

MoveInvaders:
        ldi     ICount                  ; read number of invaders
        plo     rf
        ldn     rf
        phi     rb                      ; save in RB.1

        ldi     TmrInv                  ; check invader timer is zero
        plo     rf
        ldn     rf
        bnz    	NoMove

        ghi     rb                      ; use number of invaders as speed
        adi     8
        str     rf

        ldi     SndTmr                  ; short "invaders moving" beep
        plo     rf
        ldi     3
        str     rf
                
        ldi     <(XORMissiles)
        plo     ra
        ldi     >(XORMissiles)
        phi     ra
        sep     ra

        ldi     IStatus                 ; get current status, put in RB.1
        plo     rf
        lda     rf                      ; read it, point RF to IBase
        phi     rb

        ghi     rb                      ; look at current status
        shr                             ; shift LSB right into DF
        bdf      _MoveDown
        bz       _MoveLeft               ; if zero then moving left

_MoveRight:
        ldi     <(ScrollRight)        ; set up to move right
        plo     r4
        ldi     >(ScrollRight)
        phi     r4
        ldi     $17                     ; base pointer for flip test
        br      _HMoveEnd

_MoveLeft:
        ldi     <(ScrollLeft)         ; set up to move left
        plo     r4
        ldi     >(ScrollLeft)
        phi     r4
        ldi     $10
_HMoveEnd:
        plo     rd                      ; save base pointer in RD

        ldi     IOffset                 ; point RF to offset : adjust IOffset
        plo     rf
        sex     rf                      ; use as index
        ghi     rb                      ; get value
        ani     $02                     ; 0 (left) 2 (right)
        smi     $01                     ; -1 (left) 1 (right)
        add                             ; add to IOffset
        str     rf                      ; save it back

        ldi     IBase                   ; point RF to base value
        plo     rf
        ldn     rf                      ; get base for scrolling
        plo     re                      ; set RE = scroll point
        ghi     re
        phi     rd                      ; RD contains the test value

_HScroll:
        sep     r4                      ; scroll a line
        glo     re                      ; reached the top (not top 2 lines)
        ani     $F0
        xri     $F0
        bnz    _HScroll

_TestReverse:
        ghi     r1                      ; now test for the edge (R1.H = 0)
        sex     rd                      ; use RD which is $910 or $917
_TestOr:
        or                              ; OR the video byte
        plo     re                      ; save in RE.0
        glo     rd                      ; advance RD.0 by 8
        adi     $08
        plo     rd
        glo     re                      ; restore RE.0
        bnf     _TestOr                 ; go back if not finished

        glo     rd                      ; look at < byte
        ani     $01                     ; if right this will be '1'
        bnz     _UseBit0
        glo     re                      ; shift bit 7 of RE.0 into bit 0
        shlc
        shlc
        plo     re
_UseBit0:
        glo     re                      ; look at the result
        shr                             ; shift bit 0 into carry
        bnf     ExitMoveInvaders        ; exit if zero
        br      NextState

_MoveDown:
        ldn     rf                      ; read the base value
        plo     re                      ; put in RE
        sex     re                      ; use RE as an index
        lda     re                      ; or all 8 bytes of the line together
        or                              ; +1
        irx
        or                              ; +2
        irx
        or                              ; +3
        irx
        or                              ; +4
        irx
        or                              ; +5
        irx
        or                              ; +6
        irx
        or                              ; +7
        bz      _NoBShift               ; if non-zero the base shift is required

        ldn     rf                      ; if at the bottom, that's it.
        xri     $E0
        bz      NextState
        ldn     rf                      ; add 8 to the base value
        adi     $08
        str     rf

_NoBShift:
        ldn     rf                      ; RE points to the current line
        plo     re                      ; RD points to the previous line
        adi     8
        plo     rd
        ghi     rd
        phi     rd
_ScrollUp:                              ; now scroll by copying RD->RE
        dec     rd
        dec     re
        ldn     re
        str     rd
        glo     re
        bnz     _ScrollUp

; ****************************************************************************
;                             Go to next state
; ****************************************************************************

NextState:
        ldi     IStatus                 ; point RF to status
        plo     rf
        ldn     rf                      ; advance state counter
        adi     $01
        ani     $03
        str     rf

ExitMoveInvaders:
        sep     ra
NoMove:

; ****************************************************************************
;                               Move the Base
; ****************************************************************************

MoveBase:
        ldi     TmrPly                  ; check timer
        plo     rf
        ldn     rf                      ; skip if non-zero
        bnz     ExitMoveBase
        ldi     BaseSpd                 ; reset counter
        str     rf
        ldi     POffset                 ; make RF point to the offset
        plo     rf

        sex     r3                      ; index = program
        out     2                       ; select key 4
        .db     4
        b3      _Left
        out     2                       ; select key 6
        .db     6
        b3      _Right
_ExitMB:br      ExitMoveBase

_Left:  ldn     rf                      ; read player offset
        xri     2                       ; check in range
        bz      _ExitMB
        ldi     <(ScrollLeft)         ; set up to move left
        plo     r4
        ldi     >(ScrollLeft)
        phi     r4
        ldi     $FF                     ; set -ve movement offset
        br      _MovePlayer

_Right: ldn     rf                      ; read player offset
        xri     61                      ; check in range
        bz      _ExitMB
        ldi     <(ScrollRight)        ; set up to move right
        plo     r4
        ldi     >(ScrollRight)
        phi     r4
        ldi     $01
_MovePlayer:
        sex     rf                      ; add movement offset to position
        add
        str     rf
        ldi     $F8
        plo     re
        sep     r4                      ; scroll two lines
        sep     r4
ExitMoveBase:

; ****************************************************************************
;                             Move missiles
; ****************************************************************************

        ghi     rf                      ; Make RC point to RAM
        phi     rc
        ldi     MTable                  ; RF Points to the invader table
        plo     rf
        sep 	r6 						; LBR to missile loop in new page
		dw 		MILoop

        org 	$600
MILoop: lda     rf                      ; Read position
        plo     re                      ; Save in RE.0 [Video Byte]
        ldn     rf                      ; Read Mask
        phi     rb                      ; Save in RB.1 [Mask Bit]
        dec     rf                      ; Fix RF
        sex     re                      ; Use video as index
        bz      _MNoErase               ; don't require erasing
        xri     $FF                     ; make an AND mask
        and                             ; and with screen
        str     re                      ; write it back
_MNoErase:
        ghi     rb                      ; look at mask
        bz     _MCheckNew               ; if zero, check for new missile

_MMoveDown:
        glo     re                      ; move it down
        adi     8
        plo     re
        glo     rf                      ; get missile number
        ani     $0F                     ; now 0 if player missile
        bnz     _NotIMissile
        glo     re                      ; if so, it is going up.
        smi     16
        plo     re
_NotIMissile:
        glo     re                      ; check if reached top line
        ani     $F8
        bz      MIKill                  ; if reached the top line, die

        ghi     rb                      ; get mask
        and                             ; and with screen
        bnz    EnterCollide             ; if non zero, a collision

        glo     re                      ; check if reached line at $9F0
        ani     $F8
        xri     $F0
        bz      MIKill                  ; if so, kill it (missile missed)
        br      MINext

MIKill: ghi     r1                      ; zero the mask
        phi     rb
MINext: sex     re                      ; video as index
        ghi     rb                      ; look at mask
        bz    	_MNoDraw
        or                              ; or with screen
        str     re                      ; write back
_MNoDraw:
        glo     re                      ; write it back
        str     rf
        inc     rf                      ; point at mask byte
        ghi     rb
        str     rf
        inc     rf                      ; point at next

        glo     rf                      ; reached the end ?
        ani     (MCount-1)
        bnz    	MILoop                  ; go and do all of them
        sep 	r6 						; loop back.
       	dw      MainLoop

; ****************************************************************************
;          Come here when the mask is zero : check for new missile
; ****************************************************************************

_MCheckNew:
        glo     rf                      ; look at missile
        ani     $0F                     ; check if player
        bz      _MCheckPlyr             ; if so, check for fire etc.

        ldi     IOffset                 ; read the invaders position
        plo     rc
        ldn     rc
        plo     ra                      ; save in RA.0

        ldi     RSeed
        plo     rc
        ldn     rc
        adi     7
        str     rc
        ghi     r1                      ; point to $00nn
        phi     r5
        glo     ra
        sex     r5
        xor
        inc     r5
        sex     rc
        xor

        phi     ra                      ; save number
        ani     $1F                     ; only fire one in 8 times
        bnz     MIKill

        ghi     ra                      ; upper 3 bits offset position
        shr                             ; put them in the 3 <est bits
        shr
        shr
        shr
        shr
        shl                             ; x 2 (we actually want x 6 in total)
        dec     r2                      ; save in stack space
        str     r2
        sex     r2                      ; access the stack
        glo     ra                      ; add to the base position
        add                             ; 3 lots of x2 = x6
        add
        add
        plo     ra                      ; update the base position
        inc     r2                      ; fix the stack back

        ldi     IBase                   ; point RC to the base
        plo     rc
        glo     ra                      ; get the position
        shr                             ; divide it by 8
        shr
        shr
        sex     rc                      ; add the base position to it
        add
        adi     8                       ; add 8 more to it
        plo     re                      ; RE now points to it

        glo     ra                      ; use 3 <er bits as an index
        ori     $F8                     ; into the table at $7F8 to get
        plo     ra                      ; the mask out.
        ldi     $07
        phi     ra
        ldn     ra                      ; read the mask
        phi     rb                      ; put in RB.H
        sex     re
_MoveUp:ghi     rb                      ; read mask
        and                             ; and with screen
        bnz    _MMoveDown              	; if non-zero move it down and continue
        glo     re                      ; subtract 8 (move up one square)
        smi     8
        plo     re
        ani     $F8                     ; reached top line ?
        bnz     _MoveUp
        br      MIKill                 	; if so, kill it. There was no baddie
                                        ; in that slot.
_MCheckPlyr:
        ldi     FButton                 ; point RF to fire button
        plo     rc
        sex     r3                      ; X = P
        out     2                       ; test key 0
        .db     0
        ldn     rc                      ; read fire
        shl                             ; shift old left
        bn4     _NoFirePressed
        ori     1                       ; if fire pressed LSB = 1
_NoFirePressed:
        ani     3                       ; only interested in last two states
        str     rc                      ; write back
        xri     1                       ; if current 1, last 0
        bnz    	MINext                  ; then drop through to fire

        ldi     POffset                 ; point RC to player position
        plo     rc
        ldn     rc                      ; read it
        shr                             ; divide by 8
        shr
        shr
        ani     $07
        adi     $E8                     ; work out initial position
        plo     re
        ldn     rc                      ; get it again
        ori     $F8                     ; pointer into table at $7F8
        plo     rc
        ldi     $07
        phi     rc
        ldn     rc                      ; read the pixel position
        phi     rb                      ; put into mask position
        br     	MINext

        org 	$6FE
EnterCollide:
		ldi 	0
; ****************************************************************************
;                              Check for collision
; ****************************************************************************
		org 	$700
_MICollide:
        glo     rf                      ; check if player missile collision
        ani     $0F
        bz      _PMCollide

        glo     re                      ; check if player-inv missile collision
        ani     $F0
        xri     $F0
        bz      _KillPlayer

_HitShield:
        ghi     rb                      ; if not, clear the relevant pixel
        xri     $FF                     ; (collision with shields or perhaps
        sex     re                      ; use video as index
        and                             ;  the player bullet) and kill it.
        str     re
_GoMIKill:
		sep 	r6        				; long branch to kill missiles
       	dw     	MIKill

_KillPlayer:
        ldi     128                     ; this forces a delay of about 2.5secs
        plo     r9
        ghi     rf                      ; point RC at the RAM
        phi     rc
        ldi     SndTmr                  ; long beep
        plo     rc
        ldi     60
        str     rc
        ldi     PLives                  ; point RC at lives
        plo     rc
        ldn     rc                      ; decrement lives
        smi     1
        str     rc
        bz     	_EndGame
        br     	_GoMIKill

_PMCollide:
        glo     re                      ; get the address
        adi     7*8                     ; check shield hit ?
        bdf     _HitShield              ; if in shield region pop shield

        ghi     rf                      ; set up RC to point to missile table
        phi     rc                      
        ldi     MTable+2                ; missing out the player missile
        plo     rc
        sex     rc                      ; use that as the index register
_CheckHitMissile:
        glo     re                      ; first compare the position
        xor
        bnz     _CHMNext
        inc     rc                      ; second compare the mask
        ghi     rb
        xor
        bz     	_GoMIKill               ; if it is equal to the mask, kill it.
        dec     rc
_CHMNext:
        inc     rc                      ; move to the next one
        inc     rc
        glo     rc
        ani     (MCount-1)              ; do for all the enemy missiles
        bnz     _CheckHitMissile

        glo     re                      ; down one row
        adi     8
        plo     re
        ldi     2                       ; move back two pixels
        plo     rc
_ShiftRight:
        ghi     rb                      ; shift mask right
        shr
        bnf     _NoCBack
        inc     re                      ; if carry out then next cell
        ldi     $80                     ; mask = $80
_NoCBack:
        phi     rb
        dec     rc
        glo     rc
        bnz     _ShiftRight

        ldi     3                       ; do 3 rows
        plo     ra
        glo     re                      ; r7.0 := RE.0
        plo     r7
        ghi     rb                      ; r7.1 := RB.1
        phi     r7

_NextLine:
        ghi     r7                      ; copy the mask back
        phi     rb
        ldi     5                       ; erase and go left 5 times
        plo     rc
_ShiftLeft:
        ghi     rb                      ; erase the pixel
        sex     re
        xri     $FF
        and
        str     re
        ghi     rb                      ; shift mask left
        shl
        bnf     _NoCForward             ; if carry out
        dec     re                      ; previous cell
        ldi     $01                     ; reset the mask
_NoCForward:
        phi     rb
        dec     rc
        glo     rc
        bnz    	_ShiftLeft
        glo     r7                      ; get video address
        smi     8
        plo     r7                      ; update both working and fixed
        plo     re
        dec     ra                      ; do this for 3 lines up
        glo     ra
        bnz    	_NextLine

        ghi     rf                      ; RC points to ICount
        phi     rc
        ldi     SndTmr                  ; Beep
        plo     rc
        ldi     12
        str     rc
        ldi     ICount
        plo     rc
        ldn     rc                      ; decrement invader count
        smi     1
        str     rc
        bz      _GoNewLevel             ; if zero then new level (1 fewer on score)

        ldi     PScore+3                ; Point RC to the score
        plo     rc
_IncScore:
        ldn     rc                      ; read next digit
        adi     1                       ; and increment by 1
        str     rc
        xri     10                      ; reached 10
        bnz    	_GoMIKill               ; else kill the invader, continue
        ghi     r1                      ; zero that one
        str     rc
        dec     rc                      ; do previous digit
        br      _IncScore

_GoNewLevel:
		sep 	r6 						; long branch to new level.
		dw  	NewLevel

; ****************************************************************************
;                               Game Over
; ****************************************************************************

NumIndexTab =   $0210                   ; Table of LSB of digit addresses

_EndGame:
        ghi     r1                      ; D = 0
        plo     re
        sex     re                      ; use RF as index register
_Clear2:ldi     $09                     ; RF = $0900
        phi     re                      ; initialise RE.1, stays $09
        ghi     r1                      ; Write zero there
        stxd
        glo     re
        bnz     _Clear2
        ldi     8*8+2                   ; Position score graphic
        plo     re
        ldi     PScore                  ; Point RF to the score
        plo     rf
_ScoreLoop:
        lda     rf                      ; read next score digit
        adi     <(NumIndexTab)        ; point into table
        plo     rc
        ldi     >(NumIndexTab)
        phi     rc
        ldn     rc                      ; read the offset
        plo     rc                      ; RC now points to the graphic data
        ldi     5                       ; do 5 lines
        plo     rd
_DigitLoop:
        lda     rc                      ; read graphic
        str     re                      ; write to screen
        glo     re                      ; go down one line
        adi     8
        plo     re
        dec     rd                      ; loop round 5 times
        glo     rd
        bnz     _DigitLoop
        glo     re                      ; next position
        adi     -40+1
        plo     re
        glo     rf                      ; reached the end
        ani     $0F
        bnz     _ScoreLoop

WaitP10:sex     r3                      ; use PC as Index
        out     2                       ; scan for key 0
        .db     0
_WaitK0:bn3     _WaitK0                 ; wait for key 0
        sep 	r6
        dw      Start                   ; and restart

        .org    $07F8                   ; this is a bitmask table
        .db     $80,$40,$20,$10,$08,$04,$02,$01
        .end
