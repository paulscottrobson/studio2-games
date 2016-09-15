; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;											SCRAMBLE - For the RCA Studio 2 (1802 Assembler)
;											================================================
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
;		R7 		Sound Timer in S2 BIOS.
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

RamPage	= 8													; 256 byte RAM page used for Data ($800 on S2)
VideoPage = 9												; 256 byte RAM page used for Video ($900 on S2)

Studio2BeepTimer = $CD 										; Studio 2 Beep Counter
Studio2SyncTimer = $CE 										; Studio 2 Syncro timer.

PlayerY = $F0 												; Vertical Player Position (0-31)
Keypad = $F1 												; Keypad Status (see ScanKeypad routine)
Frame = $F2 												; Frame counter
Top = $F3 													; Number of blocks at the top (counter)
Bottom = $F4 												; Number of blocks at the bottom. (counter)
WallPointer = $F5 											; Current pointer into Wall Data

RandomSeed = $E0 											; Random seed (16 bits)
Lives = $E2  												; Lives remaining.
Frequency = $E3 											; n/256 chance of object creation
Speed = $E4
FuelByte = $E5 												; Fuel byte to overwrite
FuelMask = $E6 												; Fuel byte to write there - goes 7F, 7E, 7C, 78 etc. to zero.
FuelTopUp = $E7 											; Set to non-zero to top up fuel.
ScoreBump = $E8 											; Amount to add to score.
Score = $E9 												; Score (LSB first)

WallData = $00 												; 128 bytes of wall data (top,bottom). WallPointer points to current
															; so to get (say) column 12 you calculate (current-64+12)*2 % 128

; ***************************************************************************************************************************************
;
;														In game object definitions
;
; ***************************************************************************************************************************************

ObjectStart = $80 											; base address ($80-$A8)
ObjectRecordSize = 4 										; bytes per record
ObjectCount = 10 											; number of records
ObjectEnd = ObjectStart+ObjectRecordSize * ObjectCount 		; end address

BulletObject = ObjectStart 									; first is the bullet object.

; +0 	Y Position 		bit 7 signals not in use, bit 6 delete flag, bits 0-4 vertical position 0-31
; +1 	X Position 		bits 0-5 horizontal position 0-63, bits 6-7 zero (user flags)
; +2 	Graphic 		Graphic position in the graphics table or $00 if no graphic drawn.
; +3 	ObjectID 		Object number (0 = Missile, 1 = Bomb, 2 = Fuel, 3 = Rocket, 4 = Mine, 5 = Magnetic Mine)

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
;	Scroll the whole screen left except the bottom 2 lines. This is highly repetitive, but of course this is the bit that does the
;	most work in the whole system. In testing did 1,024 scrolls in 17 seconds, about 60 scrolls a second.
;
;	Draws the player when completed scrolling the top row of the player graphic. Moves the player according to the keys in 
;	"Keypad" (e.g. vertically up and down)
;
;	Breaks 	RE,RF. Returns D != 0 if Player has collided with anything, D = 0 keep going
;	Runs in (don't care)
;	Returns to R3
;
; ***************************************************************************************************************************************

ScrollScreenLeftDrawPlayer:
		ghi 	r2 											; Point RE to Keypad
		phi 	re
		ldi 	Keypad
		plo 	re
		ldn 	re 											; Read keypad state
		dec 	re 											; RE now points to Player Y
		shr 												; shift keypad LSB into DF
		bdf 	SSL_Up 										; which is the 'up' key.
		ani 	4 											; look at bit 4, which is down now we've done a SHR.
		bz 		SSL_NoMove

SSL_Down:
		ldn 	re 											; read player Y
		xri		$1C 										; don't move if reached $1C vertically
		bz 		SSL_NoMove
		ldi 	1 											; add 1 vertically
		br 		SSL_Move

SSL_Up:	ldn 	re 											; read player Y
		xri 	$02 										; don't move if reached $02 vertically
		bz 		SSL_NoMove
		ldi 	-1 											; subtract 1 vertically
SSL_Move:
		sex 	re 											; add to Player Y position and write back
		add
		str 	re
SSL_NoMove:
		ldn 	re 											; read the Player Y position
		sdi 	32											; calculate 32-position e.g. no of lines to draw before drawing player (+2 to centre)
		plo 	re 											; save in RE.

		ldi 	VideoPage 									; Point RF to VideoRAM + 29 * 8 + 7 - e.g. the last byte two lines up.
		phi 	rf
		ldi 	29*8+7
		plo 	rf
		sex 	rf 											; X = F so we can use STXD.
SSL_Loop: 													; Scroll the current line left
		ldn 	rf 											; Read byte 7 in
		shl 												; shift it left and decrement
		stxd
		ldn 	rf 											; Read byte 6 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 5 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 4 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 3 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 2 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 1 in
		shlc 												; shift left, shift carry out in
		stxd
		ldn 	rf 											; Read byte 0 in
		shlc 												; shift left, shift carry out in
		str 	rf											; save, now at start of line

		dec 	re 											; decrement the count-to-draw value
		glo 	re
		bnz		SSL_DontDrawPlayer 							

		ldi 	>PlayerSprite 								; point RE to player sprite
		phi 	re
		ldi 	<PlayerSprite
		plo 	re
SSL_DrawPlayerLoop:
		ldn 	re 											; if sprite zero don't collide test
		bz 		SSL_NoCollision
		ldn 	rf 											; read screen position.
		ani 	$01 										; if upper bits is non-zero then crash occurred , so exit with D != 0
		bnz 	SSL_Return
SSL_NoCollision:
		lda 	re 											; read sprite data from RE and bump it
		str 	rf 											; write to screen at RF.
		glo 	rf 											; add 8 to screen position
		adi 	8
		plo 	rf
		glo 	re 											; done all three lines.
		xri 	<(PlayerSpriteEnd)
		bnz 	SSL_DrawPlayerLoop

		glo 	rf 											; fix RF back so it points to the top again
		smi 	(PlayerSpriteEnd-PlayerSprite)*8
		plo 	rf
		ldi 	$FF 										; set the count-to-draw value so it won't be drawn again.
		plo 	re

SSL_DontDrawPlayer:
		glo 	rf 											; get LSB of end of line
		dec 	rf 											; end of previous line
		bnz 	SSL_Loop 									; keep going round until whole screen done, and return with D = 0.

SSL_AdjustEdges:
		ldi 	>Random 									; random number to RE.1
		phi 	r5
		ldi 	<Random
		plo 	r5
		sep 	r5
		phi 	re

		ldi 	Top 										; point RF to the "top" value.
		plo 	rf
		ghi 	r2
		phi 	rf

SSL_AdjustTopBottom:
		ghi 	re 											; get map information
		shr 												; put bit 0 (change bit) into DF
		bnf 	SSL_NoAdjustment 							; if clear then no adjustment
		shr 												; put bit 1 (decrement on change) into DF
		bdf 	SSL_AdjustDown

		ldn 	rf 											; read the current value (being adjusted up)
		adi 	1 											; add one to it.
		ani 	15 											; wrap at 15.
		bnz		SSL_AdjustNext	 							; if has wrapped max out at 15.
		ldi 	15 
		br 		SSL_AdjustNext

SSL_AdjustDown:
		ldn 	rf 											; read current value
		bz 		SSL_AdjustNext 								; if zero, don't adjust it.
		smi 	1 											; reduce it by 1.

SSL_AdjustNext: 											; save the final value for top or bottom
		str 	rf 											; save Top/Bottom
SSL_NoAdjustment:
		inc 	rf 											; point to next - 1 on

		ghi 	re 											; shift RE.1 left twice so second time uses
		shr 												; bits 3 and 2 instead.
		shr
		phi 	re

		glo 	rf 											; go back if on bottom e.g. does this twice
		xri 	Bottom
		bz 		SSL_AdjustTopBottom

		dec 	rf 											; read bottom 
		plo 	re 											; save bottom in RE.0
		ldn 	rf
		dec 	rf 											; point to top and add - want to check it's not too small.
		sex 	rf
		add
		smi 	12 											; if not too small
		bdf 	SSL_AdjustEdges 							; adjust until okay.
		nop
		nop
SSL_NotTooSmall:
		ldn 	rf 											; read Top in RE.1 , bottom in RE.0
		phi 	re 											
		inc 	rf
		ldn 	rf
		plo 	re
		ldi 	WallPointer 								; bump wall pointer, wrap around at 127, make even.
		plo 	rf
		ldn 	rf
		adi 	2
		ani 	$7E
		str 	rf
		plo 	rf 											; rf points to wall data now
		ghi 	re 											; write top and bottom there
		str 	rf
		inc 	rf
		glo 	re
		str 	rf

		ldi 	VideoPage 									; Make RE point to the top line.
		phi 	re
		ldi 	15 											; row 1 column 7.
		plo 	re

		ldi 	Top 										; RF points to 'Top'. 
		plo 	rf

		sex 	r2 											; make space on the stack.
		dec 	r2
		ldi 	8 											; store the add value, 8 there.
		str 	r2
SSL_DrawEdge:
		lda 	rf 											; read the size - top first time around
		phi 	rb 											; save in RB.1 - this is the counter.
SSL_SetEndBitLoop:
		ldn 	re 											; set the LSB in this screen cell
		ori 	$01
		str 	re
		glo 	re 											; add the offset on the stack
		add
		plo 	re
		ghi 	rb 											; check the counter
		bz 		SSL_DrawEdgeNext 							; then finished this time.
		smi 	1 											; decrement it
		phi 	rb		
		br 		SSL_SetEndBitLoop 							; and go round again
SSL_DrawEdgeNext:
		ldn 	r2 											; calculate offset = -offset
		sdi 	0
		str 	r2
		shl 												; shift bit 7 into DF
		bnf 	SSL_DrawEdgeExit 							; if NF then done top and bottom as is 8 again.
		ldi 	29*8+7 										; point RE to the bottom line
		plo 	re
		br 		SSL_DrawEdge

SSL_DrawEdgeExit:
		inc 	r2 											; fix the stack value.
		ldi 	0 											; return zero as not dead.
SSL_Return:
		sep 	r3

PlayerSprite: 												; sprite graphics. The zero surrounds erase the edges when moving
		.db		$00
		.db 	$0E
		.db 	$07
		.db		$0E
		.db		$00
PlayerSpriteEnd:


; ***************************************************************************************************************************************
;
;											Reduce Fuel by one. Return D = 0 if fuel out.
;
; ***************************************************************************************************************************************

ReduceFuel:
		ghi 	r2 											; point RF to the Byte position
		phi 	rf
		ldi 	FuelByte
		plo 	rf
		lda 	rf 											; read byte, advance to fuel mask.
		plo 	re 											; RE to point to screen byte
		ldi 	VideoPage
		phi 	re
		ldn 	rf 											; read byte
		str 	re 											; store at screen
		shl 												; shift it left and write back
		str 	rf
		bz 		RF_PrevByte 								; return non-zero, fuel okay.
		sep 	r3
RF_PrevByte:
		str 	re
		ldi 	$FF 										; reset mask to $FE
		str 	rf
		dec 	rf 											; point to byte position.
		ldn 	rf 											; decrement it
		smi 	1
		str 	rf
		xri 	$F7 										; will return zero if out of fuel - bar gone back too far.
		sep 	r3

; ***************************************************************************************************************************************
;
;	     Moves all object positions 1 to the left to account for scrolling, anything reaching zero delete the object record.
;
;	(Split off from screen scroller due to size/boundary issues)
;
; ***************************************************************************************************************************************

ShiftObjects:
		ldi 	ObjectStart									; point RF to objects
		plo 	rf
		ghi 	r2
		phi 	rf
SHO_ShiftObjects:
		lda 	rf 											; read Object Y (RF[0]), point at Object X (RF[1])
		shl 												; check bit 7 (if set then unused)
		bdf 	SHO_NextObject 								; if set then no object here.

		ldn 	rf 											; decrement X position
		smi 	1 											
		str 	rf 											
		bnz 	SHO_NextObject 								; if reached LHS delete it, it will scroll off.
		dec 	rf 											; point to Object Y (RF[0])
		ldi 	$FF 										; write $FF there.
		str 	rf
		inc 	rf 											; point back to ObjectX (RF[1])
SHO_NextObject:
		glo 	rf 											; add record size - 1 (because of the LDA)
		adi 	ObjectRecordSize-1
		plo 	rf
		xri 	ObjectEnd 									; reached the end ?
		bnz 	SHO_ShiftObjects
		sep 	r3

; ***************************************************************************************************************************************
;
;										LFSR Random Number Generator (breaks RF)
;
; Returns to : R4 Breaks RF. Reentrant subroutine.
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
		sep 	r4 											; and exit.
		br 		Random

; ***************************************************************************************************************************************
;
;														 Keypad Scanner
;
; 	Scans keyboard for 2,4,6,8,0 returned in bits 0,1,2,3,7 respectively. Note correlation between these bits (Up,Left,Right,Down)
;	and the bit patterns in the map. 0 is used to start. Stores in Keypad variable.
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
		dec 	r2
		str 	r2 											; save on stack
		ghi 	r2 											; point RF to keypad
		phi 	rf
		ldi 	Keypad
		plo 	rf
		lda 	r2 											; restore value
		str 	rf 											; save it.
		sep 	r3 											; and exit
		br 		ScanKeypad

; ***************************************************************************************************************************************
;
;														Initialise Level
;	
; ***************************************************************************************************************************************
	
InitialiseLevel:
		ldi 	VideoPage 									; point RE,RF to video
		phi 	rf
		phi 	re
		ldi 	0 											; clear screen
		plo 	rf
IL_Clear:
		ldi 	0
		str 	rf
		inc 	rf
		glo 	rf
		bnz 	IL_Clear
		dec 	rf 											; RF still on video page
		ldi 	8 											; RE ^ top solid line
		plo 	re
		ldi 	29*8 										; RF ^ bottom solid line
		plo 	rf
IL_Set:	ldi 	$FF 										; draw solid lines
 		str 	re
 		str 	rf
 		inc 	re
 		inc 	rf
 		glo 	re 											; do all 8 bytes
 		xri 	16
 		bnz 	IL_Set

 		ghi 	r2 											; point RE to lives count
 		phi 	re
 		ldi 	Lives
 		plo 	re
 		ldn 	re 											; read lives, put lives in RE.0
 		plo 	re
 		ldi 	255 										; RF points to lives area.
 		plo 	rf
IL_Lives:
		ldi 	$0F
		str 	rf
		dec 	rf
		dec 	re
		glo 	re
		bnz 	IL_Lives

		ldi 	ObjectStart									; RE now points to objects (RE.1 points to data)
		plo 	re
IL_EraseObjects:
		ldi 	$FF 										; fill the whole table with $FF
		str 	re
		inc 	re
		glo 	re
		xri 	ObjectEnd 									
		bnz 	IL_EraseObjects

		ldi 	PlayerY 									; reset the Y Player position half way down
		plo 	re
		ldi 	16
		str 	re
 		sep 	r3 											; and return.

; ***************************************************************************************************************************************
;										Partial line plotter - xors one row of 3 pixels
;
;	On entry, D contains pattern, RF points to the Video RAM to alter.
;	On exit, RF is up one (e.g. -8) we draw sprites upwards.
;
;	Runs in R6. Returns to R5. Breaks RE
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
PX_XorRE:													; XOR with RE
		sex 	rf 
		glo 	re 											; XOR [RF] with RE.0
		xor 	
		str 	rf
		inc 	rf 											; XOR [RF+1] with RE.1
		ghi 	re
		xor
		str 	rf
		glo 	rf 											; go up one row
		smi 	9
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
		xor
		str 	rf
		glo 	rf 											; go up one row
		smi 	8
		plo 	rf
		sep 	r5 											; and exit


; ***************************************************************************************************************************************
;
;															Create new object
;
; breaks RC,RD,RE,RF
; runs in R4, returns to R3.
; ***************************************************************************************************************************************

CreateNewObject:
		ldi 	>Random 									; put RNG function in R5
		phi 	r5
		ldi 	<Random
		plo 	r5
		sep 	r5 											; get a random number.
		plo 	re 											; save in RE.0

		ldi 	Frequency 									; point RF to frequency
		plo 	rf
		ghi 	r2
		phi 	rf
		glo 	re 											; retrieve random number
		sex 	rf 											; add Frequency value
		add
		bdf 	CNO_Create									; create one [Frequency] out of 256 times
		sep 	r3
CNO_Create:
		ghi 	r2 											; point RD to the second object to find an empty slot
		phi 	rd 											; (first object is player missile)
		phi 	re
		ldi 	ObjectStart+ObjectRecordSize
		plo 	rd
CNO_FindUnused:
		ldn 	rd 											; look at Y bit 7, if set, record is unused
		shl
		bdf 	CNO_FoundSlot
		glo 	rd 											; go to next record.
		adi 	ObjectRecordSize
		plo 	rd
		xri 	ObjectEnd
		bnz 	CNO_FindUnused 								; loop round if not finished searching.
		sep 	r3

CNO_FoundSlot:
		ldi 	WallPointer 								; RE points to wall entry.
		plo 	re
		ldn 	re 											; read wall pointer, Make RE point to it.
		plo 	re
		inc 	re 											; RE points to bottom.
		ldn 	re 											; read bottom.		
		sdi 	28 											; convert to a coordinate.
		str 	rd 											; store in Y
		plo 	rc 											; save in RC.0
		inc 	rd
		ldi 	61 											; store 61 in X
		str 	rd
		inc 	rd
		ldi 	0
		str 	rd 											; store 61 in current graphic.
		sep 	r5 											; generate a random ID from 0-3
		ani 	3
		adi   	2 											; now it is 2-5
		inc 	rd
		str 	rd 											; store this in ID.
		ani 	4 											; if it is 4 or 5 then resposition vertically
		bnz		CNO_NotAtBottom
															; 2 or 3 so clear the bottom bit.
		glo 	rc 											; get bottom position								
		shl 												; x 8
		shl
		shl
		adi 	7 											; add 7
		plo 	rc 											; set RC to point to video RAM
		ldi 	VideoPage
		phi 	rc
		ldn 	rc 											; clear 3 bits.
		ani 	$F8
		str 	rc
		sep 	r3

CNO_NotAtBottom: 											; 4 and 5 so put somewhere in the middle of the cavern.
		dec 	re 											; RE now points to top RE+1 to bottom
		dec 	rd 											; point RD to vertical position. 										
		dec 	rd		
		dec 	rd
		glo 	rc 											; get bottom position
		sex 	re
		sm  												; D = bottom - top i.e. range to use.
		dec 	r2 											; save range on stack.
		str 	r2
		sex 	r2
CNO_FindYPosition:
		sep 	r5 											; generate random number
		ani 	31 											; range 0-31
		sex 	r2
		sm 													; subtract range
		bdf 	CNO_FindYPosition 							; keep going until value in range
		add 												; add back on to get range
		sex 	re
		add 												; add to top value to give position
		str 	rd 											; save in vertical position
		inc 	r2 											; fix stack back.
		sep 	r3

; ***************************************************************************************************************************************
;													Draw one graphics character
;
;	Breaks RE (drawer uses it) ,RF (video RAM), RD (graphic data), RB.1 (LSB of call)
;
;	Runs in R5, returns to R4.
; ***************************************************************************************************************************************

DrawGraphic:
		inc 	rc 											; point to the X position RC[1]
		inc 	rc 											; point to the graphic to draw RC[2]
		ldn 	rc 											; read that graphic number
		dec 	rc 											; point to X position, RC[1]
		bnz 	DGR_DrawOkay 								
		dec 	rc  										; if graphic number was zero, fix up RC and return.
		sep 	r4 

DGR_DrawOkay:
		plo 	rd 											; the value read from RC[2] is put into RD to make a pointer to the 
		ldi 	>GfxData 									; sprite data.
		phi 	rd

		ldn 	rc 											; read RC[1], the X position.
		ani 	7 											; get the 3 MSB
		shl 												; double them
		adi 	<PartialXorPlot 							; point to the partial plotter to use.
		phi 	rb

		ldn 	rc 											; read RC[1], X, again, and divide by 8
		ani 	63 											; put in the range 0-63.
		shr
		shr
		shr
		dec 	r2 											; save this offset on the top of the stack
		str  	r2

		dec 	rc 											; point RC at RC[0], Y, read this in, and multiply by 8.
		ldn 	rc
		shl
		shl
		shl
		sex 	r2 											; add to the offset from X
		add 	
		plo 	rf 											; save in RF.0 which will point to the graphic data.
		inc 	r2 											; fix the stack back up.

		ldi 	>PartialXorPlot 							; R6.1 points to the MSB of the plot routine and keeps that value.
		phi 	r6
		ldi 	VideoPage 									; point RF to the video page.
		phi 	rf
DGR_Loop:
		ghi 	rb 											; set R6 to point to the Partial Xor Plot routine to use.
		plo 	r6
		lda 	rd 											; read graphic data to output into D
		bz 		DGR_Exit 									; if zero then finished.
		sep 	r6 											; call the plot routine
		br 		DGR_Loop

DGR_Exit:
		sep 	r4

; ***************************************************************************************************************************************
;															Move Object pointed to by RC.
;
; Runs in R4 returns to R3.
; ***************************************************************************************************************************************

MoveObject:
		ldn 	rc 											; if deleting, go to erase part
		ani 	$40
		bnz 	MOB_Erase 								

		ghi 	rc 											; point RE to the graphic
		phi 	re
		glo 	rc
		adi 	2
		plo 	re
		lda 	re 											; read the graphic
		bz 		MOB_Erase 									; if zero e.g. never drawn go through erase/repaint
		ldn 	re 											; read the ID.
		ani 	7 											; mask lower 4 bits
		smi 	2 											; do nothing if '2' or '4' as they don't move.
		bz 		MOB_Exit
		smi 	2
		bz 		MOB_Exit

MOB_Erase:
		ldi 	>DrawGraphic								; erase current graphic if drawn.
		phi 	r5
		ldi 	<DrawGraphic
		plo 	r5
		sep 	r5

		ldn 	rc 											; check if delete is on.
		ani 	$40
		bnz 	MOB_Delete	

		inc 	rc 											; point to RC[3] the ID.
		inc 	rc
		inc 	rc
		ldn 	rc 											; read it
		ani  	7 											; only interested in lower 3 bits.
		phi 	rb 											; save ID in RB.1
		adi 	<Gfx_LowerByteTable 						; point RF to the lower byte table entry
		plo 	rf
		ldi 	>Gfx_LowerByteTable 						
		phi 	rf
		ldn 	rf 											; read the graphic from the table
		dec 	rc
		str 	rc 											; copy into graphic entry
		dec 	rc 											; fix RC to point to the original entry
		dec 	rc

		ghi 	rb 											; get the ID and 7
		shl 												; double it
		adi 	<MoveVectorTable 							; add to vector table base.
		plo 	re
		ldi 	>MoveVectorTable
		phi 	re
		lda 	re 											; read call address into R5
		phi 	r5
		ldn 	re
		plo 	r5

		ldi 	WallPointer 								; point RE to wall pointer
		plo 	re
		ghi 	r2
		phi 	re

		inc 	rc 											; read X Position
		ldn 	rc
		dec 	rc
		sdi 	63 											; D = (63 - X Position)
		shl 												; D = ((63 - X Position) x 2)
		sex 	re
		sd     												; wallpointer - ((63 - xPosition) x 2)
		ani 	$7E 										; in range 00-7E
		plo 	rf 											; RF now points to top,bottom gaps.
		ghi 	r2
		phi 	rf
		ldn 	re 											; D = Wallpointer.
		sep 	r5 											; and call.

MOB_RepaintAndExit: 										; redraw post move and exit
		ldi 	>DrawGraphic
		phi 	r5
		ldi 	<DrawGraphic
		plo 	r5
		sep 	r5
		br 		MOB_Exit

MOB_Delete: 												; marked for deletion, delete it.
		ldi 	$FF
		str 	rc
MOB_Exit:
		sep 	r3

MoveVectorTable: 											; pointers to movement code for the various types
		.dw 	MVC_Bullet 									; 0 Horizontal Bullet
		.dw 	MVC_Bomb 									; 1 Diagonal Bomb
		.dw 	NoMove 										; 2 Fuel Dump (never moves)
		.dw 	MVC_Rocket									; 3 Rocket
		.dw 	NoMove 										; 4 Stationary mine (never moves)
		.dw 	MVC_MagMine									; 5 Magnetic Mine

NoMove:	sep 	r4

; ***************************************************************************************************************************************
; 														Move code for Magnetic Mines
; ***************************************************************************************************************************************

MVC_MagMine:
		ani 	15 											; slow down movement
		bz 		MVCM_MoveMM
		sep 	r4
MVCM_MoveMM:
		ldi 	PlayerY 									; read player Y position
		plo 	rf
		ghi 	r2
		phi 	rf
		ldn 	rf
		sex 	rc 											; subtract from MM Y Position
		sm
		bz 		MVCM_Exit 									; if zero, exit
		ldi 	1 											; otherwise add 1 or -1 to vertical position, chasing.
		bdf 	MVCM_Adjust
		ldi 	-1
MVCM_Adjust:
		add 												; add to Y.
		str 	rc 											; store in Y.
MVCM_Exit:
		sep 	r4

; ***************************************************************************************************************************************
;														Move code for Rocket
; ***************************************************************************************************************************************

MVC_Rocket:
		ani 	3 											; slow down movement
		bnz		MVCR_Exit
		inc 	rc 											; point to X
		ldn 	rc 											; read X
		dec 	rc
		adi 	-16 										; don't move until reached this point.
		bdf 	MVCR_Exit
		ldn 	rc 											; decrement Y
		smi 	1
		str 	rc
		smi 	2 											; allow for rocket height.
		sex 	rf 											; same as top ?
		xor 	
		bnz 	MVCR_Exit

		ldn 	rc 											; set the deletion flag for next time
		ori 	$40
		str 	rc
MVCR_Exit:
		sep 	r4


; ***************************************************************************************************************************************
;																Move Bullet
; ***************************************************************************************************************************************

MVC_Bomb: 													; Bomb code goes down as well as across
		ldn 	rc 											; increment Y
		adi 	1
		str 	rc
		inc 	rc
		ldn 	rc 											; increment X
		adi 	1
		str 	rc
		dec 	rc

		inc 	rf 											; point to bottom
		ldn 	rf 											; read bottom.
		sdi 	28 											; coordinate of bottom
		sex 	rc 											; reached the bottom, then delete it
		sm 
		bnf		MVCB_Delete
		sep 	r4

MVC_Bullet:													; Bullet across only.
		inc 	rc
		ldn 	rc 											; go forward X 2. 
		adi 	2
		str 	rc
		dec 	rc
		adi 	-62											; have we reached 62 or more ?
		bdf 	MVCB_Delete
		sep 	r4

MVCB_Delete:
		ldn 	rc
		ori 	$40
		str 	rc
		sep 	r4

; ***************************************************************************************************************************************
;												Check Collision with Player Missile
;
;	RC object to check.
; ***************************************************************************************************************************************

CollidePlayerMissile:
		glo 	rc 											; is the object being tested the player missile ?
		xri 	ObjectStart
		bz 		CPM_Exit 									; if so, then exit.
		ldn 	rc 											; read Object Y
		ani 	$C0
		bnz 	CPM_Exit 									; if object is being deleted or not in use, then exit now.
		ghi 	r2 											; point RD to the Player Missile
		phi 	rd
		ldi 	ObjectStart
		plo 	rd
		ldn 	rd 											; read PM Object Y
		ani 	$C0
		bnz 	CPM_Exit 									; if PM is being deleted or not in use, then exit now.

		ldn 	rc 											; calculate Object.Y - PM.Y
		sex 	rd
		sm  												; 0,1,2 adjusted for centre position.
		adi 	-3
		bdf 	CPM_Exit 

		inc 	rc 											; point to X
		inc 	rd
		ldn 	rc 											; calculate Object.X - PM.X
		sm 													; -1,0,1 collision
		adi 	1 											; 0,1,2 acceptable
		adi 	-3
		dec 	rc 											; fix RC,RD back up
		dec 	rd
		bdf 	CPM_Exit

		ldn 	rc 											; mark RC,RD for deletion.
		ori 	$40
		str 	rc
		ldn 	rd
		ori 	$40
		str 	rd

		glo 	rc 											; RD points to ID
		adi 	3
		plo 	rd

		ldi 	FuelTopup 									; RF points to Fuel topup flag.
		plo 	rf
		ghi 	r2
		phi 	rf

		ldn 	rd 											; read ID
		ani 	7 											; only interested in lower 3 bits.
		xri 	2 											; is it object #2, a fuel dump ?
		bnz 	CPM_NotFuel
		ldi 	$FF 										; if so set the fuel dump flag.
		str 	rf
CPM_NotFuel:

		ldn 	rd 											; read ID again
		ani 	7
		adi 	<CPM_ScoreTable 							; point RE to Score Table for this ID
		plo 	re
		ldi 	>CPM_ScoreTable
		phi 	re

		sex 	re 											; index -> score table entry.
		inc 	rf 											; rf now points to ScoreBump
		ldn 	rf 											; add score table entry to score bump
		add
		str 	rf

		ldi 	15 											; longer beep
		str 	r7
CPM_Exit:
		sep 	r3

CPM_ScoreTable:
		.db 	0,0,10/10,20/10,40/10,50/10 				; score for various objects, divided by 10.

; ***************************************************************************************************************************************
;
;														Add ScoreBump to Score
;
; ***************************************************************************************************************************************

AddScoreBump:
		ldi 	ScoreBump 									; point RF to score bump
		plo 	rf
		ghi 	r2
		phi 	rf
		lda 	rf 											; load bump value, bump to first score digit
		bz 		ASB_Exit 									; exit if zero.
ASB_Loop:
		inc 	rf 											; bump to next score digit.
		sex 	rf
		add 												; add bump amount to score digit.
		str 	rf
		smi 	10 											; carry out ?
		bnf 	ASB_Exit
		str 	rf 											; write back -10 value
		ldi 	1 											; loop round to next score digit add 1
		br 		ASB_Loop

ASB_Exit:
		ldi 	ScoreBump 									; zero score bump
		plo 	rf
		ldi 	$00
		str 	rf
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
;																Object Graphics
; ***************************************************************************************************************************************

;	.org 	ROMSecondChunk+$1E8

GfxData:

Gfx_Bullet:
		.db 	$40,0 										; player bullet or bomb.
Gfx_Rocket:
		.db 	$A0,$E0,$40,0 								; player rocket.
Gfx_Fuel:	
		.db 	$E0,$E0,$A0,0 								; fuel dump.
Gfx_Mine:
		.db 	$40,$E0,$40,0 								; stationary mine.
Gfx_MoveMine:
		.db 	$A0,$40,$A0,0 								; moving mine.
Gfx_LowerByteTable: 										; table of lower bytes of graphics.
		.db 	<Gfx_Bullet
		.db 	<Gfx_Bullet
		.db 	<Gfx_Fuel
		.db 	<Gfx_Rocket
		.db 	<Gfx_Mine
		.db 	<Gfx_MoveMine

GfxPrompt:
        .db     $F7,$81,$B7,$90,$F4,$00 					; G?

; ***************************************************************************************************************************************
;													Go to the start new level code. Can't LBR
; ***************************************************************************************************************************************

GoStart:
		ldi 	>RestartLevel 								; load P3 with Restart Level
		phi 	r3
		ldi 	<RestartLevel
		plo 	r3
		sep 	r3 											; and go there.

; ***************************************************************************************************************************************
;
;														SECOND ROM SECTION 
;
; ***************************************************************************************************************************************
    	.org 	0C00h

RomSecondChunk:

; --------------------------------------------------------------------------------------------------------------------------------------
;															Restart Level
; --------------------------------------------------------------------------------------------------------------------------------------

RestartLevel:
    	ldi 	>InitialiseLevel 							; initialise the level.
    	phi 	r4
    	ldi 	<InitialiseLevel
    	plo 	r4
    	sep 	r4

    	ldi 	>ScanKeypad 								; set R4 for keypad scan (re-entrant)
    	phi 	r4
    	ldi 	<ScanKeypad
    	plo 	r4
RSL_WaitRelease: 											; wait for all keys to be released
		sep 	r4
		bnz 	RSL_WaitRelease
RSL_WaitPress:
		sep 	r4 											; wait for right key to be pressed to start level.
		ani 	$04 
		bz 		RSL_WaitPress

; --------------------------------------------------------------------------------------------------------------------------------------
;													Come back here to reset fuel
; --------------------------------------------------------------------------------------------------------------------------------------

ResetFuel:
		ghi 	r2 											; point RF to fuel topup
		phi 	rf
		ldi 	FuelTopup
		plo 	rf
		sex 	rf 											; use F as index
		ldi 	0 											; clear Fuel topup Flag
		stxd
		ldi 	$FE 										; fuel write mask to $FE
		stxd
		ldi 	$FC 										; fuel bar write in $FC
		stxd
		plo 	rf 											; save in RF.0
		ldi		VideoPage 									; set RF.1 to point to fuel bars
		phi 	rf
		ldi 	$FF 										; write out five fuel bars.
		stxd
		stxd
		stxd
		stxd
		stxd

; ***************************************************************************************************************************************
;																Main Loop
; ***************************************************************************************************************************************

MainGameLoop:
    	ldi 	>ScanKeypad 								; Update the keypad current status
    	phi 	r4
    	ldi 	<ScanKeypad
    	plo 	r4
		sep 	r4
		phi 	rb 											; save in RB.1

; --------------------------------------------------------------------------------------------------------------------------------------
;								If the fuel top up is flag (e.g. fuel hit) refuel the ship
; --------------------------------------------------------------------------------------------------------------------------------------

		ghi 	r2 											; read the fuel topup flag, set when a fuel store is blown up.
		phi 	rf
		ldi 	FuelTopup
		plo 	rf
		ldn 	rf
		bnz		ResetFuel 									; if it is set, reset the fuel (which also clears the flag)

; --------------------------------------------------------------------------------------------------------------------------------------
; 								Bump the frame number, reduce fuel count, quit if zero.
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	frame 										; point RF to Frame #
		plo 	rf
		ldn 	rf 											; increment the frame #
		adi 	1
		str 	rf 											; and save it back.
		dec 	r2 											; save frame # on stack
		str 	r2
		ani 	15 											; one frame in sixteen
		bnz 	SkipFuelReduce

		ldi 	>ReduceFuel 								; reduce the fuel count.
		phi 	r4
		ldi 	<ReduceFuel
		plo 	r4
		sep 	r4
		bz 		Dead 										; out of fuel, dead.
SkipFuelReduce:

; --------------------------------------------------------------------------------------------------------------------------------------
;				   Move player one frame in four/one frame in 2 dependent on brakes - this is the firing bit.
; --------------------------------------------------------------------------------------------------------------------------------------

		lda 	r2 											; reload frame # off stack and fix stack.
		shr 	
		bnf 	DontMovePlayer 								; if frame bit 0 clear don't move player
		shr 	
		bnf 	MoveCheckFirePlayer 						; if frame bit 1 clear move player.	
		ghi 	rb 											; reload keyboard current status.
		ani 	2 											; if left pressed 
		bnz		DontMovePlayer								; then apply the brakes.

MoveCheckFirePlayer:

		ghi 	rb 											; get keyboard status.
		shl 												; check bit 7 (fire)
		bnf 	DontFireBomb 								; if not set, then skip.

		ldi 	ObjectStart 								; point RF to object base i.e. the player missile object
		plo 	rf
		ghi 	r2
		phi 	rf
		phi 	re
		ldn 	rf 											; read player missile object
		shl
		bnf 	DontFireBomb 								; skip if player missile object is already in use.

		ldi 	PlayerY 									; get vertical player position
		plo 	re
		ldn 	re 											; read it
		str 	rf 											; store in player missile object[0]
		inc 	rf
		ldi  	8 											; store 8 in pm[1]
		str 	rf
		ldi 	0 											; store 0 in pm[2]
		inc 	rf
		str 	rf
		inc 	rf

		ghi 	rb 											; scan keypad
		ani 	2 											; now 2 if braking, 0 if firing
		shr 												; now 1 if braking (bomb), 0 if firing (missile)
		str 	rf 											; store this ID in pm[3]

		ldi 	4 											; short beep.
		str 	r7
DontFireBomb:		

; --------------------------------------------------------------------------------------------------------------------------------------
;						 Scroll screen left, update all object positions because of this scrolling
; --------------------------------------------------------------------------------------------------------------------------------------

    	ldi 	>ScrollScreenLeftDrawPlayer 				; Scroll the screen left, update the player position.
    	phi 	r4
    	ldi 	<ScrollScreenLeftDrawPlayer
    	plo 	r4
    	sep 	r4
    	bnz 	Dead 										; collision occurred, lose life

    	ldi 	>ShiftObjects 								; move all object positions left.
    	phi 	r4
    	ldi 	<ShiftObjects
    	plo 	r4
    	sep 	r4

; --------------------------------------------------------------------------------------------------------------------------------------
;								Create a new object (e.g. rocket, mine, fuel dump), possibly
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	<WallPointer								; call creation code one time in 4, use Wall Pointer
		plo 	rc
		ghi 	r2
		phi 	rc
		ldn 	rc
		ani 	15
		bnz 	DontCreateNewObject
		ldi 	>CreateNewObject 							; call object creation code
		phi 	r4
		ldi 	<CreateNewObject
		plo 	r4
		sep 	r4
DontCreateNewObject:

DontMovePlayer:

; --------------------------------------------------------------------------------------------------------------------------------------
;							Move all the objects up/down (sideways done by scroller) and check collision
; --------------------------------------------------------------------------------------------------------------------------------------
		
		ghi 	r2 											; move all objects. Point RC to the object list.
		phi 	rc
		ldi 	ObjectStart
		plo 	rc
MoveAllObjects:
		ldn 	rc 											; check bit 7 of Y which is the 'in use' bit.
		shl
		bdf 	MAO_Next 									; if set then skip

		ldi 	>CollidePlayerMissile 						; test object collides with player/missile.
		phi 	r4
		ldi 	<CollidePlayerMissile
		plo 	r4
		sep 	r4
		ldi 	>MoveObject 								; point R4 to the Move routine
		phi 	r4
		ldi 	<MoveObject
		plo 	r4
		sep 	r4 											; call the Move routine
		ldi 	>CollidePlayerMissile 						; test object collides with player/missile.
		phi 	r4
		ldi 	<CollidePlayerMissile
		plo 	r4
		sep 	r4

MAO_Next:
		glo 	rc		 									; point to the next objects
		adi 	ObjectRecordSize
		plo 	rc
		xri 	ObjectEnd 									; until reached the end.
		bnz		MoveAllObjects

; --------------------------------------------------------------------------------------------------------------------------------------
;													Transfer Scorebump value to score
; --------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>AddScoreBump 								; call Score Bump routine.
		phi 	r4
		ldi 	<AddScoreBump
		plo 	r4
		sep 	r4

; --------------------------------------------------------------------------------------------------------------------------------------
;											Synchronise against Studio II Timer and go round again
; --------------------------------------------------------------------------------------------------------------------------------------

    	ldi 	Studio2SyncTimer							; point RF to the Sync Timer.
    	plo 	rf
    	ghi 	r2
    	phi 	rf
    	phi 	re
    	ldi 	Speed 										; point RE to speed
    	plo 	re
Sync:	ldn		rf 											; wait for sync
		bnz 	Sync

		ldn 	re 											; reset sync timer from speed.
		str 	rf

    	br		MainGameLoop								; and go round again.

; --------------------------------------------------------------------------------------------------------------------------------------
;														Player Lost a Life
; --------------------------------------------------------------------------------------------------------------------------------------

Dead:	ldi 	40 											; long beep
		str 	r7
		ldi 	Lives 										; point RF to lives
		plo 	rf
		ghi 	r2
		phi 	rf
		ldn 	rf 											; decrement lives
		smi 	1
		str 	rf
		bnz 	RestartLevel								; if lives > 0 restart the level
		br 		EndGame

; --------------------------------------------------------------------------------------------------------------------------------------
;														End Game, Display Score
; --------------------------------------------------------------------------------------------------------------------------------------

		.org 	RomSecondChunk+$0FF 						; go here to roll through to next page

EndGame:
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

		ldi 	$FF
		sep 	ra
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
		ldi 	$FF
		sep 	ra

		dec 	re 											; previous value of 3 LSBs.
		glo 	re
		ani 	7
		bnz 	ScoreWriteLoop

Halt:	br 		Halt 										; game over, stop forever.

; ***************************************************************************************************************************************
;
;															Game starts here
;
; ***************************************************************************************************************************************

StartGame:
		ghi 	r2 											; point RC to Speed
		phi 	rc
    	ldi 	Speed
    	plo 	rc

    	ldi 	>GfxPrompt 									; point RE to GfxPrompt
    	phi 	re
    	ldi 	<GfxPrompt
    	plo 	re
    	ldi 	VideoPage 									; point RF to Video RAM
    	phi 	rf
    	ldi 	12*8+4
    	plo 	rf
SG_PromptLoop:
		lda 	re 											; read next prompt byte and bump
		bz 		SG_WaitKey
		str 	rf
		glo 	rf 											; next VRAM line down.
		adi 	8
		plo 	rf
		br 		SG_PromptLoop

SG_WaitKey:
		ldi 	>ScanKeypad 								; set keypad code
		phi 	r4
		ldi 	<ScanKeypad
		plo 	r4
		sep 	r4  										; read it
		bnz 	SG_WaitKey 									; wait for release
SG_WaitKey2:
		sep 	r4 											; read it again.
		ani 	7 											; only interested in 2,4 and 6. Returns 1,2,4 respectively.
		bz 		SG_WaitKey2
		xri 	4 											; change 4 to 3
		bnz 	SG_Not4
		ldi 	3^4
SG_Not4:xri 	4 											; now we have 1,2,3 for easy,medium,hard

		sdi 	5 											; now we have 4,3,2 for easy,medium,hard

    	sex 	rc
    	stxd 												; store speed
    	sdi 	4 											; 4-speed e.g. 0 for slow, 1 medium,2 for fast
    	shr 												; multiply by 64, 0,64,128
    	shrc
    	shrc
    	adi 	100 										; 100,164,228 probabilities.
    	stxd
    	ldi 	3 											; set Lives to 3, Random Seed Byte to 3.
    	stxd
    	stxd

    	ghi 	r2 											; point R7 to Sound Byte
    	phi 	r7
    	ldi 	Studio2BeepTimer
    	plo 	r7

    	ldi 	<GoStart 									; go to the start of the main code
    	plo 	r4
    	ldi 	>GoStart
    	phi 	r4
    	sep 	r4