; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;											PACMAN - For the RCA Studio 2 (1802 Assembler)
;											==============================================
;
;	Author : 	Paul Robson (paul@robsons.org.uk)
;	Tools :		Assembles with asmx cross assembler http://xi6.com/projects/asmx/
;
;	Note: 		This is the first >1k RCA Studio 2 Game. It just won't fit in 1k - unless you ridiculously simplify the game.
;				It is designed to fit in 1.5k ROM. Some features have been lost, noteably no extra life for 10,000 points 
; 				and the basic score display.
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
;		R7 		Points to sound counter.
; 		RA 		Points to the current sprite
;
;		1802 Porting notes:
;
;		(1) Keypad I/O is done via the ScanKeypad routine. Because of Branch boundaries it may be simpler to rename this routine
;			DeadScanKeypad and create a functionally equivalent one for the target machine. Though the Cosmac VIP one might work
; 			with BN3 becoming B3 (as the Cosmac VIP has an inverted return value). On an Elf keyboard latch it will probably work
; 			quite well, because Pacman controls are changes of direction of a moving object. (use the IN button for the '0' bit.)
;
;		(2) 2 pages of RAM are required. One is a data page, the other a video page rendered in the normal 64x32 1861 fashion.
;			It doesn't matter where these are on a 1802 machine, the locations given are fixed by the RCA Studio 2. All other 
; 			code is ROMmable (though if it does run in RAM it doesn't matter)
;
;		(3) This image is over 1k long. Thus it is chopped up into two parts (look through the file for the origins). These can be
; 			anywhere in memory, this particular layout is again for the Studio 2. Game ROM is at $400-$7FF,$A00-$BFF.
;
;		(4) Sound. R7 throughout points to a counter. This should be decremented every video frame, and a sound effect played
; 			if this is non-zero (e.g. basically an n/50th sound counter). This is done automatically by the Video Routine in the
;			S2. If you ignore it it doesn't matter but make sure writes to R7 don't muck anything up.
;
;		(5) There is no use of other S2 counters or the R9 frame tick register.
;
;		(6) The Program expects to start with P = 3 running from StartGame: there is a little preamble at the start which is
; 			the S2's jump vector.
;
; ***************************************************************************************************************************************
;
; 											SPRITE RECORD (0 = Player, 1-4 = Ghost, 5 = Bonus)
;
;	+0 		X position in pixels (0,0 is top left)
;	+1 		Y position in pixels 
;	+2 		Last Drawn/New Image - when something is drawn the graphic is put here for erasing.
;	+3 		Movement direction (4 bits, same bit patterns as walls UDLR)
;	+4 		Legal movements this turn (4 bits, same as +3), bit 7 is set if the sprite is at a junction (x % 6 == 0, y % 5 == 0)
;	+5,+6 	High,Low : Method to call (call via R5,return to R4) to select the sprite to be used.
; 	+7,+8 	High,Low : Method (as above) to select the new movement direction
;	+9,+10 	High,Low : Method (as above) Call this if it collides with sprite 0 (which is the player sprite)
; 	+11 	Cell Number (e.g. offset in maze table, only valid when legal movements bit 7 is set.)
;	+12..13 (X,Y) position of the old position.
;	+14..15	Status bytes for the sprite object (if needed)
;
; ***************************************************************************************************************************************

RamPage	= 8													; 256 byte RAM page used for Data ($800 on S2)
VideoPage = 9												; 256 byte RAM page used for Video ($900 on S2)

FramesPerChasingTimer = 128									; number of moves allowed when chasing ghosts.
BonusRate = 192 											; bonus frame counter goes 0-255 - bonus visible 192-255

Studio2BeepTimer = $CD 										; Studio 2 Beep Counter

;
; 	Working copy of the maze data in first 60 bytes. Must be at zero, game requires this.
;
MazeData = 0 												
;
;	These data allocations should be moved very carefully as some code relies on them being arranged in this order.
;
Lives = $40 												; Number of remaining lives
Level = $41 												; Current Level
RandomSeed = $42 											; Random Seed Value (2 bytes)
EatCounter = $44 											; Number of pills to eat remaining in this level.
Score = $46 												; Score (6 digits, most significant first)
Frame = $4C 												; Frame count.
Keyboard = $4D 												; Last read keyboard state.

;
;	These are zeroed at the start of each level. These variables must go $10 bytes before the sprite storage
;
LostLife = $50 												; set to non-zero when life lost.
GhostCaughtCounter = $51 									; score for next ghost caught (in 100s)
ChasingTimer = $52 											; decrements to zero - if non-zero ghosts are under attack.
BonusFrameCounter = $53 									; tracks bonus frames.
Death = $54 												; set to non-zero when died (e.g. ghost collision)
Outstanding100Points = $55 									; the number of outstanding units of 100 points to be added to the score
;
;	These are the six sprites : Player (0) Ghosts (1-4) Bonus (5) all of which are 16 bytes ong
;
;	Note : moving these forward may cause problems due to the S2s $8CD-$8CF timers altering data :(
;
SpriteStorage = $60 										; Sprites are stored from $60-$C0 (there are 6 of them)
SpriteRecordSize = 16 										; 16 bytes per sprite record
SpriteCount = 6 											; Six sprites
SpriteStorageEnd = SpriteStorage + (SpriteRecordSize*SpriteCount)

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
;														Pacman Maze Data
;
;	A 10x6 array of bytes (each pacman square is 6 x 5 pixels) for each square, as follows:
;
;	Bit 0:	Wall Present up
;	Bit 1:  Wall Present left
;	Bit 2: 	Wall Present right
;	Bit 3:	Wall Present down
;	Bit 4:  True if offset n is divisible by 5
;	Bit 5:  True if offset n is divisible by 6
;	Bit 6:	True if Power-pill here
;	Bit 7: 	(Altered by program) true if power pill or dot present on board.
;
; ***************************************************************************************************************************************

LevelData:
		.include "mapbytes.inc"
LevelDataEnd:

; ***************************************************************************************************************************************
;
;														Graphics all 5 x 4 bit.
;	
; ***************************************************************************************************************************************

	align 	4 												; put graphic on a four byte boundary.

Graphics:

Pellet:
		.db 	$00,$20,$00,$00
PowerPill:
		.db 	$00,$70,$70,$00
PacmanClosed:
		.db 	$70,$F8,$F8,$70
PacmanUp:	
		.db 	$50,$F8,$F8,$70
PacmanDown:
		.db 	$70,$F8,$F8,$50
PacmanLeft:
		.db 	$70,$38,$38,$70
PacmanRight:
		.db 	$70,$E0,$E0,$70
Ghost1:
		.db 	$70,$A8,$F8,$50
Ghost2:
		.db 	$70,$A8,$F8,$A8
GhostReverse:
		.db 	$70,$88,$88,$50
Cherry:
		.db 	$40,$20,$D8,$D8
Blank:
		.db 	$00,$00,$00,$00

		.db 	0,0,0,0 									; spare - removing it causes page boundary problems.

; ***************************************************************************************************************************************
;
;		 Shift/XOR Drawer for 5 bit x 1 line of graphics. There are 8 entry points each representing one pixel shift, 2 bytes apart
;
;	On Entry, 	D 		contains the bits to shift, undefined on exit.
;			  	RF 		points to the first byte of the two to Xor (should remain unchanged)
;				RE.L	is undefined on entry and exit
;				RE.H 	is undefined on entry and exit.
;
;	This is the only third level subroutine. It's run pointer doesn't matter, but it returns to R5
;	Note:  you cannot 'loop' subroutine this because you don't know what the entry point was - there are 8 entries and 2 exits :)
;
; ***************************************************************************************************************************************

ShiftXORDrawerBase:
		br 		SXD0 										; Shift 0 bits right
		br 		SXD1 										; Shift 1 right (etc.)
		br 		SXD2
		br 		SXD3 										; up to here, only requires one byte
		br 		SXD4 										; shift 4-5 => 3 Shift Rights, then 1-2 16 bit shift rights
		br 		SXD5
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
		sep 	r5 											; there are 2 exit points

SXD4: 														; shift right x 4
		shr
		shr
		shr
		phi 	re 											; RE now contains 16 bit graphic
		ldi 	0
		plo 	re
		br 		SXD4_2 

SXD5: 														; shift right x 5
		shr
		shr
		shr
		phi 	re 											; RE now contains 16 bit graphic
		ldi 	0 
		plo 	re
SXD5_2:
		ghi 	re 											; shift RE right once, 16 bits.
		shr
		phi 	re
		glo 	re
		shrc
		plo 	re

SXD4_2:
		ghi 	re 											; shift RE right once, 16 bits.
		shr
		phi 	re
		glo 	re
		shrc
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
		sep 	r5 											; Note, 2 exit points.

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
		bn3 	SKBSkip
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
;
;														Sprite Plotting Routine
;
; 	Second Level, returns to r4, runs under R5.
;	Breaks: RE (xordrawer), RF (position), RB.1, RC but RD is unchanged, so is D.
;	On entry: RD.0 = x, RD.1 = y, D = Graphic LSB. Position (0,0) puts the sprite in the top left corner of the board e.g. (1,1) on the
; 	screen
;
;	SpriteLoadAndPlot loads RD.0,RD.1 and D with [RA],[RA+1],[RA+2]
;
;	Testing : did 3 x 10240 plot/erases in 23s (about 133 per second)
; ***************************************************************************************************************************************

		.db 	0,0,0 										; padding - required for branches

SpriteLoadAndPlot:											; this loads the plot data from RA then fixes RA.
		lda 	ra
		plo 	rd 											; first byte in RD.0 (X)
		lda 	ra
		phi 	rd 											; second byte in RD.1 (Y)
		ldn 	ra 											; third byte in D (graphic)

		dec 	ra 											; fix R3
		dec 	ra

SpritePlot:
		bz 		SPRP_NoPlot 								; if graphic is zero then do nothing at all
		dec 	r2 											; save the graphic address on the stack
		str 	r2
		glo 	rd 											; range check
		adi 	-55
		bdf 	SPRP_Exit
		ghi 	rd
		adi 	-26
		bdf 	SPRP_Exit

		glo 	rd 											; calculate the position. We add 1 because the top left pixel (0,0) is at (1,1) physically
		adi 	1 			
		ani 	7 											; this is the shift amount we need to use.
		shl 												; multiply by 2
		adi 	<ShiftXORDrawerBase 						; now the LSB of the routine we need to call to shift.
		phi 	rb 											; save in RB.1, which is not used by the interrupt routine.

		glo 	rd 											; get the X position, again
		adi 	1 											; add the (1,1) fix
		shr
		shr
		shr 												; now a byte offset
		dec 	r2 											; save at TOS
		str 	r2
		ghi 	rd 											; get the Y offset
		shl 												; multiply by 8
		shl
		shl
		sex 	r2 											; add the byte offset to it.
		add 
		inc 	r2 											; fix the stack back.
		adi 	8 											; again, the fix needed because (0,0) is (1,1) this fixes vertically.
		plo 	rf 											; make RF point to the screen
		ldi 	VideoPage
		phi 	rf

SPRP_Loop:
		ghi 	rb 											; put the routine address in RC. RB.1 was its LSB
		plo 	rc
		ldi 	>ShiftXORDrawerBase							; its MSB is a constant.
		phi 	rc

		ldn 	r2 											; read the graphic address into RE.
		plo 	re
		ldi 	>Graphics 								
		phi 	re
		ldn 	re 											; read the graphic byte from RE

		sep 	rc 											; call the XOR plotter.

		glo 	rf 											; move RF to next line down
		adi 	8
		plo 	rf

		ldn 	r2 											; point to next graphics line.
		adi 	1
		str 	r2
		ani 	3 											; graphics are aligned on address 4, so when this is zero we have drawn it.
		bnz		SPRP_Loop

SPRP_Exit:
		ldn 	r2 											; restore D
		inc 	r2 											; fix up the stack.
SPRP_NoPlot:
		sep 	r4 											; and return.
		br  	SpritePlot 

; ***************************************************************************************************************************************
;
;														Level Initialisation
;
; (1) Copy Map Data into first 60 bytes of memory, setting the 'power pill' bit.
; (2) Clear the screen
; (3) Scan the map drawing upper and left walls as required
; (4) Draw the bottom line (not covered by 3)
; (5) Draw the right line (not covered by 3)
; (6) Draw the 'lives' on the far right in the 3 pixels unused
; (7) Fix the 'den' in the RAM Map so Pacmen can leave but no-one can enter
; (8) Draw all the dots and power pills
; (9) Reset the 'dots to eat' counter.
; (10) Initialise the Game Object Area
;
; ***************************************************************************************************************************************

InitialiseLevel:
		ghi 	r2 											; point RD,RF to mazedata copy area in RAM
		phi 	rf
		phi 	rd
		ldi 	MazeData
		plo 	rf
		plo 	rd
		ldi 	>LevelData 									; point RE to the original copy.
		phi 	re
		ldi 	<LevelData
		plo 	re
IL_CopyMazeData:
		lda 	re 											; read from original and bump RE
		str 	rf 											; save in maze RAM
		inc 	rf 											; bump RF
		glo 	re 											; reached the end of maze data
		xri 	<LevelDataEnd
		bnz 	IL_CopyMazeData

		plo 	re 											; set RE,RF = Video RAM Pointer
		plo 	rf
		ldi 	VideoPage
		phi 	re
		phi 	rf
IL_ClearScreen: 			
		glo 	rf 											; clear the screen (RF.0 = 0, RF.1 = $09)
		str 	re
		inc 	re
		glo 	re
		bnz 	IL_ClearScreen

IL_DrawCellResetMask:
															; RD points to maze data. RF points to video RAM.
		ldi 	$80 										; set mask in RE.1 - so VRAM | BIT is the current pixel.
		phi 	re

IL_DrawCell:
		ldn 	rd 											; read maze data entry
		ani 	$02 										; is there a left wall ?
		bz 		IL_NoLeftWall

		ldi 	5 											; draw 5 lines down.
		plo 	re 											; re.0 is the counter
IL_DrawLeftWall:
		sex 	rf 											; set the bit in [RF] e.g. video RAM
		ghi 	re 											; read the mask
		or 													; or into VRAM.
		str 	rf
		glo 	rf 											; down one line.
		adi 	8
		plo 	rf
		dec 	re 											; decrement counter
		glo 	re
		bnz 	IL_DrawLeftWall 							; do 6 vertical wall elements.
		glo 	rf 											; fix RF back
		smi 	40
		plo 	rf 											; back where it started.
IL_NoLeftWall:
		lda 	rd 											; read maze data entry again, bump the pointer
		ani 	1 											; now 1 if wall, 0 if clear.
		bz 		IL_MaskZero 
		ldi 	$FF 							
IL_MaskZero:												; now $FF if wall, $00 if clear
		dec 	r2 											; store the mask on the stack
		str 	r2
		ldi 	6 											; set the counter (RE.0) to 6 (number to draw)
		plo 	re 	
IL_UpperWall:
		sex 	r2 
		ghi 	re 											; get mask.
		and 												; and with mask on stack so set or clear.
		sex 	rf
		or  												; or into screen
		str 	rf
		ghi 	re 											; read mask
		shr 												; shift right
		bnf 	IL_NotNext 									; if DF zero, not shifted bit into it.
		shrc 												; shift it back into bit 7
		inc 	rf 											; next byte
IL_NotNext:
		phi 	re 											; store mask back in RE.1
		dec 	re 											; do it 'upperwall' times.
		glo 	re
		bnz 	IL_UpperWall

		ghi 	re 											; draw the last one always.
		sex 	rf
		or
		str 	rf

		inc 	r2 											; fix stack back.
		glo 	rf 											; reached the right hand byte ?
		ani 	7
		xri 	7
		bnz 	IL_DrawCell 								; keep going until row complete.
		glo 	rf 											; look at lower byte.
		adi 	1+4*8 										; shift right one and down by 4 rows.
		plo 	rf
		adi 	16
		bnf 	IL_DrawCellResetMask						; not finished draw with reinitialised mask.

		ldi 	$F0 										; fill in the bottom line.
		plo 	rf
IL_BottomRow:
		ldi 	$FF
		str 	rf
		inc 	rf
		glo 	rf
		ani		7
		bnz		IL_BottomRow
		dec 	rf 											; refix the last row.
		ldi 	$F8
		str 	rf

		ldi 	$00 										; point RF to the top line.
		plo 	rf
IL_RightSide:
		ldn 	rf 											; read the right side
		shl  												; put bit 7 (e.g. the leftmost bit) into DF
		glo 	rf 											; move to right side same line.
		ori 	7
		plo 	rf
		bnf 	IL_NoSetRight	 							; nothing on the right
		ldn 	rf
		ori 	8
		str 	rf
IL_NoSetRight:
		inc 	rf 											; now first on next row.
		glo 	rf
		bnz 	IL_RightSide
		dec 	rf 											; rf now pointing to VRAM again.

		ldi 	Lives 										; RD now points to lives
		plo 	rd
		ldn 	rd
		bz 		IL_NoLives 									; if zero, no lives.
		plo 	re 											; store lives in RE.0
		ldi 	$0F 										; RF where first life is going
		plo 	rf

IL_DrawLifeMarkers:
		ldn 	rf 											; draw life marker.
		ori 	2
		str 	rf
		glo 	rf
		adi 	8
		plo 	rf
		ldn 	rf
		ori 	1
		str 	rf
		glo 	rf
		adi 	16
		plo 	rf

		dec 	re
		glo 	re
		bnz 	IL_DrawLifeMarkers
IL_NoLives:

		ldi 	34 											; RD now points to the first 'den'
		plo 	rd
		ldn 	rd 											; clear up bits on 34,35 (the pacman den)
		ani 	$FE 		 								; so the Pacmen can move up through there
		str 	rd 											; but it's not possible to move back down.
		inc 	rd
		ldn 	rd
		ani 	$FE 		
		str 	rd

		ldi 	0 											; set RD.0,RD.1 to zero (0,0)
		phi 	rd
		plo 	rd
		ghi 	r2 											; make RA point to the Map in RAM
		phi 	ra
		ldi 	<MazeData
		plo 	ra

		ldi 	>SpritePlot 								; set R5 to the sprite plotter
		phi 	r5
		ldi 	<SpritePlot
		plo 	r5

IL_DrawPills:
		lda 	ra 											; read from the maze, advance maze pointer
		shl
		bnf 	IL_NoPill									; if bit 7 clear , no pill here.
		shl 												; powerpill flag in DF.
		ldi 	<Pellet
		bnf 	IL_IsPellet
		ldi 	<PowerPill
IL_IsPellet:
		sep 	r5
IL_NoPill:
		glo 	rd
		adi 	6
		plo 	rd
		xri 	60
		bnz 	IL_DrawPills
		plo 	rd
		ghi 	rd
		adi 	5
		phi 	rd
		xri 	30
		bnz 	IL_DrawPills

		ldi 	<EatCounter 								; set RA to point to eat counter - RA.1 points to RAM page
		plo 	ra
		ldi 	60-2-2 										; 6 x 10 maze, -2 for the den, -2 for the start squares.
		str 	ra

		ldi 	<SpriteStorage-$10							; set RA to point to Sprite Storage/Flags and clear it out.
		plo 	ra
IL_ClearSpriteStorage:
		ldi 	$00
		str 	ra
		inc 	ra
		glo 	ra
		xri 	<SpriteStorageEnd
		bnz 	IL_ClearSpriteStorage

		ldi 	<SpriteStorage 								; point RA to the sprite storage
		plo 	ra

		ldi 	>InitialiseObject 							; point R5 to the Initialise Object Routine
		phi 	r5
		ldi 	<InitialiseObject
		plo 	r5

		ldi 	<PlayerInitialiseData 						; do one player
		sep 	r5
		ldi 	<GhostInitialiseData 						; four ghosts
		sep 	r5
		sep 	r5
		sep 	r5
		sep 	r5
		ldi 	<BonusInitialiseData 						; and one bonus
		sep 	r5

		sep 	r3 											; and initialisation is STILL not over.

; ***************************************************************************************************************************************
;
;			Initialise object from data (LSB in D) to RA. Preserve D on exit. RA on exit should point to the next sprite.
;
;	Runs in R5, returns to R4. Breaks D,RE,RD
;
; ***************************************************************************************************************************************

InitialiseObject:
 		plo 	rd 											; save pointer in RD.0 and RE.0
 		plo 	re
 		ldi 	>PlayerInitialiseData 						; make RE point to initialisation data
 		phi 	re
 		sex 	re 											; use RE as index register
 		ldxa 												; copy 3 bytes in directly.
 		str 	ra 											; +0 (x)
 		inc 	ra

 		ldxa 												; +1 (y)
 		str 	ra
 		inc 	ra

 		inc 	ra 											; shift ra to +5
 		inc 	ra
 		inc 	ra

IOB_Copy:
 		ldxa  												; copy in the call vectors
 		str 	ra
 		inc 	ra
 		glo 	ra
 		ani 	15
 		xri 	11 											; up to 11 where hey stop
 		bnz		IOB_Copy

 		glo 	ra 											; advance RA pointer to end of record
 		adi 	SpriteRecordSize-11
 		plo 	ra

 		glo 	rd 											; recover old D value from RD.0 and return.
		sep 	r4
		br 		InitialiseObject

; ***************************************************************************************************************************************
;
;													Move the Sprite pointed to by RA
;
;	First level subroutine, runs in R4, returns to R3, preserves RA.
;
;	(1) Checks what legal moves are possible from the current position
;	(2) Erase the current sprite
;	(3) Call routine to get new sprite movement requested.
; 	(4) And with legal moves
;	(5) If zero try the previous move instead, this too anded with legal moves.
;	(6) Adjust the sprite position with the results of 4 and 5.
;	(7) If collision with Player sprite Call routine to handle collisions.
;	(8) Call routine to get the new sprite.
;	(9) Redraw sprite in new position
;	
; ***************************************************************************************************************************************

MoveSprite:

; ---------------------------------------------------------------------------------------------------------------------------------------
;												  Update the legal moves record entry
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>UpdateLegalMoves 							; Call the update legal moves routine.
		phi 	r5
		ldi 	<UpdateLegalMoves
		plo 	r5
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;														Erase the current sprite
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>SpriteLoadAndPlot 							; erase sprite
		phi 	r5
		ldi 	<SpriteLoadAndPlot
		plo 	r5
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;					 Call vector to get new sprite movement (8,4,2,1 format), and with legal move mask and store
; ---------------------------------------------------------------------------------------------------------------------------------------
		glo 	ra 											; RC = RA + 7 (address of movement reading code.)
		adi 	7
		plo 	rc
		ghi 	ra
		phi 	rc
		lda 	rc 											; Copy Call Address into R5
		phi 	r5
		lda 	rc
		plo 	r5
		sep 	r5 											; call the function to read it into D.
		ani		$0F 										; only interested in lower 4 bits.

		inc 	ra 											; move to RA+4 which is the mask for allowable moves
		inc 	ra
		inc 	ra
		inc 	ra
		sex 	ra 											; and the allowable mask with the required mask.
		and
		bnz 	MSP_MoveOkay  								; if legal move save in slot.

; ---------------------------------------------------------------------------------------------------------------------------------------
;									If move is zero, i.e. not possible retry the last move.
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldn 	ra 											; no move - get LAST move
		dec 	ra 											; and with legal move
		and
		inc 	ra 											; then save that

MSP_MoveOkay:
		dec 	ra
		str 	ra

; ---------------------------------------------------------------------------------------------------------------------------------------
;												Adjust the sprite coordinates
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>SpriteShift 								; make R5 point to the code that actually adjusts positions.
		phi 	r5
		ldi 	<SpriteShift
		plo 	r5

		ldn 	ra 											; reload the actual move back into D
		dec 	ra 											; fix up so RA is pointing back where it should be (start of record)
		dec 	ra
		dec 	ra
		sep 	r5

; ---------------------------------------------------------------------------------------------------------------------------------------
;											Check for collisions with sprite 0 (player sprite)
; ---------------------------------------------------------------------------------------------------------------------------------------

		glo 	ra 											; check if the first sprite e.g. the player
		xri 	SpriteStorage
		bz 		MSP_NotFirst 								; if it is then collision checks are somewhat pointless.

		ghi 	r2 											; point RD to sprite 0.
		phi 	rd
		ldi 	SpriteStorage
		plo 	rd

		sex 	ra 											; calculate |P0.x - P.x|
		lda 	rd
		sm
		bdf 	MSP_NoSign1
		sdi 	0
MSP_NoSign1:
		dec 	r2 											; save on stack
		str 	r2

		ldn 	rd 											; calculate |P0.y-P.y|
		inc 	ra
		sm
		dec 	ra
		bdf 	MSP_NoSign2
		sdi 	0
MSP_NoSign2:
		sex 	r2 											; add to TOS, this is the absolute distance.
		add
		inc 	r2 											; fix up stack.

		smi 	4 											; collision if total distance < 4
		bdf 	MSP_NotFirst

		glo 	ra 											; RC = RA + 9 (address of collision handling code.)
		adi 	9
		plo 	rc
		ghi 	ra
		phi 	rc
		lda 	rc 											; Copy Call Address into R5
		phi 	r5
		lda 	rc
		plo 	r5
		sep 	r5 											; call the function to read it into D.

MSP_NotFirst:

; ---------------------------------------------------------------------------------------------------------------------------------------
;													Call vector to get new sprite graphic
; ---------------------------------------------------------------------------------------------------------------------------------------
		glo 	ra 											; RC = RA + 5 (address of sprite reading code.)
		adi 	5
		plo 	rc
		ghi 	ra
		phi 	rc
		lda 	rc 											; Copy Call Address into R5
		phi 	r5
		lda 	rc
		plo 	r5
		sep 	r5 											; call the function to read it into D.
		inc 	ra 											; store it in RA[2] which is the drawing sprite.
		inc 	ra
		str 	ra
		dec 	ra 				
		dec  	ra

; ---------------------------------------------------------------------------------------------------------------------------------------
; 																Redraw the sprite
; ---------------------------------------------------------------------------------------------------------------------------------------

		ldi 	>SpriteLoadAndPlot 							; redraw sprite
		phi 	r5
		ldi 	<SpriteLoadAndPlot
		plo 	r5
		sep 	r5

		sep 	r3

; ***************************************************************************************************************************************
;
;	Update the "legal moves" element of the sprite record (RA). If at a "junction" store the index and old position in the record.
;
;	Second level, runs in R5. Breaks RD,RE,RF
;
; ***************************************************************************************************************************************

UpdateLegalMoves:
		ldi 	0 											; RE.0 is the return value
		plo 	re
		ldn 	ra 											; read x position
		plo 	rd 											; point RD to the map table
		ghi 	r2 									
		phi 	rd
		ldn 	rd 											; read the entry in the lookup table.
		ani 	$20 										; if divisible by 6 bit 5 is set
		bnz 	ULM_MoveVertical 							; if it is, we can move vertically
		glo 	re
		ori 	$02+$04  									; if not, it must be horizontal move (or I've cocked up)
		plo 	re 											; so set bits 1 and 2 (left and right)
		br 		ULM_Exit 									; and we can't be on a wall.

ULM_MoveVertical:
		glo 	re 											; if moving vertical is okay (X % 6 == 0) set bits 0,3
		ori 	$01+$08 									; (up and down)
		plo 	re

		inc 	ra 											; get the Y position
		ldn 	ra
		dec  	ra
		plo 	rf 											; save in RF.0 for later.
		plo 	rd 											; point it into the map table.
		ldn 	rd 											; read that
		ani 	$10 										; this bit set if divisible by 5.
		bz 		ULM_Exit 									; exit if not - if x % 6 == 0 and y % 5 == 0 we are at a junction point.

		glo 	rf 											; read RF which is the Y position
		shl 												; now Y is Y / 5 * 10 - we know Y/5 is a whole number
		plo 	rd 											; RD points to MAP[Y*10]
		ldn 	ra 											; read the X position
ULM_Divide:
		bz 		ULM_DivideEnd 								; reached 0, RD now points to MAP[X+Y*10] where X and Y are cell numbers.
		inc 	rd
		adi 	-6
		br 		ULM_Divide
ULM_DivideEnd:
		ldn 	rd 											; read that cell - tells us what moves are legal here - this returns bit set for walls
		ani 	$0F 										; isolate wall bits
		xri 	$0F 										; toggle wall bits to open bits.
		ori 	$80  										; set bit 7, which marks it as a 'junction' point
		plo 	re 											; that is the returned value.

		ghi 	r2 											; point R2 to RA+11 - the cell index number
		phi 	rf
		glo 	ra
		adi 	11
		plo 	rf
		glo 	rd 											; retrieve the index number and write it.
		str 	rf

		ghi 	r2 											; make RD point to the current position
		phi 	rd
		glo 	ra
		plo 	rd

		lda 	rd 											; copy X,Y to RA+12,RA+13
		inc 	rf
		str 	rf
		lda 	rd
		inc 	rf
		str 	rf

ULM_Exit:
		glo 	ra 											; RD points to legal moves entry.
		adi 	4
		plo 	rd
		glo 	re 											; copy legal moves into that record entry
		str 	rd 			
		sep 	r4 											; and exit.

; ***************************************************************************************************************************************
;
;											Shift the sprite ^RA by D (D is 8421 format)
;
;	Runs in R5 returns to R4. Breaks nothing.
;
; ***************************************************************************************************************************************

SpriteShift:
		sex 	ra
		ani 	$0F 										; only interested in four lsb
		bz 		SSH_Exit 									; no move.
		shr
		bdf 	SSH_Up
		shr 	
		bdf 	SSH_Left
		shr
		bdf 	SSH_Right
		shr
		bdf 	SSH_Down
		br 		SSH_Exit

SSH_Left:													; move left
		ldi 	-1
		br 		SSH_AddHorizontal

SSH_Right:													; move right
		ldi 	1
SSH_AddHorizontal:
		add
		ani 	63 											; force into HV range 0-63
		str 	ra
		br 		SSH_Exit

SSH_Up: 													; move up
		inc 	ra
		ldi 	-1
		br 		SSH_AddVertical

SSH_Down:
		inc 	ra  										; move down.
		ldi 	1
SSH_AddVertical
		add
		stxd
SSH_Exit:
		sep 	r4


; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;														Player Routines
;
;	Run in R5, Return to R4, Must preserve RA.
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

PlayerSprite_GetSprite:
		lda 	ra 											; calculate P.x + P.y
		sex 	ra
		add
		ani 	4 											; use this to determine open/closed
		bnz 	PSGS_1
		dec 	ra 											; fix RA and return closed
		ldi 	<PacmanClosed
		sep 	r4

PSGS_1:	inc 	ra 				 							; point to direction.
		inc 	ra
		ldn 	ra 											; read actual movement.
		dec 	ra 											; fix RA back
		dec 	ra
		dec 	ra

		shr 												; dispatch dependent on actual movement
		bdf 	PSGS_Up
		shr
		bdf 	PSGS_Left
		shr
		bdf 	PSGS_Right
		shr
		bdf 	PSGS_Down

PSGS_Right: 												; right graphic
		ldi 	<PacmanRight
		sep 	r4

PSGS_Up: 													; up graphic
		ldi	 	<PacmanUp
		sep 	r4
 
PSGS_Left: 													; left graphic
		ldi	 	<PacmanLeft
		sep 	r4

PSGS_Down: 													; down graphic
		ldi	 	<PacmanDown
		sep 	r4

PlayerSprite_GetMovement:
		ghi 	r2 											; Point RF to last keypad entry
		phi 	rf
		ldi 	Keyboard
		plo 	rf
		ldn 	rf 	 										; read it
		ani		$0F 										; only the bottom four bits matter
		sep 	r4

; ***************************************************************************************************************************************
;
;										Check for player collision with power pills or pellets
;
; 	Top Subroutine: Runs in R4 Returns to R3.
;
; ***************************************************************************************************************************************

CheckPlayerEat:
		ghi 	r2 											; point RE to the legal player movements for the player
		phi 	re
		ldi 	SpriteStorage+4 						
		plo 	re
		ldn 	re 											; read it, shift bit 7 (set at junction) into DF
		shl
		bnf 	CPE_Exit 									; if not at junction then exit.

		ldi 	SpriteStorage+11 							; read the cell number which is set at junctions.
		plo 	re
		ldn 	re
		plo 	re 											; RE now points to the cell data
		ldn 	re 											; read it, save in RB.1 and examine bit 7.
		phi 	rb 											; shifting it into the DF.
		shl 		
		bnf 	CPE_Exit 									; if already eaten (DF == 0) then skip

		ldn 	re 											; clear bit 7 indicating eaten
		ani 	$7F
		str 	re

		ldi 	EatCounter 									; decrement the 'eat' counter
		plo 	re 											; when this is zero the level is completed.
		ldn 	re
		smi 	1
		str 	re

		ldi 	5 											; short beep on R7
		str 	r7

		ghi 	rb 											; restore the maze cell entry from RB.1
		shl 												; put powerpill flag (bit 6) in DF
		shl 
		ldi 	1 											; add 1 tens (e.g. 10 points per pellet) 								
		bnf 	CPE_AddTensToScore

		ldi 	ChasingTimer 								; Eaten a power pill : point RD to the chasing counter 
		plo 	re
		ldi 	FramesPerChasingTimer 						; and set the chasing timer to non-zero.
		str 	re
		dec 	re 											; point RE to the Score for next caught ghost counter

		ldi 	1 											; initialise this to 1 (representing 100 points)
		str 	re 											; doubled every time a ghost is caught (200,400,800 points)

		ldi 	5 											; add 5 tens (e.g. 50 points per powerpellet)

CPE_AddTensToScore:
		plo 	rd 											; save tens to RD.0
		ldi 	>AddScore 									; make R5 point to AddScore routine
		phi 	r5
		ldi 	<AddScore
		plo 	r5
		glo 	rd 											; restore tens from RD.0
		sep 	r5 											; add to score

		ldi 	SpriteStorage+12							; point RE to player sprite old position, same position as the pill - set up on junctions.
		plo 	re 				
		lda 	re 											; read X into RD.0 - this is where the pill/pellet is drawn.
		plo 	rd
		ldn 	re 											; read Y into RD.1
		phi 	rd

		ldi 	>SpritePlot 								; set R5 to sprite plotter
		phi 	r5
		ldi 	<SpritePlot
		plo 	r5

		ghi 	rb 											; get the cell data from RB.1
		shl 												; shift bit 6 into DF (bit 6 indicates power pill)
		shl
		ldi 	<Pellet 									; select graphic dependent on DF (e.g. bit 6)
		bnf 	CPE_IsPellet
		ldi 	<PowerPill
CPE_IsPellet:
		sep 	r5 											; erase the pill from the display.

CPE_Exit: 													; exit
		sep 	r3

; ***************************************************************************************************************************************
;
;											Dummy Vector Methods used for testing
;
; ***************************************************************************************************************************************

NoSMethod: 													; Dummy get-sprite-visual returns cherry
		ldi 	<Cherry
NoCMethod: 													; Dummy collision ignored
		sep 	r4
NoMMethod: 													; Dummy movement non-existent
		ldi 	0
		sep 	r4

; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
; 														ROM BOUNDARY HERE
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

		.org 	$C00 										; S2 ROM can be anywhere except $000-$3FF and $800-$9FF
															; (it can be at $800-$9FF but then there'll be no RAM !!!!!)

; ***************************************************************************************************************************************
;
;											Initialisation data for Game Objects
;
;	For each type : initial position (2 bytes), Sprite vector, MoveGet vector, Collision vector
;
; ***************************************************************************************************************************************

PlayerInitialiseData:
		db 		4*6+5,5*5
		dw 		PlayerSprite_GetSprite,PlayerSprite_GetMovement,NoCMethod

GhostInitialiseData:
		db 		4*6,3*5
		dw 		Ghost_GetSprite,Ghost_GetMovement,Ghost_CollidePlayer

BonusInitialiseData:
		db 		4*6+3,2*5
		dw 		Bonus_GetSprite,NoMMethod,Bonus_CollidePlayer

; ***************************************************************************************************************************************
;
;													Add D x 10 to Score
;
;	Second Level : Runs in R5 return to R4. Breaks RE,RF
;
; ***************************************************************************************************************************************

AddScore:
		plo 	re 											; save score to add to RE.0
		ghi 	r2 											; set RF equal to Score+4
		phi 	rf 											; not +5 , that is the LSD and is always zero.
		ldi 	Score+4
		plo 	rf
ASC_Loop:
		glo 	re 											; add score to [RF]
		sex 	rf
		add 	
		str 	rf
		smi 	10 											; is it >= 10
		bnf 	ASC_Exit
		stxd 												; so deduct 10 and wrap round to previous
		ldi 	1 											; add 1 to the next one.
		plo 	re
		br 		ASC_Loop  									; this will probably crash if you score > 999,990 which is unlikely.
ASC_Exit:
		sep 	r4

; ***************************************************************************************************************************************
;
;											Add outstanding units of 100 points to the score
;
;	Runs in R4, returns to R3
;
;	(necessary because of the different depth issue of 1802 SEP routines)
; ***************************************************************************************************************************************

FixupOutstanding:
		ghi 	r2 											; point R2 to the outstanding counter
		phi 	rd
		ldi 	Outstanding100Points
		plo 	rd
		ldn 	rd 											; read it
		bz 		FXO_Exit 									; exit if zero
		smi 	1 											; decrement it.
		str 	rd

		ldi 	>AddScore 									; set R5 to add score routine
		phi 	r5
		ldi 	<AddScore
		plo 	r5
		ldi 	10 											; add ten tens.
		sep 	r5
		br 		FixupOutstanding 							; and keep going.
FXO_Exit:
		sep 	r3

; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;															Bonus Routines
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

Bonus_GetSprite:
		ghi 	r2 											; point RD to the bonus frame counter
		phi 	rd
		ldi 	BonusFrameCounter 							; read it
		plo 	rd
		ldn 	rd 											; display cherry if in range 192..255
		smi 	BonusRate
		bnf		BGS_Blank
		ldi 	<Cherry
		sep 	r4
BGS_Blank: 													; otherwise display nothing.
		ldi 	0
		sep 	r4

Bonus_CollidePlayer:
		ghi 	r2 											; point RD to the bonus frame counter
		phi 	rd
		ldi 	BonusFrameCounter 							; read it
		plo 	rd
		ldn 	rd 											; display cherry if in range 192..255
		smi 	BonusRate
		bnf		BCS_Exit
		ldi 	0 											; reset the bonus frame counter
		str 	rd
		ldi 	Outstanding100Points 						; add 5 to the outstanding points counter
		plo 	rd
		ldn 	rd
		adi 	5
		str 	rd
		ldi 	20 											; longer beep
		str 	r7
BCS_Exit:
		sep 	r4


; ***************************************************************************************************************************************
; ***************************************************************************************************************************************
;
;														Ghost Routines
;
; ***************************************************************************************************************************************
; ***************************************************************************************************************************************

Ghost_GetSprite: 						
		lda 	ra 											; calculate X+Y
		sex 	ra
		add
		dec 	ra
		ani 	1 											; look at bit 0
		bz 		GGS_Alternate 								; if set display Ghost1
		ldi 	<Ghost1
		sep 	r4
GGS_Alternate: 												; display Ghost2 or GhostReverse
		ghi 	r2 
		phi 	rd 											; point RD to chasing timer
		ldi 	ChasingTimer
		plo 	rd
		ldn 	rd 											; read it
		bnz		GGS_Chasing 								; if non-zero display GhostReverse
		ldi 	<Ghost2
		sep 	r4
GGS_Chasing:
		ldi 	<GhostReverse
		sep 	r4

; =========================================================================================================================================

Ghost_GetMovement:
		ldi 	ChasingTimer 								; point RD to chasing timer and read it
		plo 	rd
		ghi 	ra
		phi 	rd
		ldn 	rd
		phi 	rb 											; save in RB.1

		glo 	ra 											; point RD to legal moves RA+4
		adi 	4
		plo 	rd
		ldn 	rd 											; read it, put junction bit (7) into DF
		shl
		bnf 	GGM_Exit 									; only move at junctions

		glo 	ra 											; read RA[11] which is the cell number
		adi 	11
		plo 	rd
		ldn 	rd 		
		ani 	$FE 										; check 34 or 35 (drop bit 0)
		xri 	34
		bnz 	GGM_NotInPen

		ghi 	rb 											; read chasing timer saved in RB.1
		bz 		GGM_NotInPen 								; if timer = 0 then can escape the pen.

		glo 	ra 											; set RA[3] (last move) to zero.
		adi 	3
		plo 	rd
		ldi 	0 
		str  	rd
		sep 	r4 											; and also return zero - not moving.

GGM_NotInPen:
		ldi 	>Random 									; point RC to random
		phi 	rc
		ldi 	<Random
		plo 	rc

		sep 	rc 											; one time in 3 move randomly.
		ani 	3
		bz 		GGM_RandomMove

		sep 	rc 											; generate a random number
		shl 												; put MSB into DF
		bdf 	GGM_Horizontal

															; vertical move
		ldi 	SpriteStorage+1 							; read Player 1.Y
		plo 	rd
		ldn 	rd															
		inc 	ra 											; subtract Ghost.Y
		sex 	ra
		sm
		dec 	ra
		bz 		GGM_Same
		ldi 	1
		bnf 	GGM_Vertical1
		ldi 	9
GGM_Vertical1:
		plo 	rd
		ldi 	9^1
		phi 	rd
		br 		GGM_CheckInvert

GGM_Horizontal:												; horizontal move
		ldi 	SpriteStorage 								; read Player1.X
		plo 	rd
		ldn 	rd
		sex 	ra 											; subtract Ghost.X
		sm 															
		bz 		GGM_Same
		ldi 	2
		bnf 	GGM_Horizontal1
		ldi 	4
GGM_Horizontal1:
		plo 	rd
		ldi		2^4
		phi 	rd

GGM_CheckInvert: 											; RD.0 is movement, xor with RD.1 if being chased.
		ghi 	rb 											; check chasing timer.
		bz 		GGM_NotChasing

		dec 	r2 											; return RD.0 ^ RD.1
		ghi 	rd
		str 	r2
		sex 	r2
		glo 	rd
		xor
		inc 	r2
		sep 	r4

GGM_NotChasing:												; not chasing, return RD.
		glo 	rd
		sep 	r4

GGM_Same: 													; same, move randomly.

GGM_RandomMove:												; make a completely random move.
		sep 	rc 											; call random number generator
		ani 	3 											; 0,1,2,3
		xri 	2 											; 2,3,0,1
		bnz 	GGM1
		xri 	7^2											; 2,3,5,1
GGM1:	xri 	2 											; 0,1,7,3
		adi 	1 											; 1,2,8,4
		sep 	r4

GGM_Exit: 													; return continuation.
		ldi 	0
		sep 	r4

Ghost_CollidePlayer:
		ghi 	r2 											; point RD to chasing timer.
		phi 	rd
		ldi 	ChasingTimer
		plo 	rd
		ldn 	rd 											; read it
		bnz 	GCP_EatenGhost 								; if non-zero ghost is eaten

		ldi 	LostLife 									; set the 'lost life' flag to non zero
		plo 	rd
		str 	rd
		sep 	r4

GCP_EatenGhost:
		ldi 	4*6 										; move ghost to cell (4,3) in the 'home'
		str 	ra
		inc 	ra
		ldi 	3*5
		str 	ra
		dec 	ra

		ghi 	r2 											; point RD to ghost caught counter
		phi 	rd 											; point RE to 100 points to add.
		phi 	re
		ldi 	GhostCaughtCounter 							
		plo 	rd
		ldi 	Outstanding100Points
		plo 	re
		sex 	rd
		ldn 	re 											; get add value
		add 												; add ghost caught counter to it
		str 	re
		ldn 	rd 											; read gcc
		shl 												; double it
		str 	rd 
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
		phi 	r7
		phi 	rf 											; set lives to 3, level to 1, galois LFSR to non-zero
				 											; R7 points to the sound counter throughout the game.
		ldi 	Studio2BeepTimer							; Studio 2 Beep Counter
		plo 	r7

		ldi 	RandomSeed
		plo 	rf
		sex 	rf
		ldi 	$33											; set the GLFSR to non-zero, won't work if seed == 0
		stxd 
		ldi 	0											; set the current level to 0 (made 1 by new level)
		stxd 												
		ldi 	3 											; set the current lives to 3
		stxd 

NextLevel: 													; start the next level
		ghi 	r2 											; point RD to the current level.
		phi 	rd
		ldi 	Level
		plo 	rd
		ldn 	rd
		adi 	1 											; increment the current level value.
		str 	rd

SameLevel:													; restart the same level
		ldi 	>InitialiseLevel 							; Initialise the level.
		phi 	r4
		ldi 	<InitialiseLevel
		plo 	r4
		sep 	r4

WaitKey0: 													; wait for key 0 to be pressed.
		ldi 	>ScanKeypad 								; read the keyboard
		phi 	r4
		ldi 	<ScanKeypad
		plo 	r4
		sep 	r4
		shl
		bnf 	WaitKey0

RestartSprites:
		ghi 	r2 											; reset the sprite pointer to the start.
		phi 	ra
		ldi 	<SpriteStorage
		plo 	ra

InnerLoop:
		ldi 	>MoveSprite 								; move sprite pointed to by RA
		phi 	r4
		ldi 	<MoveSprite
		plo 	r4
		sep 	r4

		glo 	ra 											; go to next sprite
		adi 	SpriteRecordSize
		plo 	ra
		xri 	SpriteStorageEnd 							; loop back if not reached the end.
		bnz 	InnerLoop

		ldi 	>CheckPlayerEat 							; check what the player has eaten if anything.
		phi 	r4
		ldi 	<CheckPlayerEat
		plo 	r4
		sep 	r4

		ldi 	>FixupOutstanding 							; fix up outstanding points scored.
		phi 	r4
		ldi 	<FixupOutstanding
		plo 	r4
		sep 	r4


		ldi 	Level 										; read level
		plo 	ra 
		ldn 	ra
		shl  												; level x 2
		sdi 	14 											; subtract from 14
		bz 		NoDelay
		bnf 	NoDelay

		plo 	re 											; use it to run the delay loop.
Slow2:	ldi 	64
		plo 	rf
Slow:	dec 	rf
		glo 	rf
		bnz 	Slow
		dec 	re
		glo 	re
		bnz 	Slow2
NoDelay:

		ldi 	<Keyboard									; set RA to point to the keyboard state.
		plo 	ra

		ldi 	>ScanKeypad 								; read the keyboard
		phi 	r4
		ldi 	<ScanKeypad
		plo 	r4
		sep 	r4
		str 	ra 											; save it in the keypad status variable

		dec 	ra 											; bump the frame counter (one before the keyboard state)
		ldn 	ra
		adi 	1
		str 	ra

		ldi 	ChasingTimer 								; decrement chasing timer if > 0
		plo 	ra
		ldn 	ra
		bz 		ChasingZero
		smi 	1
		str 	ra

		ani 	8 											; check alternate frames
		bz 		ChasingZero
		ldi 	11 											; play beeper alternate frames.
		str 	r7

ChasingZero:
		ldi 	BonusFrameCounter 							; point RA to Bonus Frame Counter
		plo 	ra

		ldn 	ra 											; and increment it.
		adi 	1
		str 	ra

		ldi 	EatCounter 									; if eaten everything, go to next level.
		plo 	ra
		ldn 	ra
		bz 		NextLevel

		ldi 	LostLife 									; read the 'lost life' flag.
		plo 	ra
		ldn 	ra
		bz		RestartSprites 								; and go round again if not dead.

		ldi 	60 											; long beep.
		str 	r7

		ldi 	Lives 										; point RA to lives
		plo 	ra
		ldn 	ra 											; decrement lives
		smi 	1
		str 	ra
		bnz 	SameLevel 									; if lives left, then restart.

		ldi 	Score 										; point RA to score
		plo 	ra

		ldi 	1 											; set score digit index to 1
		plo 	re

ScoreWriteLoop:
		glo 	re 											; convert 3 LSBs of RE to screen address in RD
		ani 	7
		plo 	rd
		ldi 	VideoPage 									; put in video page
		phi 	rd

		lda 	ra 											; read next score digit
		adi 	$10 										; score table offset in BIOS
		plo 	rf
		ldi 	$02 										; read from $210+n
		phi 	rf
		ldn 	rf 											; into D, the new offset
		plo 	rf 											; put into R4, R4 now contains 5 rows graphic data

		ldi 	5 											; set R5.0 to 6
		plo 	rc
OutputChar:
		lda 	rf 											; read character and advance
		shr 												; centre in byte
		shr
		str 	rd
		glo 	rd
		adi 	8
		plo 	rd
		dec 	rc 											; decrement counter
		glo 	rc
		bnz 	OutputChar 									; loop back if nonzero
		str 	rd
		inc 	re 											; increment score index counter
		glo 	re
		xri 	7 											; reached seven, end of score write.
		bnz 	ScoreWriteLoop

Dead:	br 		Dead

		.org 	$FF
		.db 	0