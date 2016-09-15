; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;											KABOOM - For the RCA Studio 2 (1802 Assembler)
;											==============================================
;
;	Author : 	Paul Robson (paul@robsons.org.uk)
;	Tools :		Assembles with asmx cross assembler http://xi6.com/projects/asmx/
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;       Reserved for Studio 2 BIOS : 	R0,R1,R2,R8,R9,RB.0
;
;		Other usage
;		===========
;		R2 		Used for Stack, therefore R2.1 always points to RAM Page.
;       R3      PC (lowest level)
;		R5 		Draw Bat Subroutine
;		R7 		Draw Bomb Subroutine
;		RF 		Random Number Seed
;
;
; 		Studio 2 Specifics/Porting advice
;	 	=================================
;
;			(a) R9 incremented every Frame. This can be implemented in the video routine.
;			(b) $08CD is a beeper timer, also implementable in the video routine. When set to a non-zero value it beeps for that many frames.
;			(c) The keyboard is read by outing the digit to port 2 and testing EF3 for '1'. On Cosmac VIP this should test for '0'. Elf totally different.
; 			(d) On S2 User RAM is at $800 and Video RAM at $900. The program doesn't care itself.
;			(e) On S2 the code starts at $400 and begins with a 'Chip8' instruction machine code call e.g. 0abc 
; 			(f) The high score uses a table at $210 which is 10 values, each of which is an LSB of an address in $2xx which is the start of
; 				5 rows of pixel data defining an integer.
;
; ***************************************************************************************************************************************

RamPage	= 8													; 256 byte RAM page used for Data ($800 on S2)
VideoPage = 9												; 256 byte RAM page used for Video ($900 on S2)

BombList = 0 	 											; Bomb list at position 0 on RAM Page
BombRecSize = 5 											; Number of Bytes per Bomb Record
BombMax = 10 												; Maximum number of Bombs supported.
BombListEnd = BombMax * BombRecSize

LoseFlag = $80 												; Set to '1' when you have lost.
SyncCounter = $81 											; used to sync game speed.
MoveCounter = $82 											; used to sync base moves
Lives = $83 												; Lives (3-0) 
BatPosition = $84 											; Bat Position (0-255)
BatVelocity = $85 											; Bat velocity (-8 ... 8)
ExtraLifeFlag = $86 										; set to '1' when extra lfe claimed (e.g. ticked over 1000 points)
BombsToDrop = $87 											; number of bombs to drop.
BombsToHit = $88 											; counter of number of bombs to hit 
BombScoreEach = $89											; Score per bomb 1-9 only 
Score = $8A 												; 6 bytes of score, LSB first. 
Level = $90 												; current game level (1-9)
BomberPosition = $91 										; current bomber position 

Studio2BeepTimer = $CD 										; Studio 2 Beep Counter

BatSpeed = 4 												; the number of moves of bombs per bat move.
BombMovesPerFrame = 4 										; no of attempted bomb moves per frame.

; ***************************************************************************************************************************************
;
;												Bomb Data Structure
;
;		+0 		Horizontal Position in nibbles (0-15). Bit 7 set means not in use.
;		+1 		LSB of physical screen position of top line
;		+2 		LSB of graphic to draw.
;		+3 		Speed (0-255)
;		+4 		Speed Counter - add Speed to it, move on DF.
;
; ***************************************************************************************************************************************

; ***************************************************************************************************************************************
;
;												Studio 2 Boot Code
;	
; ***************************************************************************************************************************************

    	.include "1802.inc"
    	.org    400h										; ROM code in S2 starts at $400.
StartCode:
    	.db     >(StartGame),<(StartGame)					; This is required for the Studio 2, which runs from StartGame with P = 3

; ***************************************************************************************************************************************
;
;					Bomb Graphic : stay here, must all be on same page. Each graphic is duplicated in each half of the byte
;
; ***************************************************************************************************************************************

BombGraphic1:
		.db		$44,$22,$66,$FF,$66,0						; Bomb Graphic #1 (duplicated in both halves of byte)
BombGraphic2:	
		.db		$22,$44,$66,$FF,$66,0						; Bomb Graphic #2 (duplicated in both halves of byte)
Explosion:
		.db 	$99,$66,$99,$66,$99,0						; Explosion (duplicated in both halves of byte)

; ***************************************************************************************************************************************
;
;								 Bat Graphic : 8 x 4 bytes, each one is shifted right successively one bit
;
; ***************************************************************************************************************************************

BatGraphic:
		.db 	$7C,$00, 	$AA,$00 						; Shift 0 Right
		.db 	$3E,$00, 	$55,$00 						; Shift 1 Right
		.db 	$1F,$00, 	$2A,$80 						; Shift 2 Right
		.db 	$0F,$80, 	$15,$40 						; Shift 3 Right
		.db 	$07,$C0, 	$0A,$A0 						; Shift 4 Right
		.db 	$03,$E0, 	$05,$50 						; Shift 5 Right
		.db 	$01,$F0, 	$02,$A8 						; Shift 6 Right
		.db 	$00,$F8, 	$01,$54 						; Shift 7 Right

; ***************************************************************************************************************************************
;
;	Draw Bomb Graphic pointed to by R4. Fast because uses nibl resolution, so bombs are xor-drawn in bytes - this is why there are 16
;	places across the screen, they represent 8 x 2 nibbles.
;
;	Breaks : RD,RE : Draws at approximately 750 per second.
;	Returns to : R6
;
; ***************************************************************************************************************************************

DrawBomb:
		ldn 	r4 											; read bomb horizontal
		shl 												; shift bit 7 into DF
		bdf 	DB_Exit 									; if set draw nothing.

		lda 	r4 											; Read the Bomb Horizontal (0-15) into D, advance to position (+1)
		shr 												; shift the least significant bit into DF
		ldi 	$0F 										; mask to use is $0F
		bdf		DB_RightHandNibble
		ldi 	$F0											; if DF == 0, e.g. use left half of byte.
DB_RightHandNibble:
		dec 	r2 											; save mask on stack free space.
		str 	r2 											; [R2] is the mask to be used.

		lda 	r4 											; put R4 in RE.0 e.g. the drawing address, advance to graphic (+2)
		plo 	re		
		ldi 	VideoPage 									; RE.1 = Video Page, so RE points to drawing byte
		phi 	re

		ldi 	>BombGraphic1 								; make RD point to the bomb graphic
		phi 	rd
		ldn 	r4 				
		plo 	rd

		dec		r4 											; fix the 2 LDAs so that R4 has not changed.
		dec 	r4

DB_PlotBomb:
		lda 	rd 											; read graphic and advance RD
		bz 		DB_DrawCompleted							; if zero, end of bomb draw.
		sex 	r2 											; and with the mask on the stack byte
		and
		sex 	re 											; xor with the video page
		xor
		str 	re 											; and write back to the video.
		glo 	re 											; add 8 to re, i.e. next row down.
		adi 	8
		plo 	re
		bnf 	DB_PlotBomb 								; plot another bomb if NOT carry out (e.g. off the bottom of the screen)

DB_DrawCompleted:
		inc 	r2 											; reclaim the stack space.
DB_Exit:
		sep		r6 											; return
		br 		DrawBomb


; ***************************************************************************************************************************************
;
;								   Move Bomb pointed to by R4 down. Manages about 330 bombs / second
;
;	Breaks : RD,RE (Draw subroutine)
;	Returns: R3
;
;	Note: this also time syncs. If a sufficient number of calls have occurred, it syncs by waiting for R9 to go +ve. R9 increments
; 		  in the Video Redraw section.
;
; ***************************************************************************************************************************************

MoveBomb:
		ldn 	r4 											; read R4 (X position)
		shl 												; if bit 7 set (bomb not in play)
		bdf		MB_NotMoving								; don't move it.

		inc 	r4 											; point to speed (+3)
		inc 	r4
		inc 	r4
		lda 	r4 											; load speed, point to speed counter (+4)
		sex 	r4 											; add speed to speed counter
		add
		stxd 												; store back, point to (+3)	
		dec 	r4 											; set R4 back to +0
		dec 	r4
		dec 	r4
		bnf 	MB_NotMoving								; not moving this time


		sep 	r7 											; erase the bomb
		inc 	r4 											; access the position (offset 1())
		ldn 	r4 											; add 8 (one line down) to it
		adi 	8
		str 	r4

		adi 	$10 										; adding $10 gives DF for D = $F0..$FF
		bnf 	MB_NotLost
		ghi		r4 											; point RE to Lost Flag.
		phi 	re
		ldi 	LoseFlag
		plo 	re 
		str 	re 											; LoseFlag set to non-zero (BombList at $00)
MB_NotLost:

		inc 	r4 											; point to graphic (+2)
		ldn 	r4 											; switch from one to other
		xri 	BombGraphic1 ^ BombGraphic2
		str 	r4 											; write graphic back.
		dec 	r4	
		dec 	r4 											; fix R4 back to point to the record	

		sep 	r7 											; and draw the bomb.

MB_NotMoving:
		ghi 	r2 											; set RE to point to Move Counter
		phi 	re 											; this counts towards zero, when it is zero
		ldi 	MoveCounter 								; the bat can move. The bat routine resets it.
		plo 	re
		ldn 	re 											; read it
		bz 		MB_MoveCounterZero 						
		smi 	1 											; decrement and write back if non-zero
		str 	re 											; when it gets to zero the bat can move.
MB_MoveCounterZero:

		ldi 	SyncCounter 								; we *always* decrement the sync counter, point RE to it
		plo 	re 											
		ldn 	re 											; read the sync counter
		bz 		MB_SyncWithFrameCounter 					; if zero, synchronise with frame counter.
		smi 	1 											; subtract one if non zero.
		str 	re 											; and write back

MB_Exit:
		sep 	r3

; ---------------------------------------------------------------------------------------------------------------------------------------

MB_SyncWithFrameCounter:
		ldi 	BombMovesPerFrame							; Number of moves per frame.
		str 	re 											; reset the sync counter
MB_SyncWait:
		ghi 	r9 											; wait for R9 to be $00
		bnz 	MB_SyncWait	
		ldi 	$FF 										; reset R9 to -1
		phi 	r9
		plo 	r9
		br 		MB_Exit

; ***************************************************************************************************************************************
;
;													Draw Bat Graphic
;
;	Breaks RD.RE.R4
;	Returns to R6
;
; ***************************************************************************************************************************************

DrawBat:
 		ldi 	Lives 										; Point RD to Lives (number of vertical bats to draw)
		plo 	rd
		ghi 	r2
		phi 	rd
		lda 	rd 											; read lives and increment
		bz 		DBT_Exit  									; if zero do nothing.
		plo 	r4 	 										; save in R4.0
		ldn	 	rd 											; read Bat Position (one after lives) which is 0-255
		plo 	re 											; save in RE.0
		shr 												; divide 32 - value now 0-8 e.g. the byte to write in
		shr 												
		shr
		shr
		shr
		adi 	24*8 										; this is now the byte position on the screen.
		plo 	rd 											; save in RD.0
		ldi 	VideoPage 									; Make RD point to the first drawing position
		phi 	rd

		glo 	re 											; Retrieve 0-255 value
		ani		$1C											; Now it's an offset in gfx table (/4 to make pixel x4 because 4 bytes per graphic :) )
		adi 	<BatGraphic 								; Make RE point to the appropriate bat graphic for the shift
		plo 	re
		phi 	r4 											; save in R4.1
		ldi 	>BatGraphic 								
		phi 	re

		sex 	rd 											; RE is the index register

DBT_Loop:	
		lda 	re 											; read graphic and bump
		xor 												; xor with screen
		str 	rd
		inc 	rd 											; next horizontal byte, do the same.
		lda 	re 											
		xor
		str 	rd
		glo 	rd 											; add 7 to RD e.g. next line down from start
		adi 	7
		plo 	rd
		lda 	re 											; duplicate of above, 2nd line of graphic
		xor 												
		str 	rd
		inc 	rd
		lda 	re
		xor
		str 	rd
		glo 	rd 											; except we add 15 to RD giving a line gab.
		adi 	15
		plo 	rd
		ghi 	r4 											; restore the graphic pointer from R4.1 so the graphic pointer is fixed up.
		plo 	re 											
		dec 	r4 											; decrement 'lives' counter
		glo 	r4
		bnz		DBT_Loop 									; go back if not clear.
DBT_Exit:
		sep 	r6
		br 		DrawBat


; ***************************************************************************************************************************************
;	
;	Move Bat. This is not a simple left right. The buttons apply acceleration to a velocity which is added to the position. The
;	velocity damps towards zero. If you have a paddle, everything between the two 'sep r5' calls (erase and draw bat) can be
;	replaced, just putting the value read from the paddle in [BatPosition]
;
;	Breaks R4,RD,RE
;	Returns R3.
;
; ***************************************************************************************************************************************

MVB_Exit:
		sep 	r3 

MoveBat:
		ghi 	r2 		 									; point R4 to Move Counter
		phi 	r4
		ldi 	MoveCounter
		plo 	r4
		ldn 	r4 											; if it is non zero don't move.
		bnz 	MVB_Exit
		ldi 	BatSpeed									; reset move counter, determines bat speed.
		str 	r4 											; number of move attempts per bat move.
		sep 	r5 											; erase bat

		ghi 	r2 											; point R4 at Velocity
		phi 	r4
		ldi 	BatVelocity
		plo 	r4

		sex 	r2 											; X = R2
		dec 	r2 											; store 4 on TOS
		ldi 	4
		str 	r2
		out 	2 											; select key 4
		b3 		MVB_AccLeft 								; left code if pressed
		dec 	R2 											; store 6 on TOS
		ldi 	6
		str 	r2
		out 	2 											; select key 6
		b3 		MVB_AccRight 								; right code if pressed

															; no keys pressed, deaccelerate velocity to zero.
		ldn 	r4 											; read velocity
		bz 		MVB_AddVelocity 							; if zero, no need to deaccelerate
		shl 												; put velocity sign in DF
		ldi 	-1
		bnf 	MVB_DeAcc2 									; if +ve use -1
		ldi 	1
MVB_DeAcc2:
		sex 	r4 											; add the deacceleartion value to R4
		add
MVB_UpdateVelocity:
		str 	r4
		br 		MVB_AddVelocity

MVB_AccLeft: 												; accelerate left.
		ldn 	r4 	 										; -2 from velocity
		smi 	2
		str 	r4
		ani 	$F8											; check at limit
		xri 	$F8
		bz		MVB_AddVelocity
		ldi 	-8
		br 		MVB_UpdateVelocity

MVB_AccRight: 												; accelerate right
		ldn 	r4 	 										; +2 to velocity
		adi 	2
		str 	r4
		ani 	$F8
		bz		MVB_AddVelocity
		ldi 	8
		br 		MVB_UpdateVelocity

MVB_AddVelocity:
		ldn		r4 											; read velocity
		dec 	r4 											; point R4 at bat position.
		dec 	r2 											; store velocity on stack
		sex 	r2
		str 	r2
		bz 		MVB_NoMove 									; if zero, not moving.
		shl 												; shift MSB into DF
		bdf 	MVB_MoveLeft  								; if set, velocity is -ve, so move left.

		ldn 	r4 											; get bat position (moving right)
		add 												; add velocity stored on stack.
		str 	r4 											; write back
		adi 	24 											; reached RHS ?
		bnf 	MVB_NoMove 									; if not, then completed
		ldi 	255-24 										; if yes, put at RH Edge
		br 		MVB_Update

MVB_MoveLeft:												; get bat position (moving left)
		ldn 	r4
		add 												; add velocity
		bdf 	MVB_Update 									; update and save if space to move
		ldi 	0 											; otherwise left hand edge.
MVB_Update:
		str 	r4 											; update bat position
MVB_NoMove:
		inc 	r2 											; restore stack.

		ldi 	ExtraLifeFlag 								; point R4 to the extra life flag
		plo 	r4
		ldn 	r4 											; read it
		bz 		MVB_NoExtraLife 							; if zero then no extra life
		ldi 	0 											; clear extra life flag
		str 	r4
		ldi 	Lives 										; point R4 to lives
		plo 	r4
		ldn 	r4 											; read lives
		xri 	3 		 									; already have 3 ?
		bz 		MVB_NoExtraLife 							; can't have any more 
		ldn 	r4 											; increment lives
		adi 	1
		str 	r4
MVB_NoExtraLife:
		sep 	r5 											; redraw bat

		sep 	r3 											; adn ex

; ***************************************************************************************************************************************
;
;				Checks for collisions - removes and disables colliding Bombs, incrementing score 
;
;	Breaks:	R4,RA,RD,RE
;	Returns to R3
;
; ***************************************************************************************************************************************

CheckCollision:
		ghi 	r2 										; Point RA to the Bat Position
		phi 	r4
		phi 	ra
		ldi 	BatPosition
		plo 	ra
		ldi 	BombList 								; R4 points to the bomblist.
		plo 	r4
CC_Loop:
		ldn 	r4 										; read first bomb position
		shl												; shift MSB into DF
		bdf		CC_Next 								; if set do next

		inc 	r4 										; point R4 to the address which is a byte position
		ldn 	r4 										; get that byte position
		ani 	7
		shl 											; it is now a nibble position (x 2)
		dec 	r4 										; point back at the nibble offset (0/1)
		sex 	r4 					
		add 											; add that, we now have a nibble position 0-15		
		shl 											; multiply it by 16
		shl
		shl
		shl 
		adi 	8										; screen width 256, pixel width therefore 4, 2 pixels therefore 8.
		sex 	ra
		sm 	 	 										; subtract bat position from it.
		smi 	14 										; subtract half the bat width (3.5 pixels)
		bdf 	CC_NotNegative 							; if it's not negative skip next instruction
		sdi 	0 										; negate it,1 to balance collision
CC_NotNegative:											; D now has |batx - bombx|
		smi		22										; bat width 7 pixels, or 28 units, ball width 4 or 16 units, gap is half of 28+16 = 22
		bdf 	CC_Next 								; if >= 22 then no collision.

		inc 	r4 										; read the bomb byte position
		ldn 	r4
		dec 	r4
		smi		20*8 									; is it far enough down ?
		bnf 	CC_Next 								; if not, skip collision

		sep 	r7 										; erase bomb
		ldi 	$FF 									; mark it as deleted.
		str 	r4

		ghi 	r4 										; point RE to bombs to hit.		
		phi 	re	
		ldi 	BombsToHit
		plo 	re
		ldn 	re 										; decrement bombs-to-hit score
		smi 	1
		str 	re 										; completed level when this reaches zero.
		inc 	re 										; point RE at points per hit 
		lda 	re 										; read that in, bump to score LSB
CC_IncrementScore: 
		sex		re 										; add to next digit of score.
		add 	
		str 	re
		smi 	10 										; is it >= 10
		bnf 	CC_ScoreEnd
		str 	re 										; write it back
		inc 	re 										; move to the next digit
		glo 	re 										; look at the LSB
		xri		Score+3 								; carrying into 1000's ? (+0 = 1, +1 = 10, +2 = 100,+3 = 1000) 	
		bnz		CC_NoExtraLife   						; technically going beyond 999,999 could cause a problem. Won't happen :)

		ghi 	re 										; point Rd to the extra life flag
		phi 	rd
		ldi 	ExtraLifeFlag
		plo 	rd 
		ldi 	1 										; set the extra life flag to '1'.
		str 	rd

CC_NoExtraLife:
		ldi 	1 										; and complete the carry.
		br 		CC_IncrementScore

CC_ScoreEnd:
		ldi 	Studio2BeepTimer 						; short beep.
		plo 	re
		ldi 	3
		str 	re

CC_Next:glo 	r4 										; point to next bomb record
		adi 	BombRecSize 					
		plo 	r4
		xri 	BombListEnd 							; reached the end.
		bnz 	CC_Loop
		sep 	r3

; ***************************************************************************************************************************************
;
;									LFSR Random Number Generator (seed in RF throughout)
;
; Returns to : R6
;
; ***************************************************************************************************************************************

Random:	ghi 	rf 										; galois LFSR. Shift seed right into DF
		shr
		phi 	rf
		glo 	rf
		shrc
		plo 	rf
		bnf 	RN_NoXor
		ghi 	rf 										; if LSB was set then xor high byte with $B4
		xri 	$B4
		phi 	rf
RN_NoXor:
		glo 	rf
		sep 	r6
		br 		Random

; ***************************************************************************************************************************************
;
;													Initialise a Level
;	
;	Breaks RD,RE,R4
;	Returns R3.
;
; ***************************************************************************************************************************************

InitialiseLevel:
		ldi 	VideoPage 									; clear video RAM
		phi 	r4
		ldi 	0
		plo 	r4
IL_Clear:
		ldi		0
		str 	r4
		inc 	r4
		glo 	r4
		bnz 	IL_Clear
		ghi 	r2 											; point R4 to Bomb List
		phi 	r4

		ldi 	BombList 									; erase the bomb list (fill with $FF)
		plo 	r4 
IL_ClearBombList:
		ldi 	$FF
		str 	r4
		inc 	r4
		glo 	r4
		xri 	BombListEnd
		bnz 	IL_ClearBombList

		ldi 	Level 										; put level into RE.0
		plo 	r4
		ldn 	r4
		plo 	re

		ldi 	LoseFlag									; set all the control values.
		plo 	r4

		ldi 	0 											; clear lose flag ($80)
		str 	r4
		inc 	r4
		str 	r4  										; clear sync counter ($81)
		inc 	r4
		str 	r4 											; clear move counter ($82)
		inc 	r4
		inc 	r4
		ldi 	128 										; put bat in the middle ($84)
		str 	r4
		ldi 	0 											; set bat velocity to zero ($85)
		inc 	r4
		str 	r4
		inc 	r4
		str 	r4 											; clear extra life flag ($86)
		inc 	r4

		glo 	re 											; retrieve level in RE.0
		shl 												; calculate number as 24 + level * 4 (32..60 per level 1-9)
		shl 												; max level is 50 :)
		adi 	24
		str 	r4
		inc 	r4
		str 	r4
		inc 	r4
		glo 	re 											; points per level == level # stored in RE.0
		str 	r4

		ldi 	BomberPosition 								; reset the bomber position.
		plo 	r4
		ldi 	8
		str 	r4

		sep 	r5 											; draw the bat

		sex 	r2
		dec 	r2 											; select key 0
		ldi 	0
		str 	r2
		out 	2
IL_WaitGo: 													; wait for the 'go' key.
		inc 	rf 											; seed the RNG.
		bn3 	IL_WaitGo

		ldi 	$FF 										; reset the R9 synchroniser.
		phi 	r9
		plo 	r9

		sep 	r3

; ***************************************************************************************************************************************
;
;													Create a new bomb (if available)
;
; ***************************************************************************************************************************************

CreateBomb:
		ghi 	r2 		 									; point RD to Move Counter
		phi 	rd
		phi 	r4
		ldi 	MoveCounter
		plo 	rd
		ldn 	rd 											; if it is non zero don't move.
		bnz 	CBM_Exit
		ldi 	BombsToDrop 								; any more bombs to drop ?
		plo 	rd
		ldn 	rd
		bz 		CBM_Exit 			 						; if bombs to drop zero then exit.

		ldi 	>Random 									; set RA to point to the random code
		phi 	ra
		ldi 	<Random
		plo 	ra

		ldi 	BomberPosition 								; point RD to bomber position
		plo 	rd
		ldn 	rd 											; read it, put in RE.0
		plo 	re
		sep 	ra 											; random number
		ani 	2 											; now 0 or 2
		smi 	1 											; now -1 or 1
		sex 	rd 											; add to position
		add
		str 	rd 											; write back
		ani 	$F0 										; in range 0-15
		bz 		CMB_BomberOk
		glo 	re 											; no restore position 
		str 	rd
CMB_BomberOk:

		sep 	ra 											; get a random number
		ani 	15 											; one time in 15
		bnz		CBM_Exit

		ldi 	BombList 									; point R4 to BombList
		plo 	r4
CBM_Find:
		ldn 	r4 											; read first byte
		shl  												; if bit 7 set it is free, so use it.
		bdf 	CBM_Found
		glo 	r4 											; advance to next bomb
		adi 	BombRecSize
		plo 	r4
		xri 	BombListEnd 								; if not reached end try again
		bnz 	CBM_Find
		br 		CBM_Exit 									; no free slots, exit


CBM_Found:
		ldi 	BomberPosition 								; RD points to bomber position
		plo 	rd 
		ldn 	rd 											; read bomber position
		ani 	1 											; left or right half
		str 	r4 											; save in nibble record (+0)
		inc 	r4
		ldn 	rd 											; read bomber position
		shr 												; put in correct range
		str 	r4 											; save in position (+1)
		inc 	r4


		ldi 	<BombGraphic1 								; save bomb graphic 1 pointer in graphic (+2)
		str 	r4
		inc 	r4

		ldi 	Level 										; point RD to level
		plo 	rd
		ldn		rd 											; read level
		shl 												; multiply by 16
		shl
		shl
		shl
		adi 	90 											; add 90: L1 = 106, L9 = 234
		bnf		CBM_NoMaxSpeed
		ldi 	255 										; max out at 255, as fast as you can go.
CBM_NoMaxSpeed:
		str 	r4 											; save speed in speed (+3)

		dec 	r4 											; point to start of record.
		dec 	r4
		dec 	r4
		sep 	r7 											; draw it

		ldi 	BombsToDrop 								; decrement bombs to drop counter
		plo 	r4
		ldn 	r4
		smi 	1
		str 	r4

CBM_Exit:
		sep 	r3

; ***************************************************************************************************************************************
;
;												Draw All Bombs (or Erase All Bombs)
;
;	Breaks : RD,RE (Draw subroutine) R4
;	Returns: R3
;
; ***************************************************************************************************************************************

ExplodeAllBombs:
		ldi 	RamPage 									; make R4 point to the Bomb List
		phi 	r4
		ldi 	BombList
		plo 	r4
EAB_Loop:
		sep 	r7 											; erase the bomb
		inc 	r4 											; point to graphic
		inc 	r4
		ldi 	<Explosion 									; put explosion there.
		str 	r4
		dec 	r4
		dec 	r4
		sep 	r7 											; redraw the bomb
		glo 	r4 											; advance R4 to the next bomb record
		adi 	BombRecSize
		plo 	r4
		xri 	<BombListEnd 								; reached end of the bomb list ?
		bnz 	EAB_Loop
		sep 	r3

; ***************************************************************************************************************************************
;
;											Write byte D to RE. Add 8 to RE
;
; ***************************************************************************************************************************************

WriteDisplayByte:
		str 	re 											; save result 
		glo 	re 											; down one row
		adi 	8
		plo 	re
		sep 	r3
		br 		WriteDisplayByte

; ***************************************************************************************************************************************
;
;														M A I N    P R O G R A M
;
; ***************************************************************************************************************************************

		.org	StartCode+$2E0

; ---------------------------------------------------------------------------------------------------------------------------------------		
; 														Set everything up
; ---------------------------------------------------------------------------------------------------------------------------------------		

StartGame:
		ldi 	$0FF 									; initialise the Stack to $2FF
		plo		r2 										; from $2CF.
		ldi 	RAMPage
		phi 	r2

		ldi 	>DrawBomb 								; make R7 point to the bomb drawing routine
		phi 	r7 										; keeps this throughout.
		ldi 	<DrawBomb								
		plo 	r7
		ldi 	>DrawBat 								; make R5 point to the bat drawing routine
		phi 	r5
		ldi 	<DrawBat
		plo 	r5

		ldi 	Lives 									; Point RD to Lives, reset to 3.
		plo 	rd
		ghi 	r2 										; retrieve RAM page.
		phi 	rd
		ldi 	3
		str 	rd

		ldi 	Level 									; Point RD to Level, reset to 1.
		plo 	rd
		ldi 	1
		str 	rd

; ---------------------------------------------------------------------------------------------------------------------------------------		
;														New Level
; ---------------------------------------------------------------------------------------------------------------------------------------		

NewLevel:
		ldi 	>InitialiseLevel 						; Initialise the level
		phi 	r6
		ldi 	<InitialiseLevel
		plo 	r6
		sep 	r6

; ---------------------------------------------------------------------------------------------------------------------------------------		
;												Outer loop, checks before moving
; ---------------------------------------------------------------------------------------------------------------------------------------		

MainLoop:
		ghi 	r2 										; point RE to "lost"
		phi 	re 
		ldi 	LoseFlag
		plo 	re
		ldn 	re 										; read lost flag
		bnz 	LoseLife
		ldi 	BombsToHit 								; check if all bombs have been hit.
		plo 	re
		ldn 	re 
		bz 		LevelCompleted

		dec 	r2 										; space on stack
		ldi 	<BombList 								; save the LSB of the Bomb List on the Stack.
		str 	r2

		ldi 	>CheckCollision 						; Check Collisions.
		phi 	r6
		ldi 	<CheckCollision
		plo 	r6
		sep 	r6

; ---------------------------------------------------------------------------------------------------------------------------------------		
;												Inner loop, move all bombs
; ---------------------------------------------------------------------------------------------------------------------------------------		

MoveAllBombs:											; move all of them

		ldi 	>CreateBomb 							; bomb creation check (same rate as bat move)
		phi 	r6
		ldi 	<CreateBomb
		plo 	r6
		sep 	r6

		ldi 	>MoveBat 								; R6 points to Move the Bat routine
		phi 	r6
		ldi 	<MoveBat
		plo 	r6
		sep 	r6 										; And Move it

		ghi 	r2 										; Make R4 point to the current bomb
		phi		r4
		ldn 	r2 										; get the bomb pointer out of the stack entry
		plo 	r4

		ldi 	>MoveBomb 								; R6 points to MoveBomb subroutine
		phi		r6
		ldi 	<MoveBomb
		plo 	r6		
		sep		r6 										; and move it.

		ldn 	r2 										; reload the bomb pointer LSB
		adi 	BombRecSize 							; add offset to next record and update
		str 	r2
		xri 	BombListEnd 							; reached the end
		bnz 	MoveAllBombs

		inc 	r2 										; reclaim space off stack
		br		MainLoop 								; keep going .....

; ---------------------------------------------------------------------------------------------------------------------------------------		
;											Come here when level completed
; ---------------------------------------------------------------------------------------------------------------------------------------		

LevelCompleted:
		ldi 	Level 									; access level counter
		plo 	re
		ldn 	re 										; increment it
		adi 	1
		str 	re
		br 		NewLevel

; ---------------------------------------------------------------------------------------------------------------------------------------		
;															  Life lost
; ---------------------------------------------------------------------------------------------------------------------------------------		

LoseLife:
		ldi 	>ExplodeAllBombs 						; explode all the bombs.
		phi 	r6
		ldi 	<ExplodeAllBombs
		plo 	r6
		sep 	r6

		ghi 	r2
		phi 	re
		ldi 	Studio2BeepTimer 						; long warble
		plo 	re
		ldi 	120
		str 	re
LoseLifeWait: 											; wait for it .....
		ldn 	re
		bnz 	LoseLifeWait

		ldi 	Lives 									; point RE to lives counter
		plo 	re
		ldn 	re 										; read lives
		smi 	1 										; subtract one
		str 	re 										; save result
		bnz 	NewLevel 								; some left, try again with fewer lives

; ---------------------------------------------------------------------------------------------------------------------------------------		
;														Game Over, Display Score
; ---------------------------------------------------------------------------------------------------------------------------------------		

GameOver:
		ghi 	r2 										; point RD to the score.
		phi 	rd
		ldi 	Score
		plo 	rd
		ldi 	6 										; make 3 LSBs of E 110 (screen position)
		plo 	re
		ldi 	>WriteDisplayByte 						; point RA to the byte-writer
		phi 	ra
		ldi 	<WriteDisplayByte
		plo 	ra

ScoreWriteLoop:
		glo 	re 										; convert 3 LSBs of RE to screen address
		ani 	7
		adi 	128-40
		plo 	re
		ldi 	VideoPage 								; put in video page
		phi 	re

		lda 	rd 										; read next score digit
		adi 	$10 									; score table offset in BIOS
		plo 	r4
		ldi 	$02 									; read from $210+n
		phi 	r4
		ldn 	r4 										; into D, the new offset
		plo 	r4 										; put into R4, R4 now contains 5 rows graphic data

		ldi 	5 										; set R5.0 to 6
		plo 	r5
OutputChar:
		lda 	r4 										; read character and advance
		shr 											; centre in byte
		shr
		sep 	ra 										; output it
		dec 	r5 										; decrement counter
		glo 	r5
		bnz 	OutputChar 								; loop back if nonzero

		dec 	re 										; previous value of 3 LSBs.
		glo 	re
		ani 	7
		bnz 	ScoreWriteLoop

Stop:													; game ends, press RESET to play again.
		br 		Stop

        .org    07FFh                   				; fill it to 1,024 bytes.
        .db     0FFh
        .end

