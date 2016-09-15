; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;											ASTEROIDS - For the RCA Studio 2 (1802 Assembler)
;											=================================================
;
;	Author : 	Paul Robson (paul@robsons.org.uk)
;	Tools :		Assembles with asmx cross assembler http://xi6.com/projects/asmx/
;
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
;		R4 		PC (First level call)
; 		R5 		PC (Second Level Call)
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

RamPage	= 8													; 256 byte RAM page used for Data ($800 on S2)
VideoPage = 9												; 256 byte RAM page used for Video ($900 on S2)

Studio2BeepTimer = $CD 										; Studio 2 Beep Counter
Studio2SyncTimer = $CE 										; Studio 2 Syncro timer.

RandomSeed = $E0 											; 16 bit RNG seed
Lives = $E2 												; Lives count
Level = $E3 												; Level number
PointsToAdd = $E4 											; Points to add to score
Score = $E5 												; Score (6 bytes LSD first)

AsteroidBase = $00 											; Asteroid Start point
AsteroidCount = 16 											; Number of asteroids
AsteroidRecSize = 8 										; Size of each asteroid.
AsteroidEnd = AsteroidBase + AsteroidRecSize * AsteroidCount

MissileBase = AsteroidEnd 									; Missile Start Point
MissileCount = 4 											; number of missiles
MissileRecSize = 4 											; bytes per missile.
MissileEnd = MissileBase+MissileCount * MissileRecSize

XPlayer = MissileEnd+0 										; Player X position (follows Missiles for collision code.)
YPlayer = MissileEnd+1 										; Player Y position
Rotation = MissileEnd+2 									; Player Rotation (0-7)/Graphic
IsVisible = MissileEnd+3 									; Set when player has been made visible at level start.
VisiMask = MissileEnd+4 									; Checks whether asteroid in player area.
SpeedCounter = MissileEnd+5 								; Speed counter
LastFire = MissileEnd+6 									; Last status of fire button.

PlayerSpeed = 160 											; player speed is fixed.

MissileLifeSpan = 24 										; number of missile moves before self-termination

; ***************************************************************************************************************************************
;
;	Asteroid
;	========
;		+0 			X Position (0-63) - bit 7 unused - bit 6 don't draw first time.
;		+1 			Y Position (0-31) - bit 7 set marks it for destruction.
;		+2 			Asteroid ID (0-2) - also width = (n+1)*4 and height = (n+1) * 2
;		+3 			Direction of movement (0-7)
;		+4 			Speed
;		+5 			Speed counter.
;		+6,7 		(Reserved)
;
;	Missiles
;	========
;
;		+0 			Missile X Position - bit 7 set if not in use - bit 6 first draw.
; 		+1 			Missile Y Position - bit 7 marks it for destruction.
; 		+2 			Direction of Movement (0-7)
;		+3 			Moves remaining till expires.
;
; ***************************************************************************************************************************************

; ***************************************************************************************************************************************
;
;														Studio 2 Boot Code
;	
; ***************************************************************************************************************************************

    	.include "1802.inc"
    	.org    400h										; ROM code in S2 starts at $400.
StartCode:
    	.db     >(StartGame),<(StartGame)					; This is required for the Studio 2, which runs from StartGame with P = 3

; ***************************************************************************************************************************************
;
;													Asteroid Drawing Code
;
;	On entry : RA[0] is the horizontal position (0-63)
; 			   RA[1] is the vertical position (0-31)
; 			   RA[2] is the asteroid ID (0-2), also height/2.
;
;	Works by maintaining four pointers representing four quadrants and two masks (one for each side), these are
;   drawn a pixel at a time and moved in unison. Think of four linked pens drawing a circle, each doing one
; 	quarter of it.
;
;	Upper Right Pointer : RF 		Left Mask : RA.1 
;	Lower Right Pointer : RE 		Right Mask : RA.0
;	Upper Left Pointer :  RD 
;	Lower Left Pointer :  RC 		First-Plot Flag : RB.1
;
;	Breaks ALL REGISTERS - well I need it as fast as possible :) but RA is preserved on the stack.
;
;	Runs in R4, returns to R3.
;
;	Final testing showed : drawing 4 of each (e.g. 12 in total) 256 times in 10 seconds.
;						   3072 in 10 seconds, or about 300 per second.
;
; ***************************************************************************************************************************************

DrawAsteroid:
		sex 	r2 											; X = 2 throughout the pre draw code.

		dec 	r2 											; save RA on the stack.
		glo 	ra
		stxd
		ghi 	ra  
		stxd 	 											; save and allocate byte on stack for work.

		lda 	ra 											; read asteroid data in.
		plo 	rc
		lda 	ra
		phi 	rc
		lda 	ra
		phi 	rb
		str 	r2 											; save in stack space
		ghi 	rc 											; subtract 1/2 height from y to centre it.
		sm
		phi 	rc

; ---------------------------------------------------------------------------------------------------------------------------------------
;											Calculate the screen position and bit mask
; ---------------------------------------------------------------------------------------------------------------------------------------

		ghi 	r4 											; Call the byte & mask calculation routine.
		phi	 	r5 
		ldi 	<CalculateScreenPosition
		plo 	r5
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;						Calculate the asteroid height and set the screen position for the bottom half
; ---------------------------------------------------------------------------------------------------------------------------------------

		ghi	 	rb 											; get asteroid number from RB.1
		shl 												; asteroid # x 16
		shl
		shl
		shl
		adi 	8 											; asteroid # x 16 + 8 is the difference between top and bottom.

		str 	r2 											; save it on space allocated for calculations above.
		glo 	rd 											; get the upper offset
		add 												; add the difference
		plo 	re 											; put in RE.0 and RC.0 - the lower bytes of the lower quarters
		plo 	rc

		ghi 	rb 											; copy RB.1 (asteroid ID)
		str 	r2 											; store in allocated stack space.

; ---------------------------------------------------------------------------------------------------------------------------------------
;						Set up R5-R7 to point to - Plot Pixel, Move Horizontally, Move Vertically
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>PlotPixel 									; R5 always points to the pixel plotter
		phi 	r5
		phi 	r6 											; R6 points to the move left (or right) modifier
		phi 	r7 								
		ldi 	<PlotPixel 
		plo 	r5
		ldi 	<MoveLeft
		plo 	r6
		ldi 	<MoveDown 									; R7 points to the move down modifier
		plo 	r7

		ldi 	$FF 										; set 'first plot' flag in RB.0 - stops overwriting of first dot.
		phi 	rb 

		ldi 	VideoPage									; Set High Bytes of quadrant pointers RF-RC to point to the Video Page.
		phi 	rf
		phi 	re
		phi 	rd
		phi 	rc

; ---------------------------------------------------------------------------------------------------------------------------------------
;							Sequences of calls to 5,6,7 dependent on what you want to draw
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldxa 												; load the asteroid ID back in and fix up the stack
		bnz 	DA_Not0 									; if non zero skip the drawing of asteroid 0.

		sep 	r5 											; Asteroid 0.
		sep 	r6
		sep 	r5
		br 		DA_Exit

DA_Not0:shr 												; bit 0 set
		bnf 	DA_Asteroid2 								; if clear, it's asteroid #2

		sep 	r5 											; Asteroid 2.
		sep 	r6
		sep 	r5
		sep 	r6
		sep 	r7
		sep 	r5
		br 		DA_Exit

DA_Asteroid2:
		sep 	r5
		sep 	r6
		sep 	r5
		sep 	r6
		sep 	r7
		sep 	r5
		sep 	r6
		sep 	r7
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;															Restore RA and exit
; ---------------------------------------------------------------------------------------------------------------------------------------

DA_Exit:sex 	r2 											; restore RA off the stack.
		ldxa
		phi 	ra
		ldxa
		plo 	ra
		sep 	r3
		br 		DrawAsteroid 								; make it re-entrant

; ---------------------------------------------------------------------------------------------------------------------------------------
;																	Plot Pixels
; ---------------------------------------------------------------------------------------------------------------------------------------

PlotPixel:
		sex 	rf 	 										; do upper right pixel (RF,RB.0)
		glo		ra
		xor
		str 	rf

		sex 	re 											; do lower right pixel (RE,RB.0)
		glo 	ra
		xor 	
		str 	re

		ghi 	rb  										; first doesn't plot left and right because they're the same
		bz		PP_LeftSide									; and cancel each other out so skip.
		ldi 	0 											; clear first plot flag.
		phi 	rb
		sep 	r4 											; return
		br 		PlotPixel

PP_LeftSide:
		sex		rd 											; do upper left pixel (RD,RB.1)
		ghi 	ra
		xor
		str 	rd

		sex 	rc 											; do lower left pixel (RC,RB.1)
		ghi 	ra
		xor 	
		str 	rc

		sep 	r4 											; return
		br 		PlotPixel 								

; ---------------------------------------------------------------------------------------------------------------------------------------
;															Horizontal Movement
; ---------------------------------------------------------------------------------------------------------------------------------------

MoveLeft:
		ghi 	ra 											; get left mask
		shl 												; shift left and write back.
		phi 	ra
		bnf 	ML_MoveLeftRightSide
		shlc												; make it $01
		phi 	ra
		ghi 	rd
		dec 	rd
		dec 	rc
		phi 	rd
		phi		rc

ML_MoveLeftRightSide:
		glo 	ra 											; get right mask
		shr 	 											; shift right and write back
		plo 	ra
		bnf 	ML_Exit 									; if reached border
		shrc 												; make it $80
		plo 	ra 
		ghi 	re
		inc 	re 											; and move forward.
		inc 	rf
		phi 	re
		phi 	rf
ML_Exit:
		sep 	r4
		br 		MoveLeft

; ---------------------------------------------------------------------------------------------------------------------------------------
;															Vertical Movement
; ---------------------------------------------------------------------------------------------------------------------------------------

MoveDown:
		glo 	rf 											; move the upper pointers down one line.
		adi 	8
		plo 	rf
		glo 	rd
		adi 	8
		plo 	rd
		glo 	re 											; move the lower pointers up one line.
		smi 	8
		plo 	re
		glo 	rc
		smi 	8
		plo 	rc
		sep 	r4
		br 		MoveDown

MaskTable:													; Bitmask table. Has to stay in the same page as the Asteroid Drawing Code.
		.db 	$80,$40,$20,$10,$08,$04,$02,$01

; ***************************************************************************************************************************************
;
;		 Shift/XOR Drawer for 4 bit x 1 line of graphics. There are 8 entry points each representing one pixel shift, 2 bytes apart
;
;	On Entry, 	D 		contains the bits to shift, undefined on exit.
;			  	RF 		points to the first byte of the two to Xor (should remain unchanged)
;				RE.L	is undefined on entry and exit
;				RE.H 	is undefined on entry and exit.
;
;	Runs in R5, Return to R4
;	Note:  you cannot 'loop' subroutine this because you don't know what the entry point was - there are 8 entries and 2 exits :)
;
; ***************************************************************************************************************************************

ShiftXORDrawerBase:
		br 		SXD0 										; Shift 0 bits right
		br 		SXD1 										; Shift 1 right (etc.)
		br 		SXD2
		br 		SXD3 										;
		br 		SXD4 										; up to here, only requires one byte
		br 		SXD5 										; shift 5 => 4 Shift Rights, then 1 x 16 bit shift rights
		br 		SXD6										; shift 6-7 => swap and 1-2 shift lefts

SXD7:														; shift right x 7 == swap and shift left one in 16 bits
		shl 												; shift result left, MSB into DF
		plo 	re 											; this is the second byte of data
		ldi 	0 											; set D = DF, e.. the old MSB is the LSB of this byte	
		shlc 
		phi 	re 											; RE.H RE.L now is a 7 bit shift.
		br 		SXDXorWord

SXD6:														; shift right x 7 == swap and shift left twice in 16 bits
		shl 												; (this part same as for SXD7)
		plo 	re 												
		ldi 	0 												
		shlc 
		phi 	re 											; RE.H RE.L now is a 7 bit shift.
		glo 	re 											; shift it once more to the left
		shl
		plo 	re
		ghi 	re
		shlc
		phi 	re
		br 		SXDXorWord

SXD4: 														; shift right x 4
		shr 
SXD3:														; shift right x 3
		shr 
SXD2:														; shift right x 2
		shr
SXD1:														; shift right x 2
		shr
SXD0:														; shift right x 1
		sex 	rf 											; xor with the first screen byte
		xor
		str 	rf
		sep 	r4 											; there are 2 exit points

SXD5: 														; shift right x 5
		shr
		shr
		shr
		shr
		shr 												; shift fifth bit into DF
		phi 	re 											; RE now contains 16 bit graphic
		ldi 	0
		shrc 												; shift DF into bit 7
		plo 	re

SXDXorWord:
		sex 	rf 											; index on RF
		inc 	rf 											; Xor RE.L into RF+1
		glo 	re
		xor
		stxd
		ghi 	re 											; Xor RE.H into RF
		xor
		str 	rf 									
		sep 	r4 											; Note, 2 exit points.

; ***************************************************************************************************************************************
;														Calculate Screen Position
;
;	In: 	RC.0 (Horizontal 0-63) RC.1 (Vertical 0-31)
;	Out: 	RF.0 and RD.0 point to the byte, RA.1 and RA.0 contain the mask.
;
;	Returns to R4. Breaks RC
;
; ***************************************************************************************************************************************

CalculateScreenPosition:
		sex 	r2 											; X = Stack
		glo 	rc 											; get the horizontal position (0-63)
		ani		63
		shr 												; divide by 8 - this is a byte offset now.
		shr
		shr
		dec 	r2 											; allocate space for it on the stack
		str 	r2 											; save it.
		ghi 	rc 											; get vertical position (0-31)
		ani 	31
		shl 												; multiply by 8
		shl
		shl
		add 												; D = X/8 + Y/8 - the byte position
		plo 	rf 											; byte position stored in RF.0 and RD.0
		plo 	rd

		glo 	rc 											; RC.0 anded with 7 and added the table offset to it
		ani 	7
		adi 	<MaskTable 					
		plo 	rc
		ldi 	>MaskTable									; RC.1 now contains this page address, e.g. RC points to mask table
		phi 	rc
		ldn 	rc 											; read mask table
		phi 	ra 											; store it in RA.1
		plo 	ra 											; and RA.0
		inc 	r2 											; fix up stack
		sep 	r4

; ***************************************************************************************************************************************
;
;														 Keypad Scanner
;
; 	Scans keyboard for 2,4,6,8,0 returned in bits 0,1,2,3,7 respectively. Note correlation between these bits (Up,Left,Right,Down)
;	and the bit patterns in the map. 0 is used to start.
;
;	High Level Call, returns to R3. Breaks RF.
;
;	PORT: Changing this can easily throw "Branch out of Range" errors where 1802 branches cross page. It may be better to either
; 		  pad it out to the same length or simply completely replace it.
;
; ***************************************************************************************************************************************

ScanKeypad:
		ldi 	2 											; start off by scanning '2'
		phi 	rf 											; this value goes in RF.
		sex 	r2
		ldi 	0 											; initial value in RF.
		plo 	rf
SKBLoop:
		ghi 	rf 											; get current scan value.
		dec 	r2 											; store the scanned value on the stack.
		str 	r2
		out 	2 											; select that latch

		ghi 	rf 											; shift scan left ready for next time
		adi 	2 											; 2,4,6,8,10,12,14,16 but scan only uses lower 4 bits
		phi 	rf
		glo 	rf 											; get the current value
		shr 												; shift right.
		b4 		SKBSet 										; check EF3 EF4
		bn3 	SKBSkip
SKBSet:
		ori		$80 										; if key pressed or with $80, 7 shifts will make this $01 (for '2')
SKBSkip:
		plo 	rf 											; save the current value
		ghi 	rf 											; read the scan value
		xri 	$12 										; if reached $12 then finished
		bnz 	SKBLoop
		glo 	rf 											; load the keypad result into D
		ani 	$8F 										; we are only interested in 0,1,2,3,7, throw the rest.
		sep 	r3 											; and exit


; ***************************************************************************************************************************************
;														Draw 4 bit Sprite
;
;	RC.0 	x position (0-63) (autoloaded by DrawPlayerSprite)
;	RC.1 	y position (0-31)
;	D 		graphic 0-7.
;
;	Breaks : R5,R6,RA,RB.1,RC,RD,RE,RF
;
;	DrawPlayerSprite loads data in from RA[0],RA[1],RA[2] first.
;
; ***************************************************************************************************************************************

DrawPlayerSprite:
		ldi 	XPlayer 									; point RA to player data
		plo 	ra
		ghi 	r2
		phi 	ra
		lda 	ra 											; read X
		smi 	1 											; adjust centre
		plo 	rc
		lda 	ra 											; read Y
		smi 	1 											; adjust centre
		phi 	rc
		lda 	ra 											; read graphic
		ani 	7 											; only interested in lower 3 bits.
DrawSprite:
		shl 												; multiply graphic # x 4
		shl 		
		adi 	<AsteroidGraphics							; point RE to the asteroid graphic to use
		phi 	rb 											; save the low address in RB.1

		glo 	rc 											; get X position
		ani 	7 											; take 3 bits which are in byte position
		shl 												; x 2
		adi		<ShiftXORDrawerBase 						; set R6 = XOR Drawer Address
		plo 	r6
		ldi 	>ShiftXORDrawerBase 						
		phi 	r6

		ldi 	>CalculateScreenPosition 					; calculate sprite position. Byte offset in RF.0 RD.0 mask in RA.1 RA.0
		phi 	r5
		ldi 	<CalculateScreenPosition
		plo 	r5
		sep 	r5
		ldi 	VideoPage 									; make RF point to the video.
		phi 	rf

		ghi 	rb 											; get the asteroid graphic low pointer
		plo 	ra 											; make RA point to the asteroid graphic
		ldi 	>AsteroidGraphics
		phi 	ra

		glo 	r6 											; save XOR Drawer LSB in RB.1
		phi 	rb
DS_Loop:
		lda 	ra 											; get next graphic
		bz 		DS_Exit 									; exit if finished
		sep 	r6 											; call the XOR Drawer
		ghi 	rb 											; fix it back for the next call.
		plo 	r6
		glo 	rf 											; next line down.
		adi 	8
		plo 	rf
		br 		DS_Loop
DS_Exit:
		sep 	r3

; ***************************************************************************************************************************************
;									Reposition RA[0] (X) and RA[1] (Y) in direction D
;
;	Returns to R3, breaks RF.
;
; ***************************************************************************************************************************************

MoveObject:
		ani 	7 											; 8 directions
		shl 												; 2 entries per direction
		adi 	<DirectionTable
		plo 	rf 											; make RF point to the direction adders
		ldi 	>DirectionTable
		phi 	rf
		sex 	rf											; use RF as index

		ldn 	ra 											; read X
		add  												; add dX
		ani 	63 											; fix range
		str 	ra 											; write back

		inc 	ra 											; go to Y, dY
		inc 	rf
		ldn 	ra 											; add dY to Y, force into range
		add
		ani 	31
		str 	ra

		dec 	ra 											; fix up RA
		sep 	r3 											; and exit.

DirectionTable: 											; dx,dy for each of 8 directions.
		db 		0,-1
		db 		1,-1
		db 		1,0
		db 		1,1
		db 		0,1
		db 		-1,1
		db 		-1,0
		db 		-1,-1

		
; ***************************************************************************************************************************************
;														Single Pixel Drawer
;
;	Toggles pixel RC.0,RC.1
; 	Breaks R5,RC,RD,RE,RF - RA is preserved on the stack.
;
; ***************************************************************************************************************************************

DrawPixelLoad:
		dec 	r2 											; save RA on the stack.
		glo 	ra
		str 	r2
		dec 	r2
		ghi 	ra
		str 	r2
		lda 	ra 											; copy coordinates into RC.0,RC.1
		plo 	rc
		lda 	ra
		phi 	rc
DrawPixel:
		ldi 	>CalculateScreenPosition 					; calculate sprite position. Byte offset in RF.0 RD.0 mask in RA.1 RA.0
		phi 	r5
		ldi 	<CalculateScreenPosition
		plo 	r5
		sep 	r5
		ldi 	VideoPage 									; make RF point to the video.
		phi 	rf
		glo 	ra 											; get mask
		sex 	rf 											; xor into screen.
		xor
		str 	rf
		lda 	r2 											; restore RA off the stack.
		phi 	ra
		lda 	r2
		plo 	ra
		sep 	r3	

; ***************************************************************************************************************************************
;
;										LFSR Random Number Generator (breaks RF)
;
; Returns to : R5 Breaks RF. Reentrant subroutine.
;
; ***************************************************************************************************************************************

Random:	ghi 	r2 											; point RF to the Seed Data (2nd byte)
		phi 	rf
		ldi 	RandomSeed+1
		plo 	rf
		sex		rf 											; use RF as index register

		ldn 	rf 											; load the 2nd byte
		shr 												; shift right into DF
		stxd 												; store and point to first byte
		ldn 	rf 											; rotate DF into it and out
		shrc 
		str 	rf
		bnf 	RN_NoXor
		inc 	rf 											; if LSB was set then xor high byte with $B4
		ldn 	rf
		xri 	$B4
		stxd 												; store it back and fix up RF again.
RN_NoXor:
		ldn 	rf 											; re-read the LSB
		inc 	rf
		add 												; add the high byte.
		sep 	r5 											; and exit.
		br 		Random

; ***************************************************************************************************************************************
;													Insert Asteroid of type D
;
;	Returns pointer to new Asteroid in RA. Runs in R5, returns to R4
;	Breaks RB.1, RA, RF, R6
; ***************************************************************************************************************************************

InsertAsteroid:
		phi 	rb 											; put type in RB.1
		ghi 	r2 											; set RA to point to asteroid base records.
		phi 	ra
		ldi 	<AsteroidBase
		plo 	ra
IAFindSlot:
		ldn 	ra 											; read first item, $FF if not in use
		shl 												; shift bit 7 into DF
		bdf 	IAFoundSlot
		glo 	ra 											; go to next record
		adi 	AsteroidRecSize
		plo 	ra
		xri 	AsteroidEnd 								; if reached the end, give up !
		bnz		IAFindSlot
		phi 	ra 											; return $0000 in RA.
		plo 	ra		
		sep 	r4

IAFoundSlot:
		ldi 	>Random 									; R6 = Random Routine
		phi 	r6
		ldi 	<Random
		plo 	r6
		glo 	ra 											; add 5 to RA
		adi 	5
		plo 	ra

		sep 	r6 											; random number
		sex 	ra 											; X = RA
		stxd 												; store in RA[5] - means don't all draw/erase same frame.

		ghi 	rb 											; get type in RB.1
		shl 												; x 64 = 0 - 0 1 - 64 2 - 128
		shl
		shl
		shl
		shl
		shl
		sdi 	172 										; 172 - n x 32  0 = 172, 1 = 108, 2 = 54
		stxd 												; store in RA[4]
		sep 	r6 											; Direction of movement 0-7 in RA[3]
		sex 	ra 											; X = A
		ani 	7
		ori 	1 											; force diagonal
		stxd

		ghi 	rb 											; type in RA[2]
		stxd

		sep 	r6 											; y position in RA[1]
		sex 	ra 											; X = A
		ani 	31
		stxd

		sep 	r6 											; x position in RA[0] 										
		sex 	ra 											; X = A
		ani 	63
		ori 	64 											; set don't draw first bit.
		str 	ra
		sep 	r4


; ***************************************************************************************************************************************
;
;														M A I N    P R O G R A M
;
; ***************************************************************************************************************************************

; ---------------------------------------------------------------------------------------------------------------------------------------		
; 														Set everything up
; ---------------------------------------------------------------------------------------------------------------------------------------		

StartGame:
		ldi 	$0FF 										; initialise the Stack to $2FF
		plo		r2 											; from $2CF.
		ldi 	RAMPage
		phi 	r2
		phi 	rd

		ldi 	Level 										; point RD to Level.
		plo 	rd
		sex 	rd
		ldi 	1											; start at level #1
		stxd
		ldi 	3 											; with three lives
		stxd
		stxd 												; makes the MSB of random seed non-zero.

; ---------------------------------------------------------------------------------------------------------------------------------------		
;													Come here if starting new level.
; ---------------------------------------------------------------------------------------------------------------------------------------		

StartNewLevel:
		ldi 	>InitialiseLevel 							; call level initialisation code.
		phi 	r4
		ldi 	<InitialiseLevel
		plo 	r4
		sep 	r4

; ---------------------------------------------------------------------------------------------------------------------------------------		
;												Restart the current level.
; ---------------------------------------------------------------------------------------------------------------------------------------		

RestartCurrentLevel:
		ldi 	VideoPage									; point RA to the video page
		phi 	rd
		phi 	ra
		ldi 	0
		plo 	ra
		ldi 	8 											; and RD to VP Line 1
		plo 	rd
RCL_Clear: 													; clear the screen.
		ldi 	$00
		str 	ra
		inc 	ra
		glo 	ra
		bnz 	RCL_Clear
		ghi 	r2 											; read lives left
		phi 	re
		ldi 	Lives
		plo 	re
		ldn 	re
		plo 	re 											; store in RE.0
RCL_Lives:
		ldi 	$60 										; draw a life marker
		str 	rd
		glo 	rd 											; two lines down
		adi 	16
		plo 	rd
		dec 	re 											; for however many lives are left.
		glo 	re
		bnz 	RCL_Lives

		ldi 	IsVisible 									; RE points to Visible Flag (RE.1 = Data Area)
		plo 	re
		sex 	re
		ldi 	0 											; set Visible Flag ($F3) to zero.
		stxd
		stxd 												; set rotation ($F2) to zero
		ldi 	16 											; set Y ($F1) to 16 
		stxd
		ldi 	32 											; set X ($F0) to 32
		stxd 

		ldi 	MissileBase 								; erase missiles
		plo 	re
RCL_ClearMissiles:
		ldi 	$FF
		str 	re
		inc 	re
		glo 	re
		xri 	MissileEnd
		bnz 	RCL_ClearMissiles

RCL_Wait5: 													; wait for Player 1 Key 5 which is the start key
		dec 	r2
		sex 	r2
		ldi 	5 											; put 5 on TOS
		str 	r2 							 				; send to keyboardlatch
		out 	2
		bn3 	RCL_Wait5 									; loop back if key 5 not pressed

; ---------------------------------------------------------------------------------------------------------------------------------------		
;															Main Loop
; ---------------------------------------------------------------------------------------------------------------------------------------		

MainLoop:
		ghi 	r2  										; Point RA to Visibility Mask and set it to $FF
		phi 	ra 											; (cleared if in central area)
		ldi 	VisiMask
		plo 	ra
		ldi 	$FF
		str 	ra

; ---------------------------------------------------------------------------------------------------------------------------------------		
;														Move all the asteroids
; ---------------------------------------------------------------------------------------------------------------------------------------		

		ldi 	AsteroidBase  								; Point RA to asteroids
		plo 	ra

ML_MoveAsteroid:
		ldn 	ra 											; get X
		shl 												; bit 7 set = not used
		bdf 	ML_NextAsteroid2							; skip to next

		ghi 	ra 											; point RF to the speed RA[4]
		phi 	rf
		glo 	ra
		adi 	4
		plo 	rf
		lda 	rf 											; read speed, advance to speed counter RA[5]
		sex 	rf
		add 												; add to speed counter
		str 	rf
		bnf 	ML_NextAsteroid 							; if no carry out don't move.

		ldi 	>DrawAsteroid 								; R4 points to drawing routine
		phi 	r4
		ldi 	<DrawAsteroid
		plo 	r4

		ldn 	ra 											; if bit 6 of X is set
		ani 	$40
		bnz 	ML_DontNeedErase 							; then first time, so don't need to erase
		sep 	r4 											; erase

		inc 	ra 											; read Y
		ldn 	ra
		dec 	ra
		shl 												; if bit 7 set
		bnf 	ML_DontNeedErase 							; then don't destroy asteroid
		ldi 	$FF 										; mark asteroid unused
		str  	ra
		br 		ML_NextAsteroid

ML_DontNeedErase:
		ldi 	>MoveObject 								; R5 points to object mover
		phi 	r5
		ldi 	<MoveObject
		plo 	r5
		inc 	ra 											; get direction at RA[3]
		inc 	ra
		inc 	ra
		ldn 	ra
		dec 	ra
		dec 	ra
		dec 	ra
		sep 	r5 											; move (also clears bit 6)
		sep 	r4 											; repaint (R4 reentrant)

ML_NextAsteroid:
		ldn 	ra 											; read X - check in range 22-42
		ani 	63
		smi 	22
		bnf 	ML_NextAsteroid2
		smi 	20
		bdf 	ML_NextAsteroid2

		inc 	ra 											; read Y - check in range 11-21
		ldn 	ra
		ani		31
		dec 	ra
		smi 	11
		bnf 	ML_NextAsteroid2
		smi 	10
		bdf 	ML_NextAsteroid2

		ghi 	r2 											; clear visimask flag if in area.
		phi 	re
		ldi 	VisiMask
		plo 	re
		ldi 	0
		str 	re

ML_NextAsteroid2:
		glo 	ra 											; point RA to next asteroid
		adi 	AsteroidRecSize
		plo 	ra
		xri 	AsteroidEnd 								; go back if reached the end.
		bnz		ML_MoveAsteroid

		ldi 	>ScanKeypad 								; read the keypad
		phi 	r4
		ldi 	<ScanKeypad
		plo 	r4
		sep 	r4
		dec 	r2 											; store on stack.
		str 	r2

		ldi 	>ML_JumpPage								; set R4 to ML_JumpPage - we can't do LBR.
		phi 	r4
		ldi 	<ML_JumpPage
		plo 	r4
		sep 	r4 											; transfer there
ML_JumpPage:
		ldi 	>MovePlayerSection 							; set R3 to MovePlayerSection
		phi 	r3
		ldi 	<MovePlayerSection
		plo 	r3
		sep 	r3 											; and go there.

; ***************************************************************************************************************************************
;
;														Set up new Level
;
; ***************************************************************************************************************************************

InitialiseLevel:
		ghi 	r2
		phi 	ra 											; erase asteroid data to all $FFs
		ldi 	AsteroidBase
		plo 	ra
AsteroidClear:
		ldi 	$FF
		str 	ra
		inc 	ra
		glo 	ra
		xri 	AsteroidEnd
		bnz 	AsteroidClear

		ldi 	Level 										; get level.
		plo 	ra
		ldn 	ra 				
		shr 												; level/2 + 3
		adi 	3
		dec 	r2 											; save on stack space.
		str 	r2
		smi 	9
		bnf		SNL_InsertLoop								; max out at 9
		ldi 	9
		str 	r2

SNL_InsertLoop:
		ldi 	>InsertAsteroid 							; call insert asteroid code.
		phi 	r5
		ldi 	<InsertAsteroid
		plo 	r5
		ldi 	2											; type 2 - the big ones.
		sep 	r5

		ldn 	r2 											; decrement counter till zero.
		smi 	1
		str 	r2
		bnz 	SNL_InsertLoop
		inc 	r2

		sep 	r3

; ***************************************************************************************************************************************
;														Collision Check
;
;	Check collision of 4 missiles + player with Asteroid at RC. 
;
;	Runs in R4, returns to R3. Jumps out if player has lost.
; ***************************************************************************************************************************************

CollisionCheck:
		ldi 	MissileBase 								; point RD to the missile base
		plo 	rd
		ghi 	r2
		phi 	rd
		inc 	rc 											; point RC to RC[2] which is the asteroid type
		inc 	rc
		ldn 	rc 											; read in asteroid type
		dec 	rc 											; point RC back to RC[0]
		dec 	rc
		dec 	r2 											; make space on the stack
		adi 	2 											; collision is |dx| and |dy| < type+2 (e.g. 2,3,4)
		str 	r2
CC_Loop:
		ldn 	rd 											; read missile/player X
		ani 	$C0
		bnz 	CC_Next 									; if non-zero either unused bit (7) or new (6) is set so skip
		inc 	rd 											; read RD[1] e.g. missile/player Y
		ldn 	rd
		dec 	rd
		shl 												; bit 7 of RD[1] - the marked for deletion bit - in DF
		bdf 	CC_Next 									; skip if marked for deletion.

		ldn 	rd 											; read X.Missile
		sex 	rc
		sm 													; calculate X.Player - X.Asteroid
		bdf 	CC_Abs1 									; calculate |X.Player - X.Asteroid|
		sdi 	0
CC_Abs1:sex 	r2 											; point to collision width
		sm   												; if >= collision width, go to next record
		bdf 	CC_Next

		inc 	rd 											; read Y.Player
		ldn 	rd
		dec 	rd
		sex 	rc 											; calculate Y.Player-Y.Asteroid
		inc 	rc
		sm
		dec 	rc
		bdf 	CC_Abs2 									; calculate |Y.Player - Y.Asteroid|
		sdi 	0
CC_Abs2:sex 	r2 											; if >= collision width, go to next record
		sm
		bdf 	CC_Next

		glo 	rd 											; get LSB of collided player/missile.
		xri 	XPlayer 									; hit the player
		bz 		CC_LostLife

		inc 	rd  										; mark bullet for deletion - set RD[1] bit 7
		ldn 	rd
		ori 	$80
		str 	rd
		dec 	rd

		inc 	rc 											; mark asteroid for deletion - set RC[1] bit 7
		ldn 	rc
		ori 	$80
		str 	rc
		inc 	rc 											; get asteroid type
		ldn 	rc  										; load type RC[2] into R7.0
		plo 	r7 											
		dec 	rc 											; fix RC back to point to asteroid base.
		dec 	rc

		inc 	rd 											; point RD to missile direction
		inc 	rd
		ldn 	rd 											; load rotation angle from RC[3] into r7.1
		smi 	2 											; subtract 2 i.e. a right angle to the missile direction.
		phi 	r7
		dec 	rd 											; fix RD back
		dec 	rd

		ghi 	r2 											; point RE to points to add
		phi 	re
		ldi 	PointsToAdd
		plo 	re
		glo 	r7 											; type destroyed 2,1,0
		sdi 	3 											; score is 1,2,3 x 100 points
		sex 	re 											; add to points to add.
		add
		str 	re

		glo 	r7 											; get asteroid type
		bz 		CC_Next 									; if zero don't spawn smaller ones.
		ldi 	2 											; set RE.0 = 2, the counter.
		plo 	re
CC_NewRocks:
		ldi 	>InsertAsteroid 							; create a new asteroid in RA
		phi 	r5
		ldi 	<InsertAsteroid
		plo 	r5
		glo 	r7 											; get asteroid type shot
		smi 	1 											; one less is the asteroid type to be created, returns a pointer in RA.
		sep 	r5

		lda 	rc 											; get X of destroyed asteroid
		ori 	$40 										; set 'new' flag.
		str 	ra
		inc 	ra
		ldn 	rc 											; get Y of destroyed asteroid
		str 	ra
		dec 	rc 											; rc back pointing at record
		inc 	ra 											; RA now at RA[2] type
		inc 	ra 											; RA now at RA[3] rotation
		ghi 	r7 											; get rotation, flip 180 degrees
		adi 	4
		ani 	7
		phi 	r7
		str 	ra 											; store in the rotation slot.
		dec 	re 											; do it twice
		glo 	re
		bnz 	CC_NewRocks

CC_Next:glo 	rd 											; advance RD to next record
		adi 	MissileRecSize
		plo 	rd
		xri 	MissileEnd+MissileRecSize 					; go one further - this is the player collision check
		bnz 	CC_Loop 									; keep going.

		inc 	r2 											; fix stack up 
		sep 	r3

CC_LostLife:
		ghi 	r2 											; player collision. Check that player is visible
		phi 	re
		ldi 	IsVisible
		plo 	re
		ldn		re
		bz 		CC_Next 									; if not visible ignore this.

		inc 	r2 											; fix stack
		ldi 	>Dead 										; go to lost life code, jump out of routine.
		phi 	r3
		ldi 	<Dead
		plo 	r3
		sep 	r3
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
; 														ROM BREAK HERE
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

; ---------------------------------------------------------------------------------------------------------------------------------------		
;														Move the player
; ---------------------------------------------------------------------------------------------------------------------------------------		

		.org 	$C00
SecondRomBase:

MovePlayerSection:

		ghi 	r2
		phi 	rd
		phi 	re 
		ldi 	SpeedCounter 								; point RE to player speed counter
		plo 	re
		ldn 	re 											; add speed to speed counter
		adi 	PlayerSpeed
		str 	re
		bnf 	ML_EndPlayerMove 							; no carry out, don't move.

		ldi 	IsVisible 									; point RD to IsVisible	, check if player has been made visible yet.
		plo 	rd
		lda 	rd 											; read isVisible and point RD to Visimask
		bnz 	ML_PlayerMove
		ldn 	rd  										; read Visimask
		bz 		ML_EndPlayerMove 							; if that is zero, then can't come into existence yet.
		dec 	rd 											; point back to IsVisible, D != 0
		str 	rd 											; now mark it as been made visible
		br 		ML_RedrawPlayer

ML_PlayerMove:
		ldi 	>DrawPlayerSprite							; erase the player
		phi 	r4
		ldi 	<DrawPlayerSprite
		plo 	r4
		sep 	r4

		ghi 	r2 											; RA points to player, RE to rotation
		phi 	ra
		phi 	re
		ldi 	XPlayer
		plo 	ra
		ldi 	Rotation
		plo 	re

		ldn 	re 											; read rotation
		plo 	rd 											; put in RD
		ldn 	r2 											; read keypad
		shr 
		shr  												; shift bit 1 into DF
		bnf 	ML_NotLeft
		dec 	rd 											; if set rotate left
ML_NotLeft:
		shr 												; shift bit 2 into DF
		bnf 	ML_NotRight
		inc 	rd 											; if set rotate right
ML_NotRight:
		glo 	rd 											; store rotation back anded with 7
		ani 	7
		str 	re


		ldn 	r2 											; read keypad state off stack
		shr  												; bit 0 (key 2) into DF
		bnf 	ML_RedrawPlayer 							; if not set, don't move.

		ldi 	>MoveObject 								; R4 points to object mover
		phi 	r4
		ldi 	<MoveObject
		plo 	r4
		ldn 	re 											; read rotation in.
		sep 	r4 											; move the player.

ML_RedrawPlayer:
		ldi 	>DrawPlayerSprite							; redraw the player before exiting.
		phi 	r4
		ldi 	<DrawPlayerSprite
		plo 	r4
		sep 	r4

; ---------------------------------------------------------------------------------------------------------------------------------------		
;											Check for player fire, launch missile if true.
; ---------------------------------------------------------------------------------------------------------------------------------------		

		ghi 	r2 											; point RF to last fire byte
		phi		rf
		phi 	ra  										; set RA.1 to data area
		ldi 	LastFire
		plo 	rf

		ldn 	r2 											; reload keyboard byte off stack
		ani 	$80											; isolate bit 7 (fire) into D
		sex 	rf 											; ex-or with old status.
		xor
		bz  	ML_EndPlayerMove 							; if no change then exit player move.
		xor 												; ex-or brings back new status.
		str 	rf 											; save in last status byte
		bz 		ML_EndPlayerMove 							; if 0 then transition 1->0, exit

		ldi 	MissileBase 								; fire missile request, set RA.0 to missile base
		plo 	ra 											; look for free missile space.
ML_FindFreeMissile:
		ldn 	ra 											; look in missile slot.
		shl 												; check bit 7
		bdf 	ML_FoundFreeMissileSpace  					; if set, free slot so create new missile
		glo 	ra 											; advance to next slot
		adi 	MissileRecSize
		plo 	ra
		xri 	MissileEnd 									; reached the end
		bnz 	ML_FindFreeMissile 							; try again.
		br 		ML_EndPlayerMove 							; all missiles currently in use.

ML_FoundFreeMissileSpace:
		ldi 	XPlayer 									; RF points to player data, RA to missile
		plo 	rf 
		lda 	rf 											; copy X across
		ori 	$40 										; set the not-drawn bit.
		str 	ra
		inc 	ra
		lda 	rf 											; copy Y across
		str 	ra
		inc 	ra
		lda 	rf 											; copy rotation = missile direction across.
		str 	ra
		inc 	ra
		ldi 	MissileLifeSpan 							; set the missile life counter
		str 	ra

		ldi 	Studio2BeepTimer 							; short beep.
		plo 	ra
		ldi 	5
		str 	ra

ML_EndPlayerMove:
		inc 	r2 											; fix stack back up.

; ---------------------------------------------------------------------------------------------------------------------------------------		
;													Move all live missiles
; ---------------------------------------------------------------------------------------------------------------------------------------		

		ghi 	r2 											; point RA to missile start
		phi 	ra
		ldi 	MissileBase
		plo 	ra


ML_MoveMissiles:
		ldn 	ra 											; read X
		shl 												; if bit 7 set not in use.
		bdf 	ML_NextMissile
		shl 												; if bit 6 go to move, redraw, exit
		bdf 	ML_MissileNoErase

		ldi 	>DrawPixelLoad 								; set R4 to the pixel loader.
		phi 	r4
		ldi 	<DrawPixelLoad
		plo 	r4
		sep 	r4 											; erase previous missile

ML_MissileNoErase:
		inc 	ra 											; read Y from RA[1]
		ldn 	ra
		dec 	ra
		shl 												; bit 7 into DF
		bdf 	ML_MissileDestroy 							; if set, mark it for destroying.
		glo 	ra 											; point RE at life counter RA[3]
		adi 	3
		plo 	re
		ghi 	ra
		phi 	re

		ldn 	re 											; read the life counter RA[3]
		smi 	1 											; decrement it and update.		
		str 	re
		bz 		ML_MissileDestroy 							; if zero destroy the missile
		dec 	re 											; RE now points at missile direction RA[2]

		ldi 	>MoveObject 								; R4 points to object mover
		phi 	r4
		ldi 	<MoveObject
		plo 	r4
		ldn 	re											; read rotation in.
		sep 	r4 											; move the missile

		ldi 	>DrawPixelLoad 								; set R4 to the pixel loader.
		phi 	r4
		ldi 	<DrawPixelLoad
		plo 	r4
		sep 	r4 											; redraw the missile
		br 		ML_NextMissile

ML_MissileDestroy:											; destroy the missile
		ldi 	$FF 										; set MA[0] to $FF terminating it.
		str 	ra
ML_NextMissile:
		glo 	ra 											; go to next missile
		adi 	MissileRecSize
		plo 	ra
		xri 	MissileEnd 									; if not reached end, go back
		bnz 	ML_MoveMissiles

; ---------------------------------------------------------------------------------------------------------------------------------------		
;													Collision Testing
; ---------------------------------------------------------------------------------------------------------------------------------------		
	
		ghi 	r2
		phi		rc
		ldi 	AsteroidBase 							 	; scan through asteroids check collisions with bullets/player.
		plo 	rc
ML_CollisionLoop:
		ldn 	rc 											; read asteroid X
		ani 	$C0 										; bit 7 = unused, bit 6 = newly created. Both must be clear.
		bnz  	ML_CollisionNext							; if bit 7 set this record is empty.
		ldi 	>CollisionCheck 							; call collision check
		phi 	r4
		ldi 	<CollisionCheck
		plo 	r4
		sep 	r4
ML_CollisionNext:
		glo 	rc
		adi 	AsteroidRecSize 							; go to next asteroid record.
		plo 	rc
		xri 	AsteroidEnd 								; keep going till the end.
		bnz 	ML_CollisionLoop

; ---------------------------------------------------------------------------------------------------------------------------------------		
;													Adding accrued points
; ---------------------------------------------------------------------------------------------------------------------------------------		

ML_AddPoints:
		ldi 	PointsToAdd 								; point RA to points to add
		plo 	ra
		ldn 	ra 											; read points to add
		bz 		ML_EndAddPoints 							; exit if zero
		smi 	1 											; decrement accrued
		str 	ra
		inc 	ra 											; advance to units digit.
		inc 	ra 											; advance to tens digit.
ML_BumpDigit:
		inc 	ra 											; advance to next digit
		ldn 	ra 											; increment and save digit
		adi 	1
		str 	ra
		smi 	10 											; if < 10 then see if any more accrued points
		bnf 	ML_AddPoints
		str 	ra 											; save result back (e.g. mod 10)
		br 		ML_BumpDigit 								; do the next digit. (e.g. tens->hundreds)
ML_EndAddPoints:
		br 		TimerSync-1

; ---------------------------------------------------------------------------------------------------------------------------------------		
; 													Timer Synchronisation
; ---------------------------------------------------------------------------------------------------------------------------------------		

		.org 	SecondRomBase-1+256

		ghi 	r2
TimerSync:
		ghi 	r2
		phi		ra
		ldi 	Studio2SyncTimer 							; RA points to S2 sync timer.
		plo 	ra
ML_WaitTimer:
		ldn 	ra
;		bnz 	ML_WaitTimer
		ldi 	3
		str 	ra

; ---------------------------------------------------------------------------------------------------------------------------------------		
; 												Check if level completed.
; ---------------------------------------------------------------------------------------------------------------------------------------		

		ldi 	AsteroidBase 								; set RA point to asteroid base
		plo 	ra
ML_CheckCompleted:
		ldn 	ra 											; read ra
		shl 												; shift alive bit into DF
		bnf 	LongBranchMainLoop							; if there's a live asteroid keep going round.
		glo 	ra 											; go to next record.
		adi 	AsteroidRecSize
		plo 	ra
		xri 	AsteroidEnd 								; check all asteroids
		bnz 	ML_CheckCompleted

		ldi 	Level 										; completed level - bump to next.
		plo 	ra
		ldn 	ra
		adi 	1
		str 	ra

		ldi 	>StartNewLevel 								; start a new level.
		phi 	rc
		ldi 	<StartNewLevel
		plo 	rc
		br 		LongBranchToRC

; ---------------------------------------------------------------------------------------------------------------------------------------		
; 											Loop around because we have no LBR
; ---------------------------------------------------------------------------------------------------------------------------------------		

LongBranchMainLoop:
Loop2:	ldi 	>MainLoop
		phi 	rc
		ldi 	<MainLoop
		plo 	rc

LongBranchToRC:
		ldi 	>JumpToRC 										; so we're stuck with this.
		phi 	r4
		ldi 	<JumpToRC
		plo 	r4
		sep 	r4

JumpToRC: 														; here with P = 4
		ghi 	rc 												; copy RC to R3
		phi 	r3
		glo 	rc
		plo 	r3
		sep 	r3 												; jump to r3

; ---------------------------------------------------------------------------------------------------------------------------------------		
;															Life Lost
; ---------------------------------------------------------------------------------------------------------------------------------------		

Dead:	ghi 	r2 												; point RF to Lives
		phi		rf
		ldi 	Lives
		plo 	rf
		ldn 	rf 												; decrement lives count
		smi 	1
		str 	rf

		bz 		GameOver

		ldi 	AsteroidBase 									; set all the new flags in the asteroids as Restart will clear screen.
		plo 	rf
DeadSetNew:
		ldn 	rf
		ori 	$40
		str 	rf
		glo		rf
		adi 	AsteroidRecSize
		plo 	rf
		xri 	AsteroidEnd
		bnz		DeadSetNew

		ldi 	>RestartCurrentLevel 							; restart the current level
		phi 	rc
		ldi 	<RestartCurrentLevel
		plo 	rc
		br 		LongBranchToRC

; ---------------------------------------------------------------------------------------------------------------------------------------		
;															Game Over
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

		ldi 	$FF
		sep 	ra
		ldi		$00
		sep 	ra

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

		ldi		$00
		sep 	ra
		ldi 	$FF
		sep 	ra

		dec 	re 										; previous value of 3 LSBs.
		glo 	re
		ani 	7
		bnz 	ScoreWriteLoop

Halt:	br 		Halt

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
;													Asteroid Ship Graphics
;
; ***************************************************************************************************************************************

		.org 	SecondROMBase+$1E0
AsteroidGraphics:
		.db 	64,160,160,0
		.db 	96,160,64,0
		.db 	192,32,192,0
		.db 	64,160,96,0
		.db 	160,160,64,0
		.db 	64,160,192,0
		.db 	96,128,96,0
		.db 	192,160,64,0

		.db 	0