; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;											BERZERK - For the RCA Studio 2 (1802 Assembler)
;											===============================================
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
;		R4 		PC (level 1 subroutine)
;		R5 		PC (level 2 subroutine)
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

RamPage	= 8													; 256 byte RAM page used for Data ($800 on S2)
VideoPage = 9												; 256 byte RAM page used for Video ($900 on S2)

Studio2BeepTimer = $CD 										; Studio 2 Beep Counter
Studio2SyncTimer = $CE 										; Studio 2 Syncro timer.

XRoom = $E0 												; Horizontal Room Number
YRoom = $E1 												; Vertical Room Number
Seed1 = $E2 												; Random Number Seed #1
Seed2 = $E3 												; Random Number Seed #2

NorthDoor = $E4 											; door present flags. If non-zero can exit in that direction.
SouthDoor = $E5 											
EastDoor = $E6
WestDoor = $E7

LivesLost = $E8 											; Number of lives lost
Score = $E9 												; Score (LS Digit first, 6 digits)

FrameCounter = $F0 											; Frame counter
KeyboardState = $F1 										; Current Keyboard State (0-9 + bit 7 for fire)

XAdjustStart = 125
YAdjustStart = 227

; ------------------------------------------------------------------------------------------------------------------------------------
;
; +0 	bit 7 : Not in use, bit 6 : To be Deleted, Bit 5 : not drawn Bits 3-0 : ObjectID 
;																	(0 = Player, 1 =  Missile, 2-4 = Robots)
; +1    Speed Mask (and with Frame counter, move if zero)
; +2 	bits 3..0 direction as per Studio 2 Keypad, 0 = no movement
; +3 	X position (0-63)
; +4    Y position (0-31)
; +5    0 if graphic not drawn, or LSB of address of 3 bit right justified graphic terminated with $00
;
; It is a convention that an objects missile immediately follows it's own object. Object 0 is the Player, Object 1 is the Player Missile
; 
; ------------------------------------------------------------------------------------------------------------------------------------

ObjectStart = $00
ObjectRecordSize = 6
ObjectCount = 2+8
ObjectEnd = ObjectStart+ObjectRecordSize * ObjectCount

PlayerObject = ObjectStart+0*ObjectRecordSize
PlayerMissileObject = ObjectStart+1*ObjectRecordSize

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
;										  Draw Room according to current specification.
;
; Runs in R4, Returns to R3
; ***************************************************************************************************************************************

DrawRoom:

; ---------------------------------------------------------------------------------------------------------------------------------------
;											Clear the whole screen, draw the basic frame.
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	VideoPage 									; point RF to video page
		phi 	rf
		ldi 	0
		plo 	rf
DRM_ClearScreen:
		glo 	rf
		ani 	$F8 										; top and bottom lines
		bz 		DRM_WriteFF
		xri 	$F0
		bz 		DRM_WriteFF
		xri 	$08
		bz 		DRM_Write00
		glo 	rf 											; check left and right sides
		ani 	$07
		bz 		DRM_Write80
		xri 	$07
		bz 		DRM_Write08
DRM_Write00:												; erase
		ldi 	$00
		br 		DRM_Write
DRM_Write08:												; right wall
		ldi 	$08
		br 		DRM_Write
DRM_Write80: 												; left wall
		ldi 	$80
		br 		DRM_Write
DRM_WriteF8: 												; top/bottom right
		ldi 	$F8
		br 		DRM_Write
DRM_WriteFF: 												; write top/bottom
		glo 	rf 											; check RHS
		ani 	7
		xri 	7
		bz 		DRM_WriteF8
		ldi 	$FF
DRM_Write: 													; write and fill whole screen
		str 	rf
		inc 	rf
		glo 	rf
		bnz 	DRM_ClearScreen

; ---------------------------------------------------------------------------------------------------------------------------------------
;										  Get West Door from room to the left's east door
; ---------------------------------------------------------------------------------------------------------------------------------------
		ldi 	WestDoor 									; point RF to West door, RE to XRoom.
		plo 	rf
		ldi 	XRoom
		plo 	re
		ghi 	r2
		phi 	rf
		phi 	re

		ldn 	re 											; read XRoom
		plo 	rd 											; save it in RD.
		smi 	1
		str 	re 											; go to the room to the left.

		ldi 	>ResetSeed 									; reset the seed according to room to the immediate left.
		phi	 	r5
		ldi 	<ResetSeed
		plo 	r5
		sep 	r5 											; reset the seed, get the first Random Number
		ani 	$01 										; bit 0 (east door) becomes our west door.
		str 	rf

		glo 	rd 											; restore old XRoom
		str 	re

; ---------------------------------------------------------------------------------------------------------------------------------------
;										Get North door from rom to the north's south door.
; ---------------------------------------------------------------------------------------------------------------------------------------

		inc 	re 											; RE points to Y Room
		ldi 	NorthDoor 									; RF to North Door.
		plo 	rf

		ldn 	re 											; Read Y Room
		plo 	rd 											; save in RD.0
		smi 	1
		str 	re 											; go to room above
		ldi 	<ResetSeed
		plo 	r5
		sep 	r5 											; reset the seed, get the first Random Number
		ani 	$02 										; bit 1 (south door) becomes our north door.
		str 	rf

		glo 	rd 											; restore old Y Room
		str 	re

		ldi 	SouthDoor 									; point RF to south door.
		plo 	rf

; ---------------------------------------------------------------------------------------------------------------------------------------
;								Get South and East doors from our current room, initialise RNG for walls
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	<ResetSeed 									; reset the seed, our actual room now.
		plo 	r5
		sep 	r5 											; reset the seed, get the first Random Number

		shr 												; shift bit 0 (east door) into DF
		ani 	$01 										; bit 0 (was bit 1) is the south door
		str 	rf
		inc 	rf 											; point RF to east door
		ldi 	$00
		shrc 												; get the old bit 7 out.
		str 	rf 											; save in east door.

; ---------------------------------------------------------------------------------------------------------------------------------------
;							Draw the 8 walls from the 8 centre point in directions chosen from the RNG
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	VideoPage 									; set RF to point to the first of the eight 'wall' centre points
		phi 	rf
		ldi 	10*8+1 										; row 8, byte 1
		plo 	rf
		ldi 	$08 										; set RE.1 to point to the current bit mask for Oring in.
		phi 	re
		ldi 	$0F 										; set RE.0 to the current byte #1 for Oring in.		
		plo 	re
		ldi 	$FF 										; set RD.1 to currentbyte #2 for Oring in.
		phi 	rd
; ---------------------------------------------------------------------------------------------------------------------------------------
;														Inner Wall Loop
; ---------------------------------------------------------------------------------------------------------------------------------------
DRM_Loop1:
		glo 	rf 											; save start position in RC.1s
		phi 	rc

		ghi 	re 											; set the pixel on the wall corner
		sex 	rf
		or
		str 	rf

		sep 	r5 											; get the second seeded number that defines the room layout.
		shl 												; put bit 7 in DF
		bnf 	DRM_WallHorizontal 							; if clear the wall is horizontal.

; ---------------------------------------------------------------------------------------------------------------------------------------
;												Vertical wall, either direction
; ---------------------------------------------------------------------------------------------------------------------------------------

		shl 												; put bit 6 in DF.
		ldi 	8 											; use that to decide up or down ?
		bnf 	DRM_VerticalOpposite
		ldi		-8
DRM_VerticalOpposite:

		dec 	r2 											; save offset position on stack.
		str 	r2
		ldi 	10 											; set RC.0 (counter) to 10
		plo 	rc
DRM_VerticalLoop:
		sex 	rf 											; video memory = index
		ghi 	re 											; or bit mask in.
		or
		str 	rf
		sex 	r2 											; offset = index
		glo 	rf 											; add to screen position
		add
		plo 	rf
		dec 	rc 											; do it 10 times.
		glo 	rc
		bnz 	DRM_VerticalLoop
		inc 	r2 											; fix stack up.
		br 		DRM_Next

; ---------------------------------------------------------------------------------------------------------------------------------------
;										Horizontal walls, seperate code for left and right
; ---------------------------------------------------------------------------------------------------------------------------------------

DRM_WallHorizontal:
		shl 												; bit 6 determines direction
		bnf 	DRM_WallLeft

		sex 	rf 											; index = vram - right wall
		glo		re
		or
		str 	rf
		inc 	rf
		ghi 	rd
		or
		str 	rf
		br 		DRM_Next

DRM_WallLeft: 												; left wall.
		sex 	rf
		ghi 	re 											; check the wall pixel
		shl
		bnf 	DRMWL_NotLHB 						
		dec 	rf 											; back one if the wall is not on the MS Bit.		
DRMWL_NotLHB:
		ghi 	rd
		xri 	$0F
		or
		str 	rf
		dec 	rf
		glo 	re
		xri 	$F0
		or
		str 	rf

; ---------------------------------------------------------------------------------------------------------------------------------------
;													Advance to next wall position
; ---------------------------------------------------------------------------------------------------------------------------------------

DRM_Next:
		ghi 	rc 											; reset start position saved in RC.1
		
		plo		rf
		glo 	re 											; change the ORing byte from $0F to $FF 
		xri 	$F0 			
		plo 	re

		ghi 	rd 											; change the other one from $FF to $F0
		xri 	$0F 
		phi 	rd

		ghi 	re 											; change the ORing bitmask from $08 to $80
		xri 	$88
		phi 	re
		shl 												; if gone from 08 to 80 add 1 to rf
		bnf 	DRM_NoBump
		inc 	rf
DRM_NoBump:
		inc 	rf 											; add one further to RF anyway.
		glo 	rf 											; reached the end of row 2 ?
		xri 	20*8+7 
		bz 		DRM_Frame
		glo 	rf
		xri 	10*8+7 										; reached the end of row 1 ?
		bnz		DRM_Loop1 									; no keep going
		ldi 	20*8+1 										; yes, move to the second row
		plo 	rf
		br 		DRM_Loop1

; ---------------------------------------------------------------------------------------------------------------------------------------
;														Open top and bottom doors
; ---------------------------------------------------------------------------------------------------------------------------------------

DRM_Frame:
		ldi 	3 											; point RF to upper door space
		plo 	rf
		ghi 	r2 											; point RE to NorthDoor
		phi 	re
		ldi 	NorthDoor
		plo 	re
		br 		DRM_TBDoor-1 								; sorts the page out.

		.org 	StartCode+$FF
		glo 	re 											; nop but not 3 cycles.
DRM_TBDoor:
		ldn 	re 											; read north door
		bz 		DRM_TBClosed 								; if zero, it is closed.
		ldi 	$80 										; open door on display
		str 	rf
		inc 	rf
		ldi 	$0F
		str 	rf
		dec 	rf
DRM_TBClosed:
		ldi 	30*8+3 										; point to bottom door always
		plo 	rf
		glo 	re 											; switch NorthDoor pointer to South Door
		xri 	NorthDoor ^ SouthDoor
		plo 	re
		xri 	NorthDoor 									; do it twice, till it returns to its original value.
		bnz 	DRM_TBDoor

; ---------------------------------------------------------------------------------------------------------------------------------------
;													 Open left and right doors
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	11*8 										; point RF to west door space
		plo 	rf
		ldi 	WestDoor 									; point RE to west door pointer
		plo 	re
DRM_LRDoor:
		ldn 	re 											; read west door, if zero it's closed
		bz 		DRM_LRClosed
DRM_OpenLRDoor:
		ldi 	$00 										; open it
		str 	rf
		glo 	rf 											; down one line
		adi 	8
		plo 	rf
		smi 	20*8 										; until reached the bottom
		bnf 	DRM_OpenLRDoor

DRM_LRClosed:
		ldi 	11*8+7 										; point RF to east door space
		plo 	rf
		glo 	re 											; switch west door pointer to east door pointer
		xri 	EastDoor ^ WestDoor
		plo 	re
		xri 	WestDoor 									; do it twice, till it returns to original value.
		bnz 	DRM_LRDoor

; ---------------------------------------------------------------------------------------------------------------------------------------
;												Draw number of lives lost
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	7+8											; point RF to lives draw area
		plo 	rf
		ldi 	LivesLost 									; point RE to lives lost
		plo 	re
		ldn 	re 											; calculate 3-lost
		sdi 	3
		plo 	rd 											; save in RD.0
DRM_Lives:
		ldn 	rf 											; set lives marker
		ori 	3
		str 	rf
		glo 	rf 											; two rows down
		adi 	16
		plo 	rf
		dec 	rd
		glo 	rd 											; for however many lives.
		bnz 	DRM_Lives

		sep 	r3

; ***************************************************************************************************************************************
;
;						Reset Seed according to Room positions, breaks R7, returns first Random Number
;
;  Runs in R5, returns to R4, drops through to "Random" subroutine below. Need to be in same page.
; ***************************************************************************************************************************************

ResetSeed:
		ldi 	XRoom 										; point R7 to XRoom
		plo 	r7
		ghi  	r2
		phi 	r7
		lda 	r7 											; read X Room, bump it
		inc 	r7 											; bump again to Seed1
		adi 	XAdjustStart
		str 	r7 											; store (modified) in Seed1
		dec 	r7 											; repeat with Y Room and Seed2
		lda 	r7
		inc 	r7
		adi 	YAdjustStart
		str 	r7

; ***************************************************************************************************************************************
;
;											 Random Number Generator, breaks R7.
;
;   Runs in R5, return to R4.
; ***************************************************************************************************************************************

Random:	ghi 	r2 											; point R7 to the Seed Data (2nd byte)
		phi 	r7
		ldi 	Seed2
		plo 	r7
		sex		r7 											; use R7 as index register

		ldn 	r7 											; load the 2nd byte
		shr 												; shift right into DF
		stxd 												; store and point to first byte
		ldn 	r7 											; rotate DF into it and out
		shrc 
		str 	r7
		bnf 	RN_NoXor
		inc 	r7 											; if LSB was set then xor high byte with $B4
		ldn 	r7
		xri 	$B4
		stxd 												; store it back and fix up RF again.
RN_NoXor:
		ldn 	r7 											; re-read the LSB
		inc 	r7
		add 												; add the high byte.

		sep 	r4 											; and exit.
		br 		Random

; ***************************************************************************************************************************************
;
;			Erase the object structure. Initialise the Player, flipping position horizontally or vertically accordingly.
;
;	Runs in R4, return to R3
; ***************************************************************************************************************************************

InitialiseRoomAndPlayer:
		ghi 	r2 											; set RF to the last object structure byte
		phi 	rf
		ldi 	ObjectEnd-1
		plo 	rf
IRM_Clear:													; fill everything with $FF
		sex 	rf
		ldi 	$FF
		stxd
		glo 	rf
		xri 	PlayerObject+ObjectRecordSize-1 			; keep going until reached last byte of player record
		bnz 	IRM_Clear

		stxd 												; +5 graphic drawn zero

		ldn 	rf 											; +4 copy Y
		stxd

		ldn 	rf 											; +3 copy X
		stxd

		ldi 	0 											; +2 direction no movement		
		stxd 
		ldi 	3 											; +1 speed mask
		stxd
		ldi 	0+32										; object ID = 0 (Player object) and not drawn flag set.
		stxd
		sep 	r3

; ***************************************************************************************************************************************
;										Partial line plotter - xors one row of 3 pixels
;
;	On entry, D contains pattern, RF points to the Video RAM to alter.
;	On exit, RF is up one (e.g. -8) we draw sprites upwards.
;
;	Runs in R6. Returns to R5. Breaks RE, Set [R2] to Non-Zero on collision.
;
; ***************************************************************************************************************************************

PartialXORPlot:
		br 		PX_Shift0 									; shift right x 0
		br 		PX_Shift1 									; shift right x 1
		br 		PX_Shift2 									; shift right x 2
		br 		PX_Shift3 									; shift right x 3
		br 		PX_Shift4 									; shift right x 4
		br 		PX_Shift5 									; shift right x 5
		br 		PX_Shift6 									; shift right 8, shift left 2.

PX_Shift7:													; shift right 8, shift left 1.
		shl 												; shift left, store in right half
		phi 	re
		ldi 	0 											; D = DF, store in left half.
		shlc
		plo 	re

PX_XorRE:													; XOR with RE, check collision.
		sex 	rf 

		glo 	re 											; check collision.
		and 
		bz 		PX_NoCollideLeftPart
		str 	r2 											; set TOS non zero on collision
PX_NoCollideLeftPart:

		glo 	re 											; XOR [RF] with RE.0
		xor 	
		str 	rf
		inc 	rf 											; XOR [RF+1] with RE.1

		ghi 	re 											; check collision.
		and 
		bz 		PX_NoCollideRightPart
		str 	r2 											; set TOS non zero on collision
PX_NoCollideRightPart:

		ghi 	re
		xor
		str 	rf
		glo 	rf 											; go down one row
		adi 	7
		plo 	rf
		sep 	r5 											; and exit

PX_Shift6:
		shl 												; RE.10 = D >> 8 left 1.
		phi 	re
		ldi 	0
		shlc
		plo 	re
		ghi 	re 											; shift it left once again
		shl
		phi 	re
		glo 	re
		shlc
		plo 	re
		br 		PX_XorRE 									; and exclusive OR into video memory.

PX_Shift5:													; shift right 6 and xor
		shr
PX_Shift4:													; shift right 4 and xor
		shr
PX_Shift3:													; shift right 3 and xor
		shr
PX_Shift2:													; shift right 2 and xor
		shr
PX_Shift1:													; shift right 1 and xor
		shr
PX_Shift0:													; shift right 0 and xor
		sex 	rf 											; XOR into RF
		plo 	re 											; save pattern in RE.0
		and 	 											; and with screen
		bz 		PX_NoCollideSingle 							; skip if zero e.g. no collision
		str 	r2 											; set TOS non zero on collision
PX_NoCollideSingle:											
		glo 	re 											; restore pattern from RE.0
		xor
		str 	rf
		glo 	rf 											; go down one row
		adi 	8
		plo 	rf
		sep 	r5 											; and exit

; ***************************************************************************************************************************************
;														Plot Character in RC
;
; Runs in R5, Returns to R4. D set to non-zero on collision with .... something.
;
; Subroutine breaks RB.1,RD,RE, uses RF as VideoRAM pointer.
; ***************************************************************************************************************************************

PlotCharacter:
		inc 	rc 											; advance to RC[3] which is the X position.
		inc 	rc
		inc 	rc

		ldi 	>PartialXORPlot 							; R6.1 set to PartialXOR Plot (MSB) throughout.
		phi 	r6

		ldn 	rc 											; read X position
		ani 	7 											; get the lower 3 bits - the shifting bits.
		shl 												; double and add to PartialXORPlot LSB
		adi 	<PartialXORPlot 							; this is the LSB of the routine address
		phi 	rb 											; save in RB.1

		lda 	rc 											; get X, bump to point to Y RC[4], divide by 8.
		shr
		shr
		shr
		dec 	r2 											; save X/8 on stack.
		str 	r2
		lda 	rc 											; get Y, bump to point to character data pointer RC[5]
		shl
		shl
		shl 												; multiply by 8
		sex 	r2 											; add to X/8 
		add 	  											; D now = Y*8 + X/8 e.g. the byte position in the screen

		plo 	rf 											; store in RF (points to video RAM)
		ldi 	VideoPage
		phi 	rf

		ldn 	rc 											; read character data pointer RC[5]
		plo 	rd 											; put in RD, RD is the pixel data source.
		ldi 	>Graphics 									; Make RD a full 16 bit pointer to graphics.
		phi 	rd

		ldi 	0
		str 	r2 											; clear top of stack which is the collision flag.
PCLoop:
		ghi 	rb 											; set R6 to the drawer routine.
		plo 	r6
		lda 	rd 											; read a graphic byte
		bz 		PCComplete 									; complete if zero
		sep 	r6 											; draw that pixel out.
		br 		PCLoop 										; keep going till more data.

PCComplete:
		glo 	rc 											; fix up RC so it points back to the start
		smi 	5
		plo 	rc

		lda 	r2 											; read collision flag off top of stack and fix the stack.
		sep 	r4 											; and return to R4.


; ***************************************************************************************************************************************
;
;											Object Mover (object pointed to by RC)
;
; ***************************************************************************************************************************************

MoveObject:
; ---------------------------------------------------------------------------------------------------------------------------------------
;									Check bit 7 of the ID/Flags is clear, e.g. it is in use
; ---------------------------------------------------------------------------------------------------------------------------------------
		ldn 	rc 											; read RC[0] - ID and Flags
		shl 												; put bit 7 (not in use) into DF
		bnf 	MO_InUse
		sep 	r3
MO_InUse:
; ---------------------------------------------------------------------------------------------------------------------------------------
;						if to be deleted (bit 6), erase and delete, if not drawn yet (bit 5), draw it and exit
; ---------------------------------------------------------------------------------------------------------------------------------------
		shl 												; put bit 6 (deleted) flag into DF.
		bdf 	MO_Erase 									; if set, go to erase because you want to delete it.
		shl 												; put bit 5 (not drawn) into DF.
		bdf 	MO_Redraw
; ---------------------------------------------------------------------------------------------------------------------------------------
;							  And the Frame Counter with the speed mask, to see if it is move time
; ---------------------------------------------------------------------------------------------------------------------------------------
		inc 	rc 											; move to RC[1]
		ghi 	r2 											; point RF at the Frame Counter
		phi 	rf
		ldi 	FrameCounter
		plo  	rf
		ldn 	rf 											; read the Frame Counter
		sex  	rc 											; and with the speed mask - controls how fast it goes.
		and 
		dec 	rc 											; fix RC up before carrying on.
		bz 		MO_TimeToMove
		sep 	r3
MO_TimeToMove:

; ---------------------------------------------------------------------------------------------------------------------------------------
;  			Figure out what direction is required, update it if $FF not returned. If direction = 0 (no move) collision only
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>CallVector 								; call the code to get the new direction.
		phi 	r6
		ldi 	<CallVector
		plo 	r6
		ldi 	<VTBL_GetDirection
		sep 	r6
		plo 	re 											; save it in RE.0

		ghi 	rc 											; point RF to RC[2], the direction.
		phi 	rf
		glo 	rc
		plo 	rf
		inc 	rf
		inc 	rf

		glo 	re 											; look at the returned direction.
		xri 	$FF 										; returned $FF, no change.
		bz 		MO_NoUpdateDirection
		glo 	re 											; copy the returned direction in.
		str 	rf
MO_NoUpdateDirection:
		ldn 	rf 											; if movement is zero, do nothing other than collision check.
		bz 		MO_CheckCollision

; ---------------------------------------------------------------------------------------------------------------------------------------
; 													Erase the old drawn character
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_Erase:
		ldi 	>PlotCharacter 								; erase the character.
		phi 	r5
		ldi 	<PlotCharacter
		plo 	r5
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;							if character marked to be deleted, then set ID/Flags to all '1' and return
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldn 	rc 											; read the ID + Flags
		ani 	$40 										; is the delete flag set ?
		bz 		MO_DontDelete 								; skip if not deleting.

		ldi 	$FF 										; set the flags to $FF e.g. deleted object
		str 	rc
		sep 	r3 											; and return to caller.

MO_DontDelete:
	
; ---------------------------------------------------------------------------------------------------------------------------------------
; 												Move in the requested direction
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>MoveObjectPosition 						; set R5 to point to the object moving code
		phi 	r5
		ldi 	<MoveObjectPosition
		plo 	r5		
		inc 	rc 											; read the current direction from RC[2]
		inc 	rc
		ldn 	rc
		dec 	rc
		dec 	rc
		sep 	r5 											; and move it.

; ---------------------------------------------------------------------------------------------------------------------------------------
; 						Get the graphic we want to use for drawing, and save that, then draw it in the new place
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_Redraw: 													; redraw in its new/old position.
		ldi 	>CallVector 								; call the code to get the graphic character
		phi 	r6
		ldi 	<CallVector
		plo 	r6
		ldi 	<VTBL_GetGraphicCharacter
		sep 	r6 
		plo 	re 											; save in RE.0
		ghi 	rc 											; set RF = RC[5], the graphic pointer
		phi 	rf
		glo 	rc
		adi 	5
		plo 	rf
		glo 	re 											; restore from RE.0
		str 	rf 											; save in RF.0 table.

		ldi 	>PlotCharacter 								; now redraw it in the new position.
		phi 	r5
		ldi 	<PlotCharacter
		plo 	r5
		sep 	r5
		bz 		MO_ClearNotDrawn 							; if no collision clear the 'not drawn' flag.

; ---------------------------------------------------------------------------------------------------------------------------------------
;					if Player collided, must've died. if Missile collided, delete. if robot collided, undo move.
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_Collide:
		ldn 	rc 											; get the ID number
		ani 	15

		bz 		MO_PlayerHitFrame 							; if zero then the player has hit something, life over.
		xri 	1 											; if it is ID #1 (bullet) then delete it but keep data for collision.
		bz 		MO_DeleteMissile 							; otherwise move it back.

MO_MoveBackwards:
		ldi 	>PlotCharacter 								; now erase it in the new position
		phi 	r5
		ldi 	<PlotCharacter
		plo 	r5
		sep 	r5

		ldi 	>MoveObjectPosition 						; set R5 to point to the object moving code
		phi 	r5
		ldi 	<MoveObjectPosition
		plo 	r5		
		inc 	rc 											; read the current direction from RC[2]
		inc 	rc
		ldn 	rc
		sdi 	10 											; move it backwards i.e. to where it was.
		dec 	rc
		dec 	rc
		sep 	r5 											; and move it.

		ldi 	>PlotCharacter 								; now redraw it in the original position.
		phi 	r5
		ldi 	<PlotCharacter
		plo 	r5
		sep 	r5
		br 		MO_ClearNotDrawn 							; go on to the next phase.

MO_DeleteMissile:
		ldn 	rc
		ori 	$40
		str 	rc
		br 		MO_ClearNotDrawn

; ---------------------------------------------------------------------------------------------------------------------------------------
;															Player died
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_PlayerHitFrame: 											; player hit something, die now.
		ldi 	>LifeLost
		phi 	r3
		ldi 	<LifeLost
		plo 	r3
		sep 	r3

; ---------------------------------------------------------------------------------------------------------------------------------------
; 										    	Collision okay, clear not drawn bit.
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_ClearNotDrawn:
		ldn 	rc 											; clear the 'not drawn' flag as it now will be until deleted.
		ani 	$FF-$20 
		str 	rc

; ---------------------------------------------------------------------------------------------------------------------------------------
; 					 Call the collision testing code (missiles vs players/robots) or firing code (player/robot)
; ---------------------------------------------------------------------------------------------------------------------------------------

MO_CheckCollision:
		ldi 	>CallVector 								; call collision testing code.
		phi 	r6
		ldi 	<CallVector
		plo 	r6
		ldi 	<VTBL_CollisionCheckOrFire
		sep 	r6

		sep 	r3 											; and finally exit.

; ***************************************************************************************************************************************
;
;												Adjust object at RC in direction D
;
; ***************************************************************************************************************************************

MoveObjectPosition:
		ani 	15 											; lower 4 bits only.
		shl 												; RF to point to the offset table + D x 2
		adi 	<XYOffsetTable 								
		plo 	rf
		ldi 	>XYOffsetTable
		phi 	rf

		sex 	rc 											; RC as index
		inc 	rc 											; point to RC[3] , x position
		inc 	rc
		inc 	rc

		lda 	rf 											; read X offset 	
		add  												; add to RC[3]
		str 	rc
		inc 	rc 											; point to RC[4], y position
		ldn 	rf 											; read Y offset
		add 												; add to RC[4]
		str 	rc
		glo 	rc 											; set RC[4] back to RC[0]
		smi 	4
		plo 	rc
		sep 	r4
		br  	MoveObjectPosition 							; make reentrant

XYOffsetTable:
		.db 	0,0 										; 0
		.db 	-1,-1,  0,-1,   1,-1 						; 1 2 3
		.db 	-1,0,   0,0,	1,0 						; 4 5 6
		.db 	-1,1,	0,1, 	1,1 						; 7 8 9
		.db 	0,0 										; 10

; ***************************************************************************************************************************************
;
;			On entry, P = 6 and D points to a table. Load the vector into R5, and set P = 5 - vectored code run in P5, return to P4
;
; ***************************************************************************************************************************************

CallVector:
		dec 	r2 											; save the table LSB on the stack
		str 	r2
		ldn 	rc 											; get ID bits
		ani 	15
		shl 												; double
		sex 	r2 											; add to table LSB
		add
		plo 	rf 											; put in RF.0
		ldi	 	>VTBL_GetDirection 							; point to tables, all in same page
		phi 	rf
		inc 	r2 											; fix up stack
		lda 	rf 											; read MSB into R5.1
		phi 	r5
		ldn 	rf 											; read LSB into R5.0
		plo 	r5
		sep 	r5 											; and jump.

Continue: 													; continue is a no-op e.g. don't change direction.
		ldi 	$FF
		sep 	r4
GetMissileGraphic:	
		ldi 	<Graphics_Missile
		sep 	r4
GetRobotGraphic:
		ldi 	<Graphics_Robot
		sep 	r4

VTBL_GetDirection:
		.dw 	GetPlayerDirection,Continue,ChasePlayer, ChasePlayer, ChasePlayer

VTBL_GetGraphicCharacter:
		.dw 	GetPlayerGraphic,GetMissileGraphic,GetRobotGraphic,GetRobotGraphic,GetRobotGraphic

VTBL_CollisionCheckOrFire:
		.dw 	CheckPlayerFire,CollideMissile,Continue,LaunchMissile,LaunchMissile

; ***************************************************************************************************************************************
;
;												Update Keyboard State, also returned in D
;
; ***************************************************************************************************************************************

UpdateKeyboardState:
		ldi 	9 											; set RF.0 to 9
		plo 	rf
UKSScan:
		dec 	r2 											; put RF.0 on TOS.
		glo 	rf
		str 	r2
		sex 	r2 											; put into keyboard latch.
		out 	2
		b3 		UKSFound 									; if EF3 set then found a key pressed.
		dec 	rf
		glo 	rf
		bnz 	UKSScan 									; try all of them
UKSFound: 													; at this point RF.0 is 0 if no key pressed, 1 if pressed.
		ldi 	0 											; set keyboard latch to zero.
		dec 	r2
		str 	r2
		out 	2
		bn4 	UKSNoFire 									; skip if Keypad 2 key 0 not pressed
		glo 	rf  										; set bit 7 (the fire bit)
		ori 	$80
		plo 	rf
UKSNoFire:
		ghi 	r2 											; point RE to the keyboard state variable
		phi 	re
		ldi 	KeyboardState
		plo 	re
		glo 	rf 											; save the result there
		str 	re 	
		sep 	r3

; ***************************************************************************************************************************************
;
;													Get Player Direction Move
;
; ***************************************************************************************************************************************

GetPlayerDirection:
		ghi 	r2 											; point RF to KeyboardState
		phi 	rf
		ldi 	KeyboardState
		plo 	rf
		ldn 	rf 											; read Keyboard State
		ani 	15 											; only interested in bits 0-3
		sep 	r4

; ***************************************************************************************************************************************
;														Get Player Graphic
; ***************************************************************************************************************************************

GetPlayerGraphic:
		ghi 	r2 											; read keyboard state
		phi 	rf
		ldi 	<KeyboardState
		plo 	rf
		ldn 	rf
		ani 	15 											; bits 0-3
		shl 												; x 2, add XYOffsetTable
		adi 	<XYOffsetTable
		plo 	rf
		ldi 	>XYOffsetTable
		phi 	rf 
		ldn 	rf 											; read X offset
		shl 												; sign bit in DF
		ldi 	<Graphics_Left1 							; pick graphic based on sign bit
		bdf		GPG_Left
		ldi 	<Graphics_Right1
GPG_Left:
		plo 	rf 
		glo 	r9 											; use S2 BIOS Clock to pick which animation to use.
		ani 	4
		bz 		GPG_NotAlternate
		glo 	rf
		adi 	5
		plo 	rf
GPG_NotAlternate:
		glo 	rf
		sep 	r4


; ***************************************************************************************************************************************
;
;														Check Player Fire
;
; ***************************************************************************************************************************************

CheckPlayerFire:
		ghi 	r2 											; point RF to keyboard state
		phi 	rf
		ldi 	<KeyboardState
		plo 	rf
		ldn 	rf 											; read keyboard
		shl 												; fire button into DF
		bdf 	LaunchMissile
		sep 	r4

; ***************************************************************************************************************************************
;
;													  Launch Missile from RC
;
; ***************************************************************************************************************************************

LaunchMissile:
		ghi 	rc 											; point RD to Missile that's being launched
		phi 	rd
		glo 	rc 											
		adi 	ObjectRecordSize
		plo 	rd

		ldn 	rd 											; check if already in use, if so exit.
		shl
		bnf 	LM_Exit

		ldi 	1+$20 										; object ID #1, not drawn in RD[0]
		str 	rd
		inc 	rd
		ldi  	0 											; speed mask RD[1]
		str 	rd
		inc 	rd

		inc 	rc 											; point RC to direction RC[2]
		inc 	rc
		lda 	rc 											; read it and bump it.
		bz 		LM_Cancel 									; if zero cancel missile launch.
		str 	rd 											; save in RD[2]
		inc 	rd


		shl 												; double direction, add XYOffsetTable
		adi 	<XYOffsetTable
		plo 	rf 											; make RF point to offset data
		ldi 	>XYOffsetTable
		phi 	rf

		ldn 	rc 											; read RC[3] (X Position)
		sex 	rf
		add 												; add 2 x direction to it
		add
		adi 	1
		str 	rd 											; save in RD[3]

		inc 	rc 											; point to RC[4],RD[4] and Y offset
		inc 	rd
		inc 	rf

		ldn 	rc 											; RD[4] = RC[4] + 3 x dy
		add
		add
		add
		adi 	2
		str 	rd 

		glo 	rc 											; fix RC back
		smi 	4
		plo 	rc
LM_Exit:
		sep 	r4	

LM_Cancel: 													; missile launch cancelled
		dec 	rd
		dec 	rd
		ldi 	$FF 										; write $FF to RD[0] no object
		str 	rd
		dec 	rc 											; fix up RC
		dec 	rc
		dec 	rc
		sep 	r4 											; and exit.

; ***************************************************************************************************************************************
;
;													  Missile collision check
;
; ***************************************************************************************************************************************

CollideMissile:
		ghi 	rc 											; RF = RC + 3
		phi 	rf
		glo 	rc
		adi 	3
		plo 	rf 											; RF points to X
		lda 	rf 											
		ani 	$C0
		bnz 	CM_Delete 
		ldn 	rf
		ani 	$E0
		bnz 	CM_Delete
		ldi 	>CheckHitPlayerRobotObjects  				; check for collisions with player or robots.
		phi 	r6
		ldi 	<CheckHitPlayerRobotObjects
		plo 	r6
		sep 	r6
		sep 	r4
CM_Delete:
		ldn 	rc
		ori 	$40
		str 	rc
		sep 	r4

; ***************************************************************************************************************************************
;
;															Berzerk Graphics
;
; ***************************************************************************************************************************************

Graphics:

Graphics_Left1:
		.db 	$40,$C0,$40,$40,0
Graphics_Left2:
		.db 	$40,$C0,$40,$A0,0
Graphics_Right1:
		.db 	$40,$60,$40,$40,0
Graphics_Right2:
		.db 	$40,$60,$40,$A0,0
Graphics_Missile:
		.db 	$80,0
Graphics_Robot:
		.db 	$40,$A0,$E0,$A0,0

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
;														SECOND ROM SECTION 
;
; ***************************************************************************************************************************************

    	.org 	0C00h

; ***************************************************************************************************************************************
;
;															Game starts here
;
; ***************************************************************************************************************************************

StartGame:
; --------------------------------------------------------------------------------------------------------------------------------------
;														Come back here when life lost
; --------------------------------------------------------------------------------------------------------------------------------------
		ghi 	r2 											; reset the player object position to something sensible
		phi 	rf
		ldi 	PlayerObject+3
		plo 	rf
		ldi 	13
		str 	rf
		inc 	rf
		str 	rf
		ldi 	XRoom 										; reset the start room
		plo 	rf
		ldi 	0
		str 	rf
		inc 	rf
		str 	rf
WaitKey5:
		ldi 	>UpdateKeyboardState 						; update keyboard state.
		phi 	r4
		ldi 	<UpdateKeyboardState
		plo 	r4
		sep 	r4
		xri 	5 											; keep going till key 5 pressed.
		bnz 	WaitKey5
; --------------------------------------------------------------------------------------------------------------------------------------
;								     Come back here when re-entering a new rooom - initialise and draw
; --------------------------------------------------------------------------------------------------------------------------------------
NewRoom:
		ldi 	RamPage 									; reset the stack.
		phi 	r2
		ldi 	$FF
		plo 	r2

		ldi 	>InitialiseRoomAndPlayer 					; re-initialise a room
		phi 	r4
		ldi 	<InitialiseRoomAndPlayer
		plo 	r4
		sep 	r4

    	ldi 	>DrawRoom 									; draw the room.
    	phi 	r4
    	ldi 	<DrawRoom
    	plo 	r4
    	sep 	r4

; --------------------------------------------------------------------------------------------------------------------------------------
;															Create Robots
; --------------------------------------------------------------------------------------------------------------------------------------
		ghi 	r2 											; point RF to objects where can create robots
		phi 	rf
		ldi 	ObjectStart+ObjectRecordSize*2
		plo 	rf
		ldi 	>CreateRobot 								; point R4 to create robot code.
		phi 	r4
		ldi 	<CreateRobot
		plo 	r4

		ldi 	2 											; create various robot types 2,3 and 4.
		sep 	r4
		ldi 	3
		sep 	r4
		ldi 	4
		sep 	r4

; --------------------------------------------------------------------------------------------------------------------------------------
;	 														MAIN LOOP
; --------------------------------------------------------------------------------------------------------------------------------------

MainLoop:
		ldi 	>UpdateKeyboardState 						; update keyboard state.
		phi 	r4
		ldi 	<UpdateKeyboardState
		plo 	r4
		sep 	r4

; --------------------------------------------------------------------------------------------------------------------------------------
;													Move/Check all objects
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	ObjectStart 								; point RC to object start
		plo 	rc
		ghi 	r2
		phi 	rc

ObjectLoop:
		ldi 	>MoveObject 								; move object
		phi 	r4
		ldi 	<MoveObject
		plo 	r4
		sep 	r4

		glo 	rc 											; go to next object.
		adi 	ObjectRecordSize
		plo 	rc
		xri 	ObjectEnd 									; loop back if not at end.
		bnz 	ObjectLoop

; --------------------------------------------------------------------------------------------------------------------------------------
;											Increment the frame counter (used for speed)
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	FrameCounter 								; bump the frame counter
		plo 	rc
		ldn 	rc
		adi 	1
		str 	rc

; --------------------------------------------------------------------------------------------------------------------------------------
;												Check to see if exited through doors
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	PlayerObject+3 								; point RC to Player.X
		plo 	rc
		ghi 	r2 											; point RD to XRoom
		phi 	rd
		ldi 	XRoom
		plo 	rd 											
		ldn 	rc  										; read RC (Player X)
		bz 		MoveLeftRoom
		xri 	$3A
		bz 		MoveRightRoom
		inc 	rc 											; point RC to Player Y
		inc 	rd 											; point RD to YRoom
		ldn  	rc 											; read RC (Player Y)
		bz 		MoveUpRoom
		xri 	$1B
		bz 		MoveDownRoom

; --------------------------------------------------------------------------------------------------------------------------------------
; 												Synchronise with RCAS2 Timer Counter
; --------------------------------------------------------------------------------------------------------------------------------------

Synchronise:
		ldi 	Studio2SyncTimer							; synchronise and reset
		plo 	rc
		ldn 	rc
		bnz 	Synchronise
		ldi 	3*1
		str 	rc

		br 		MainLoop

; --------------------------------------------------------------------------------------------------------------------------------------
;													Handle vertical moves (room->room)
; --------------------------------------------------------------------------------------------------------------------------------------

MoveDownRoom:
		ldi 	1
		br 		MoveVRoom
MoveUpRoom:
		ldi 	$FF
MoveVRoom: 													; add offset to RD (points to YRoom)
		plo 	re
		sex 	rd
		add
		str 	rd
		glo 	re
		shl
		ldi 	1
		bnf 	MoveVRoom2
		ldi 	26
MoveVRoom2:
		str 	rc
		br 		NewRoom

; --------------------------------------------------------------------------------------------------------------------------------------
;												Handle horizontal moves (room->room)
; --------------------------------------------------------------------------------------------------------------------------------------

MoveRightRoom:
		ldi 	1
		br 		MoveHRoom
MoveLeftRoom:
		ldi 	$FF
MoveHRoom: 													; add offset to RD (points to XRoom)
		plo 	re
		sex 	rd
		add
		str 	rd
		glo 	re
		shl
		ldi 	2
		bnf 	MoveHRoom2
		ldi 	$38
MoveHRoom2:
		str 	rc

		br 		NewRoom

; ***************************************************************************************************************************************
;
;														Dead if reached here.
;
; ***************************************************************************************************************************************

LifeLost:
		ghi 	r2 											; point RF to lives lost
		phi 	rf
		ldi 	LivesLost
		plo 	rf
		ldn 	rf 											; bump lives lost
		adi 	1
		str 	rf
		xri 	3 											; lost 3 lives, if not, try again
		bnz  	StartGame

; ***************************************************************************************************************************************
;
;															Display Score
;
; ***************************************************************************************************************************************

		ghi 	r2 											; point RD to the score.
		phi 	rd
		ldi 	Score
		plo 	rd
		ldi 	6 											; make 3 LSBs of E 110 (screen position)
		plo 	re
		ldi 	>WriteDisplayByte 							; point RA to the byte-writer
		phi 	ra
		ldi 	<WriteDisplayByte
		plo 	ra

ScoreWriteLoop:
		glo 	re 											; convert 3 LSBs of RE to screen address
		ani 	7
		adi 	128-40
		plo 	re
		ldi 	VideoPage 									; put in video page
		phi 	re

		ldi		$00
		sep 	ra

		lda 	rd 											; read next score digit
		adi 	$10 										; score table offset in BIOS
		plo 	r4
		ldi 	$02 										; read from $210+n
		phi 	r4
		ldn 	r4 											; into D, the new offset
		plo 	r4 											; put into R4, R4 now contains 5 rows graphic data

		ldi 	5 											; set R5.0 to 6
		plo 	r5
OutputChar:
		lda 	r4 											; read character and advance
		shr 												; centre in byte
		shr
		sep 	ra 											; output it
		dec 	r5 											; decrement counter
		glo 	r5
		bnz 	OutputChar 									; loop back if nonzero

		ldi		$00
		sep 	ra

		dec 	re 											; previous value of 3 LSBs.
		glo 	re
		ani 	7
		bnz 	ScoreWriteLoop

Halt:	br 		Halt 										; game over, stop forever.

; ***************************************************************************************************************************************
;
;													Make object @RC chase the player
;
; ***************************************************************************************************************************************

ChasePlayer:
		ghi 	rc 											; point RF to RC+3 X Position.
		phi 	rf 											; point RE to PlayerObject+3
		phi 	re
		glo 	rc
		adi 	3
		plo 	rf
		ldi 	PlayerObject+3
		plo 	re
		sex 	rf

		glo 	r9 											; check bit 4 of the sync counter 
		ani 	$10
		bz 		CP_Horizontal

		inc 	re 											; point to Y coordinates
		inc 	rf
		ldn 	re
		sm
		ldi 	2
		bnf 	CP_1
		ldi 	8
		sep 	r4

CP_Horizontal:
		ldn 	re 											; calculate Player Object Coord - Object Coord
		sm 
		ldi 	4
		bnf 	CP_1										; if >= return 4 (left) else return 6 (right)
		ldi 	6
CP_1:	sep 	r4

; ***************************************************************************************************************************************
;
;			Check to see if missile object at RC has collided with a Player or a Robot. If it has delete both (set delete flags)
;			Jump to lost-life code if required, add score if required.
;
; Runs in R6, Returns to R5, must preserve RC. May crash out if player dies.
; ***************************************************************************************************************************************

CheckHitPlayerRobotObjects:
		ghi 	rc 											; RD <- RC+3 e.g. x position of missile
		phi 	rd
		glo 	rc
		adi 	3
		plo 	rd
		ghi 	r2 											; RE points to the Object List
		phi 	re 	
		ldi 	ObjectStart
		plo 	re
CHPRO_Loop:
		ldn 	re 											; get ID/Flags for Object being tested
		shl 												; check in use flag.
		bdf 	CHPRO_Next 									; skip if not in use.
		ldn 	re 											; get ID
		ani 	15 											
		xri 	1 											; if missile don't check.
		bz 		CHPRO_Next

		ghi 	re 											; point RF to x position.
		phi 	rf
		glo 	re
		adi 	3
		plo 	rf
		sex 	rf

		ldn 	rd 											; check |missile.X - object.X|
		smi 	1
		sm
		bdf 	CHPRO_1
		sdi 	0
CHPRO_1:smi 	2 											; check that value is < 2
		bdf 	CHPRO_Next

		inc 	rd 											; calculate |missile.Y - object.Y|
		inc 	rf
		ldn 	rd
		smi 	2
		sm
		dec 	rd
		bdf 	CHPRO_2
		sdi 	0
CHPRO_2:smi 	3
		bnf 	CHPRO_Hit

CHPRO_Next:
		glo 	re 											; go to next one
		adi 	ObjectRecordSize
		plo 	re
		xri 	ObjectEnd 									; loop back if not reached the end.
		bnz 	CHPRO_Loop
		sep 	r5

CHPRO_Hit:
		ldn 	rc 											; set delete on missile
		ori 	$40
		str 	rc
		ldn 	re 											; set delete on object
		ori 	$40
		str 	re
		glo 	re 											; did we hit the player object
		xri 	PlayerObject
		bnz		CHPRO_HitRobot

		ldi 	>LifeLost 									; lost a life.
		phi 	r3
		ldi 	<LifeLost
		plo 	r3
		sep 	r3

CHPRO_HitRobot:
		ldi 	Score+1 									; RF points to score+1
		plo 	rf 
		ldn 	re 											; Get object ID 2-4
		ani 	15
		smi 	1 											; now 1,2 or 3 representing 10,20,30 points
CHPRO_BumpScore:
		sex 	rf 											; add to the current digit.
		add
		str 	rf
		smi 	10 											; if < 10 then no carry out to next digit
		bnf 	CHPRO_Exit
		str 	rf 											; save modulo 10 value
		ldi 	1 											; carry 1 forward.
		inc 	rf
		br 		CHPRO_BumpScore
CHPRO_Exit:
		sep 	r5

; ***************************************************************************************************************************************
;	
;											Create Robots of type D at position RF.
;
; ***************************************************************************************************************************************

CreateRobot:
		phi 	re 											; save type in RE.1
		ldi 	>Random 									; random in R5
		phi 	r5
		ldi 	<Random
		plo 	r5
		sep 	r5 											; random number
		ani 	3 											; from 0-3 robots
		adi 	1 											; from 1-4 robots
		plo 	re 											; save in RE.0
CRBT_Loop:
		glo 	rf 											; reached end of storage space
		smi 	ObjectEnd-ObjectRecordSize*2
		bdf		CRBT_Exit 									; if not enough space for two objects then exit.
		ghi 	re 											; get type
		ori 	$20 										; set not-drawn-yet flag
		str 	rf 											; write to ID/Flags[0] and bump
		inc 	rf

		ghi 	re 											; type 2,3,4
		adi 	252 										; set DF if 4.
		ldi 	15 											; slow speed.
		bnf 	CRBT_0
		ldi 	7 											; fast speed.
CRBT_0:
		str 	rf 											; write to speed[1] and bump
		inc 	rf

		ldi 	0 											; write 0 to direction[2] and bump
		str 	rf
		inc 	rf

		dec 	r2 											; space on stack.

CRBT_XPosition:
		sep 	r5 											; random number 0-255
		ani 	7 											; 0-7
		smi 	5
		bdf		CRBT_XPosition
		adi 	5 											; 0-5
		shl 												; x2
		shl 												; x4
		str 	r2 
		shl 												; x8
		sex 	r2
		add 												; x12
		adi 	1
		str 	r2

		glo 	rf
		shr
		ani 	7
		add
		str 	rf 											; write to xPosition[3] 
		str 	r2

		ghi 	r2 											; RD ^ PlayerX
		phi 	rd
		ldi 	PlayerObject+3
		plo 	rd
		ldn 	rd 											; read PlayerX
		sm  												; PlayerX - RobotX
		bdf 	CRBT_NotAbs
		sdi 	0
CRBT_NotAbs:												; |PlayerX-RobotX|
		smi 	8
		bnf 	CRBT_XPosition

		inc 	rf 											; bump to yPosition[4]

CRBT_YPosition:
		sep 	r5 											; random number 0-255
		ani 	3 											; 0-3
		bz 		CRBT_YPosition 								; 1-3
		smi 	1 											; 0-2
		shl 												; x2
		str 	r2
		shl 												; x4
		shl 												; x8
		sex 	r2
		add 												; x10
		adi 	2 											; spacing
		str 	rf 											; write to yPosition[4]

		inc 	rf 											; move to next free slot
		inc 	rf

		ghi 	re 											; type 2,3,4
		xri 	2 											; if 2 skip
		bz 		CRBT_NotFire
		glo 	rf 											; 3 and 4 allow space for missile firer.
		adi 	ObjectRecordSize
		plo 	rf

CRBT_NotFire:
		inc 	r2 											; fix stack back.

		dec 	re 											; decrement the counter
		glo 	re
		bnz 	CRBT_Loop 									; keep going till zero.
CRBT_Exit:
		sep 	r3
		br 		CreateRobot 								; re-entrant subroutine.

		.org 	$DFF

