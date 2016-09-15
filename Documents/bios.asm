; *****************************************************************************
; *****************************************************************************
;
;               SYSTEM BIOS / INTERPRETER : RCA STUDIO II
;
;          Reverse engineered by Paul Robson (autismuk@aol.com)
;
; *****************************************************************************
; *****************************************************************************
;
;       R1      Video Interrupt Address
;       R2      Stack Pointer (initialised to $08BF)
;       R3      Sub  PC : Interpreting an Instruction
;       R4      Main PC : Interpreter Loop
;       R5      Interpreter Program Pointer
;       R6      Addr first variable (R0-RF)
;       R7      Addr second variable (R0-RF)
;       R8      Accessing system memory
;       R9      Random Seed
;       RA      Index Register
;       RB      Low = Vertical scroll position
;       RF.0    Current Instruction (Byte 1)
;
;       0800-087F               Sprite Graphic Buffers
;       0880-08B0 (approx)      Working Memory Space
;       08xx-08BF               1802 Stack
;       08C0-08CF               Variables (16 off)
;       08C9                    Sprite Number [R9]
;       08CA                    Keypad Select [RA] (1=P1:Left,0=P2:Right)
;       08CB                    Carry [RB]
;       08CC                    Direction [RC]
;       08CD                    Beep length counter [RD]
;       08CE,F                  Counters [RD,RF]
;       08D0-08D7               Sprites (Position)
;       08D8-08DF               Sprites (Height, Flip)
;       08E0-08E7               Direction
;       08E8-08EF               1-Screen Position (internal ?)
;       08F0-08F7               Move counter
;       08F8-08FF               Working Memory Space
;
;       0xxx    Call 1802 code at xxx
;                       0066    Turn the video on.
;       1xxx    Jump to xxx
;       2xxx    Call Subroutine at xxx
;       3raa    Jump to aa (short) if r <> 0
;       4raa    Jump to aa (short) if r == 0
;       5rnn    Skip instruction if Register <> nn
;       6rnn    Load constant nn to r
;       70aa    Decrement R0,short jump if not zero
;       7rnn    Add constant nn to r (NOT r = 0)
;       8xyf    Arithmetic and logic operations, all set carry register RB
;               if not specified then unpredictable.
;                       8xy0    RX := RY,
;                       8xy1    RX := RX or RY
;                       8xy2    RX := RX and RY
;                       8xy3    RX := RX xor RY
;                       8xy4    RX := RX + RY, RB Carry
;                       8xy5    RX := RX - RY, RB Not Borrow
;                       8xy6    RX := RY >> 1, RB LSB           [?]
;                       8xy7    RX := RY - RX, RB Not Borrow    [?]
;                       8xyE    RX := RY << 1, RB MSB           [?]
;       9xy0    Skip instruction if RX <> RY
;       9xyf    System Memory operations (the lowest set bit decides function)
;                       9xy1    RX := RY                (also 3,5,7,9,B,D,F)
;                       9xy2    RX := Memory[RY]        (also 6,A,E)
;                       9xy4    Memory[RY] := RX        (also 4,C)
;                       9xy8    RX -> Memory[RY..RY+2] as BCD, adds 3 to RY
;       Annn    Load index register with nnn
;       Bcnn    Store nn at index register, add c to it (LSB only, wraps)
;       C0xx    Return from subroutine
;       Crnn    Register r = Random Number & nn
;       Dkaa    Check if key k pressed (if F then key in RB), if so
;               short jump to aa and set RB = Key Number. RA is player selector
;       E0      Clear Graphic Buffer for given sprite [Sprite No in R9]
;       E1      Move Sprite in given direction (also 3,5,7,9,B,D,F)
;       E2      Move sprite in direction in RC (also 6,10,E)
;       E4      XOR Data at Index into current picture, Index incremented by Height
;       E8aa    Draw Sprite on screen ; short jump to aa on collision.
;       Frnn    General function nn [0rnn equivalent]
;                       FrA6    Read Memory[Index] into Rr
;                       FrA9    Write Rr to Memory[Index]
;                       FrAC    Read Memory[Index] into Rr and inc. index
;                       FrAF    Write Rr to Memory[Index] and inc. index
;                       FrB3    Set LSB of Index to Register r
;                       FrB6    And Register r with 15, then or with index LSB
;                       F?F2    Clear Memory
;
; *****************************************************************************

        .org 0000h                            ; Starts at base address 0.
        .include "1802.inc"                   ; Include the R0-R15 definitions

Memory  = 0800h                               ; System/Data memory page
VideoMem = 0900h                              ; Video Memory Page

MemStack = Memory+0BFh                        ; Initial stack value

Variables = Memory+0C0h                       ; Variables (16 off,last 3 counters)
Carry = Memory+0CBh                           ; Carry Flag
Direction = Memory+0CCh                       ; Direction override flag
Player = Memory+0CAh                          ; Keypad/Player Selector
SpriteID = Memory+0C9h                        ; Sprite Number
CountEnd = Memory+0CFh                        ; Counters decremented at 50hz
CountStart = Memory+0CDh                      ; till zero (3 off)
SoundCounter = Memory+0CDh                    ; Sound Counter

Program = 0300h                               ; Interpreted program starts here
                                              ; Must be on page boundary

; *****************************************************************************
;
;       Come here at reset. Initialise everything, start the
;       main interpreting loop.
;
; *****************************************************************************

Reset:
        ghi r0               ; 0000:90        ; Clear accumulator (D=0 on reset)
        phi r1               ; 0001:b1        ; R1.High = Interrupt Routine
        phi r4               ; 0002:b4        ; R4.High = Interpreter Loop
        plo r5               ; 0003:a5        ; R5.Low = Program Pointer
        plo rb               ; 0004:ab        ; RB.Low = Vertical Scroll

        ldi Memory / 256     ; 0005:f8 08     ; D = System Memory Page
        phi r2               ; 0007:b2        ; R2.High = Stack Base
        phi r6               ; 0008:b6        ;
        phi r8               ; 0009:b8        ;
        ldi VideoInt & 255   ; 000a:f8 1c     ; R1.Low = Interrupt Routine
        plo r1               ; 000c:a1
        ldi MemStack & 255   ; 000d:f8 bf     ; R2.Low = Stack Base
        plo r2               ; 000f:a2
        ldi MainLoop & 255   ; 0010:f8 6b     ; R4.Low = Interpreter Loop
        plo r4               ; 0012:a4        ; 
        ldi Program / 256    ; 0013:f8 03     ; R5.High = Program Pointer
        phi r5               ; 0015:b5        ; 
        sep r4               ; 0016:d4        ; Go to main interpreter loop

; *****************************************************************************
;
;       Exit from video interrupt.
;
; *****************************************************************************

RetNoSound:
        req                  ; 0017:7a        ; Turn off sound
RetSoundCont:
        lda r2               ; 0018:42        ; D = Data flag byte
        shr                  ; 0019:f6        ; Shift into DF
        lda r2               ; 001a:42        ; Restore D
        ret                  ; 001b:70        ; And return to caller.

; *****************************************************************************
;
;       Video interrupt. See Bill Richman's Elf Pages for more
;       information at http://incolor.intenebr.com/bill_r
;
;       This breaks the following :-
;
;               R0      Points to end of display, 09xx
;               R1      (Interrupt vector, unchanged)
;               R2      (Stack Pointer, unchanged)
;               R8      $08CD on exit
;               R9      Incremented every interrupt
;               Q       Set or reset according to $08CD
;               Mem     $08CD,E,F decremented if non-zero.
;
; *****************************************************************************

VideoInt:
        dec r2               ; 001c:22        ; Save (X,P) at R2-1 (stack)
        sav                  ; 001d:78        ; 
        dec r2               ; 001e:22        ; Save D at R2-1 (stack)
        stxd                 ; 001f:73        ; 
        lbr WasteCycles      ; 0020:c0 00 23  ; Waste a few cycles for video
WasteCycles:
        shlc                 ; 0023:7e        ; D bit 0 now contains the DF Flag
        str r2               ; 0024:52        ; Save DF at R2 (stack)

        inc r9               ; 0025:19        ; Change Random Seed

        ldi VideoMem/256     ; 0026:f8 09     ; R0.High points to video
        phi r0               ; 0028:b0        ; 

        ldi (CountEnd&255)+1 ; 0029:f8 d0     ; R8 points to 08D0h
        plo r8               ; 002b:a8        ; 
        glo rb               ; 002c:8b        ; Get start of display position

        plo r0               ; 002d:a0        ;
        sex r2               ; 002e:e2        ; 8 DMA Cycles
Refresh:
        dec r0               ; 002f:20        ;
        plo r0               ; 0030:a0        ; 
        sex r2               ; 0031:e2        ; 8 DMA Cycles
        dec r0               ; 0032:20        ; 
        plo r0               ; 0033:a0        ; 
        sex r2               ; 0034:e2        ; 8 DMA Cycles
        dec r0               ; 0035:20        ; 
        plo r0               ; 0036:a0        ; 
        glo r0               ; 0037:80        ; 8 DMA Cycles
        dec r0               ; 0038:20        ; 
        plo r0               ; 0039:a0        ; 
        bn1 Refresh          ; 003a:3c 2f     ; Not end of this frame
WaitEnd:
        dec r0               ; 003c:20        ; Tidy up
        plo r0               ; 003d:a0        ; 
        b1  WaitEnd          ; 003e:34 3c     ; Wait for end of display pulse

_CountCheck:
        dec r8               ; 0040:28        ; Look at next byte of counters
        ldn r8               ; 0041:08        ; Decrement if non-zero
        bz  _CountIsZero     ; 0042:32 47     ;
        smi 001h             ; 0044:ff 01     ;
        str r8               ; 0046:58        ; 
_CountIsZero:
        glo r8               ; 0047:88        ; Has counter reached $00000
        xri CountStart & 255 ; 0048:fb cd     ;
        bnz _CountCheck      ; 004a:3a 40     ; if not, keep going
 
        ldn r8               ; 004c:08        ; Is the counter zero ?
        bz  RetNoSound       ; 004d:32 17     ; if so, sound off
        seq                  ; 004f:7b        ; sound on
        br  RetSoundCont     ; 0050:30 18     ; and exit
;
;       Code for Crnn, Random number generator.
;
_Random:
        inc r9               ; 0052:19        ; Bump the random pointer
        glo r9               ; 0053:89        ; RE := $00.R9Low
        plo re               ; 0054:ae        ;
        ghi r3               ; 0055:93        ;
        phi re               ; 0056:be        ; 
        ghi r9               ; 0057:99        ; D := R9High
        sex re               ; 0058:ee        ; 
        add                  ; 0059:f4        ; Calc R9.1 + Mem[R9.Low]
        str r6               ; 005a:56        ; Save in the register specified
        shr                  ; 005b:f6        ; Add half the value to it
        sex r6               ; 005c:e6        ;
        add                  ; 005d:f4        ; 
        phi r9               ; 005e:b9        ; Tweak the MSB of random pointer
        str r6               ; 005f:56        ; Update the value
        lda r5               ; 0060:45        ; Get the AND mask
        and                  ; 0061:f2        ; AND with the random value
        str r6               ; 0062:56        ; Write it back
        sep r4               ; 0063:d4        ; Next instruction

        idl                  ; 0064:00        ; Wasted space ?
        idl                  ; 0065:00        ; 
;
;       Turn on the video display
;
        sex r2               ; 0066:e2        ; Make space for INP command
        dec r2               ; 0067:22        ; 
        inp 1                ; 0068:69        ; INP1 turns video on
        inc r2               ; 0069:12        ; Fix Stack
        sep r4               ; 006a:d4        ; Next Instruction

; *****************************************************************************
;
;                               Main interpreter loop
;
; *****************************************************************************

MainLoop:                                     ; Main interpreter loop
        ghi r6               ; 006b:96        ; Set 2nd variable High
        phi r7               ; 006c:b7        ; 
        ghi r4               ; 006d:94        ; RC.High := $00
        phi rc               ; 006e:bc        ; 
        lda r5               ; 006f:45        ; Read instruction, adv R5
        plo rc               ; 0070:ac        ; RC.Low := Instruction
        plo rf               ; 0071:af        ; RF.Low := Instruction
        shr                  ; 0072:f6        ; Put 4 MSB of instruction into D
        shr                  ; 0073:f6        ; 
        shr                  ; 0074:f6        ; 
        shr                  ; 0075:f6        ; 
        bz  CodeExec         ; 0076:32 94     ; If zero, exec as code

        ori AddrTable & 255  ; 0078:f9 e0     ; D := E1-EF (depends on inst MSN)
        plo rc               ; 007a:ac        ; RC points to instr addr table
        glo rf               ; 007b:8f        ; D = original instruction
        ani 00fh             ; 007c:fa 0f     ; D = C0-CF (inst LSB)
        ori Variables & 255  ; 007e:f9 c0     ;
        plo r6               ; 0080:a6        ; R6.Low = C0-CF (Instr Byte1 LSN)

        ldn r5               ; 0081:05        ; Get instruction 2nd byte
        shr                  ; 0082:f6        ; Isolate MS Nibble
        shr                  ; 0083:f6        ; 
        shr                  ; 0084:f6        ; 
        shr                  ; 0085:f6        ; 
        ori  Variables & 255 ; 0086:f9 c0     ; R7.Low = C0-CF (Instr Byte2 MSN)
        plo r7               ; 0088:a7        ; 

        lda rc               ; 0089:4c        ; Read Instruction Addr High
        phi r3               ; 008a:b3        ; Into R3.High
        glo rc               ; 008b:8c        ; Add 15 to address table now
        adi 00fh             ; 008c:fc 0f     ; F1-FF [16 total with LDA]
        plo rc               ; 008e:ac        ; 
        lda rc               ; 008f:4c        ; Read Instruction Addr Low
_Execute:
        plo r3               ; 0090:a3        ; Exec Addr.Low := R3
        sep r3               ; 0091:d3        ; And jump there
        br  MainLoop         ; 0092:30 6b     ; Loop back on return
;
;       Execute instructions as code.
;
CodeExec:
        glo rf               ; 0094:8f        ; Get Instruction Byte
        ani 00fh             ; 0095:fa 0f     ; Get Addr 4 MSB
        phi r3               ; 0097:b3        ; Put in R3
        lda r5               ; 0098:45        ; Get Low Byte of Address
        br  _Execute         ; 0099:30 90     ; and Jump there
;
;       8XYF    RX := RX (function) RY [see above for functions]
;
Cmd_ALU:
        dec r2               ; 009b:22        ; Make space on stack
        sex r2               ; 009c:e2        ; Write to stack area
        ldi 0d3h             ; 009d:f8 d3     ; Last instruction "SEP 3"
        stxd                 ; 009f:73        ; 
        lda r5               ; 00a0:45        ; Make MSNibble byte 1 into a
        ori 0f0h             ; 00a1:f9 f0     ; 1802 ALU Instruction
        str r2               ; 00a3:52        ; Save that
        sex r6               ; 00a4:e6        ; R(X) is now the first register
        lda r7               ; 00a5:47        ; Read the second register
        sep r2               ; 00a6:d2        ; Do the instruction, fixes R2 too
        str r6               ; 00a7:56        ; Save the result back
        ldi Carry & 255      ; 00a8:f8 cb     ; R6 := $08CB, Register B
        plo r6               ; 00aa:a6        ; 
        ghi r1               ; 00ab:91        ; D = 0
        shlc                 ; 00ac:7e        ; D = Carry value
        str r6               ; 00ad:56        ; Save carry value
        sep r4               ; 00ae:d4        ; Return
;
;       C0xx, return from subroutine, Crxx Register r = Random & 255
;
Cmd_Ret:
        glo r6               ; 00af:86        ; Get the address of MSN Byte 1
        xri Variables & 255  ; 00b0:fb c0     ; Check it is C0
        bnz _Random          ; 00b2:3a 52     ; No, go to random number bit
        lda r2               ; 00b4:42        ; Pop MSB off stack
        phi r5               ; 00b5:b5        ; 
        lda r2               ; 00b6:42        ; Pop LSB off stack
        plo r5               ; 00b7:a5        ; 
        sep r4               ; 00b8:d4        ; Next instruction
;
;       6RNN    Load R Immediate with NN
;
Cmd_LAcc:
        lda r5               ; 00b9:45        ; Get the 2nd byte (data)
        str r6               ; 00ba:56        ; Store in register
        sep r4               ; 00bb:d4        ; Next instruction
;
;       Powers of 10 Data Table (used in BCD conversion)
;
Power10:
        .db 64h              ; 00bc:64        ; 100
        .db 0Ah              ; 00bd:0a        ; 10
        .db 01h              ; 00be:01        ; 1
;
;       3RAA    Short jump to AA if R <> 0
;
Cmd_Jnz:
        ldn r6               ; 00bf:06        ; Read the register
        bnz _Jump0           ; 00c0:3a c7     ; If non zero jump
_Skip0: inc r5               ; 00c2:15        ; Advance past address
        sep r4               ; 00c3:d4        ; and exit
;
;       4RAA    Short jump to AA if R = 0
;
Cmd_Jz:
        ldn r6               ; 00c4:06        ; Read the register
        bnz _Skip0           ; 00c5:3a c2     ; If non zero skip
_Jump0:
        ldn r5               ; 00c7:05        ; Get address
        plo r5               ; 00c8:a5        ; Update Interpreter Address
        sep r4               ; 00c9:d4        ; Next Instruction
;
;       2XXX    Call subroutine at xxx
;
Cmd_Call:
        inc r5               ; 00ca:15        ; R5 points to next instruction
        glo r5               ; 00cb:85        ; save LSB it on the stack
        dec r2               ; 00cc:22        ; 
        str r2               ; 00cd:52        ; 
        ghi r5               ; 00ce:95        ; Save MSB of return address
        dec r2               ; 00cf:22        ; 
        str r2               ; 00d0:52        ; 
        dec r5               ; 00d1:25        ; Restore R5 so GOTO works
;
;       1xxx    Jump Command
;
Cmd_Jump:
        lda r5               ; 00d2:45        ; Get LSB and advance pointer
        plo r5               ; 00d3:a5        ; Update LSB Interpreter
        glo r6               ; 00d4:86        ; R6 := 08Cx, x is Nibl of MSB
        ani 00fh             ; 00d5:fa 0f     ; Strip off the rest
        phi r5               ; 00d7:b5        ; Put into MSB Interpreter
        sep r4               ; 00d8:d4        ; Next instruction
;
;       2xxx    Set Index Register Command
;
Cmd_LIndex:
        glo r6               ; 00d9:86        ; Get MSB and strip off MSN
        ani 00fh             ; 00da:fa 0f     ; 
        phi ra               ; 00dc:ba        ; Put in High Byte Index
        lda r5               ; 00dd:45        ; Get LSB and advance pointer
        plo ra               ; 00de:aa        ; Put in Low Byte Index
        sep r4               ; 00df:d4        ; Next Instruction

; *****************************************************************************
;
;       Instruction Address Table. First 16 bytes are High byte, Second
;       16 are Low Byte
;
; *****************************************************************************

AddrTable:
        .db 0                ; 00e0:00        ; 0xxx Machine Call, (seperate)
        .db Cmd_Jump/256     ; 00e1:00        ; 1xxx Jump to xxx
        .db Cmd_Call/256     ; 00e2:00        ; 2xxx Call Subroutine at xxx
        .db Cmd_Jnz/256      ; 00e3:00        ; 3raa Short Jump if r <> 0
        .db Cmd_Jz/256       ; 00e4:00        ; 4raa Short Jump if r == 0
        .db Cmd_SkipN/256    ; 00e5:02        ; 5rxx Skip if r <> xx
        .db Cmd_LAcc/256     ; 00e6:00        ; 6rnn Load r with nn (imm)
        .db Cmd_Add/256      ; 00e7:02        ; 7rnn Add nn to r (70xx different)
        .db Cmd_ALU/256      ; 00e8:00        ; 8xyf X := X (function) Y
        .db Cmd_Mem/256      ; 00e9:02        ; 9xyf Memory functions
        .db Cmd_LIndex/256   ; 00ea:00        ; Axxx Load Index with xxx
        .db Cmd_LCI/256      ; 00eb:02        ; Bcnn Store constant and bump
        .db Cmd_Ret / 256    ; 00ec:00        ; Cxxx Return and Random Number
        .db Cmd_Key / 256    ; 00ed:02        ; Dkaa Check key and branch
        .db Cmd_Draw/256     ; 00ee:01        ;
        .db Cmd_F / 256      ; 00ef:02        ; Frxx General funcs (jump to 02xx)
;
        .db 0                ; 00f0:00        ; 0xxx
        .db Cmd_Jump & 255   ; 00f1:d2        ; 1xxx
        .db Cmd_Call & 255   ; 00f2:ca bf c4  ; 2xxx
        .db Cmd_Jnz & 255                     ; 3xxx
        .db Cmd_Jz & 255                      ; 4xxx
        .db Cmd_SkipN & 255  ; 00f5:4e        ; 5xxx
        .db Cmd_LAcc & 255   ; 00f6:b9        ; 6xxx
        .db Cmd_Add & 255    ; 00f7:3d 9b     ; 7xxx
        .db Cmd_ALU & 255                     ; 8xxx
        .db Cmd_Mem & 255    ; 00f9:56        ; 9xxx
        .db Cmd_LIndex & 255 ; 00fa:d9        ; Axxx
        .db Cmd_LCI & 255    ; 00fb:e5        ; Bxxx
        .db Cmd_Ret & 255    ; 00fc:af        ; Cxxx
        .db Cmd_Key & 255    ; 00fd:bf        ; Dxxx
        .db Cmd_Draw & 255   ; 00fe:00        ; Exxx
        .db Cmd_F & 255      ; 00ff:a4        ; Fxxx

; *****************************************************************************
;
;       Drawing code.
;
;       Offsets (Table at $08D0 onwards) :-
;
;       $00     Screen Physical Position
;       $08     Height: Bits 0..3. Bit 7 switches the bytes around (flip ?)
;       $10     Direction
;       $18     1-Screen Position (no idea why)
;       $20     Horizontal Move Counter
;
;       Each of the 8 sprites has a picture buffer at $0800 + n * 16.
;       These are alternating 8 byte values, one for the left, one
;       for the right.
;
;       $E0     Clear sprite picture buffer
;       $E1     Move
;       $E2     Move in direction in RC
;       $E4     XOR Plot data at Index (changed) into sprite picture buffer
;               for height given.
;       $E8aa   Draw on screen ; short jump if collision.
;
; *****************************************************************************

Cmd_Draw:
        ldi SpriteID & 255   ; 0100:f8 c9     ; R7 now accesses IR9, Sprite ID
        plo r7               ; 0102:a7        ; 
        ldn r7               ; 0103:07        ; Read register IR9
        shl                  ; 0104:fe        ; Multiply by 16
        shl                  ; 0105:fe        ; 
        shl                  ; 0106:fe        ; Sets up the sprite data pointer
        shl                  ; 0107:fe        ; 
        plo r6               ; 0108:a6        ; R6.0 := $0800+ Sprite# * 16

        ldi 0d0h             ; 0109:f8 d0     ; Calculate IR9+0D0h
        sex r7               ; 010b:e7        ;
        add                  ; 010c:f4        ; 
        plo r7               ; 010d:a7        ; R7 now points to $08D0+IR9
                                              ; the sprite base address

        ldi PointRFTo/256    ; 010e:f8 02     ; RC := $0292, the set up pointer
        phi rc               ; 0110:bc        ; routine. This sets RF equal to
        ldi PointRFTo&255    ; 0111:f8 92     ; the base pointer in R7.0 added
        plo rc               ; 0113:ac        ; to the following byte

        sep rc               ; 0114:dc        ; Point to offset $10
        .db     10h
        ldn rf               ; 0116:0f        ; Read offset $10
        phi rd               ; 0117:bd        ; Save in RD.1

        sep rc               ; 0118:dc        ; Point to offset $08, Height
        .db 08h              ; 0119:08        ;
        ldn rf               ; 011a:0f        ; Read offset $08
        ani 00fh             ; 011b:fa 0f     ; only the lower 4 bits matter
        plo re               ; 011d:ae        ; Save in RE.0

        ldn rf               ; 011e:0f        ; Re read offset $08
        ani 080h             ; 011f:fa 80     ; Keep bit 7 only
        phi re               ; 0121:be        ; Save in RE.1

        ldn r7               ; 0122:07        ; Read offset $00
        plo rd               ; 0123:ad        ; Save in RD.0
 
        dec r5               ; 0124:25        ; Re-read the first byte of the
        lda r5               ; 0125:45        ; opcode

        shr                  ; 0126:f6        ; Bit 0 set
        bdf _Move            ; 0127:33 4e     ;
        shr                  ; 0129:f6        ; Bit 1 set
        bdf _MoveC           ; 012a:33 49     ;
        shr                  ; 012c:f6        ; Bit 2 set
        bdf _Draw            ; 012d:33 3d     ; Xor Draw into Sprite picture
        shr                  ; 012f:f6        ; Bit 3 set
        bdf _DrawSprite      ; 0130:33 bc     ; Draw onto video display
;
;       Clear Picture Buffer to all Zeroes
;
        ldi 010h             ; 0132:f8 10     ; RF := 16, size of sprite space
        plo rf               ; 0134:af        ; 
_Clear0:
        ghi r1               ; 0135:91        ; Write zero at that location
        str r6               ; 0136:56        ; 
        inc r6               ; 0137:16        ; Go to next one
        dec rf               ; 0138:2f        ; Do all 16 bytes
        glo rf               ; 0139:8f        ; 
        bnz _Clear0          ; 013a:3a 35     ;
_Continue:
        sep r4               ; 013c:d4        ; 
;
;       XOR Data at Index into Sprite, amount dependent on the height of
;       the sprite. Index is changed (Height added). Skips 2 for some reason.
;
_Draw:                                        ; function $E4,$EC.
        sex r6               ; 013d:e6        ; R[X] is the sprite data
_DrawLoop:
        glo re               ; 013e:8e        ; Height is zero ?
        bz  _Continue        ; 013f:32 3c     ; If so, completed
        lda ra               ; 0141:4a        ; Read byte from index and inc
        xor                  ; 0142:f3        ; XOR with sprite data
        str r6               ; 0143:56        ; Update
        inc r6               ; 0144:16        ; Next Sprite Byte x 2
        inc r6               ; 0145:16        ; 
        dec re               ; 0146:2e        ; Decrement height counter
        br  _DrawLoop        ; 0147:30 3e     ; Do the next one.
;
;       Move in direction RC, override the read direction
;
_MoveC:
        ldi Direction & 255  ; 0149:f8 cc     ; RF := $08CC (Register C)
        plo rf               ; 014b:af        ; 
        ldn rf               ; 014c:0f        ; Read it
        phi rd               ; 014d:bd        ; Use instead of offset $10
;
;       Move in direction in RD.1
;
_Move:
        ghi rd               ; 014e:9d        ; Decide on direction of movement
        xri 002h             ; 014f:fb 02     ; 2 is up
        bz  _Up              ; 0151:32 63     ;
        ghi rd               ; 0153:9d        ; 
        xri 008h             ; 0154:fb 08     ; 8 is down
        bz  _Down            ; 0156:32 6d     ;
        ghi rd               ; 0158:9d        ; 
        xri 004h             ; 0159:fb 04     ; 4 is left
        bz  _Left            ; 015b:32 97     ;
        ghi rd               ; 015d:9d        ; 6 is right
        xri 006h             ; 015e:fb 06     ; 
        bz _Right            ; 0160:32 72     ;
        sep r4               ; 0162:d4        ; All others ignored

_Up:
        ldn r7               ; 0163:07        ; Subtract 8 from the position
        smi 008h             ; 0164:ff 08     ;
_MoveVertical:
        str r7               ; 0166:57        ; 
        sep rc               ; 0167:dc        ; Point RF to offset $18
        .db 18h
        ghi r3               ; 0169:93        ; D := $01
        sd                   ; 016a:f5        ; D = 1 - Physical Position
        str rf               ; 016b:5f        ; Store in $18
        sep r4               ; 016c:d4        ; And exit

_Down:
        ldn r7               ; 016d:07        ; Calculate position + 8
        adi 008h             ; 016e:fc 08     ; 
        br  _MoveVertical    ; 0170:30 66     ; And do as for 'up' code.

_Right:
        glo re               ; 0172:8e        ; Done the whole sprite
        bz  _DecMoveCtr      ; 0173:32 f9     ; if so, exit

        ldn r6               ; 0175:06        ; Shift the first byte right 1
        shr                  ; 0176:f6        ; 
        str r6               ; 0177:56        ; 
        bnf _NoRight2        ; 0178:3b 81     ; If no bit shifted out, skip
        ghi re               ; 017a:9e        ; 
        bnz _NoRight2        ; 017b:3a 81     ; If right side, skip
        ldi 080h             ; 017d:f8 80     ; 
        phi re               ; 017f:be        ; 
        inc rd               ; 0180:1d        ; Advance screen pointer
_NoRight2:
        inc r6               ; 0181:16        ; Point to second byte
        ldn r6               ; 0182:06        ; Shift that right as well
        shrc                 ; 0183:76        ; 
        str r6               ; 0184:56        ; 
        bnf _NoRight3        ; 0185:3b 93     ; No carry out, skip
        dec r6               ; 0187:26        ; Point to previous byte
        ldn r6               ; 0188:06        ; Set bit 7
        ori 080h             ; 0189:f9 80     ; 
        str r6               ; 018b:56        ; 
        inc r6               ; 018c:16        ; Fix the pointer
        ghi re               ; 018d:9e        ;
        bz _NoRight3         ; 018e:32 93     ; Skip if not swapped
        ghi r1               ; 0190:91        ; Swap it back
        phi re               ; 0191:be        ; 
        inc rd               ; 0192:1d        ; Advance screen pointer
_NoRight3:
        inc r6               ; 0193:16        ; Point to next pair
        dec re               ; 0194:2e        ; Decrement Height counter
        br  _Right           ; 0195:30 72     ; And do next line

_Left:
        glo re               ; 0197:8e        ; Check height counter
        bz  _DecMoveCtr      ; 0198:32 f9     ; Exit if zero
        ldn r6               ; 019a:06        ; Shift first byte left
        shl                  ; 019b:fe        ; 
        str r6               ; 019c:56        ; 
        bnf _Left0           ; 019d:3b a5     ; If no carry out, that's it
        ghi re               ; 019f:9e        ; If this is the left side, skip
        bz  _Left0           ; 01a0:32 a5     ;
        ghi r1               ; 01a2:91        ; Swap the sides around
        phi re               ; 01a3:be        ; 
        dec rd               ; 01a4:2d        ; Change the pointer
_Left0:
        inc r6               ; 01a5:16        ; Look at 2nd byte
        ldn r6               ; 01a6:06        ; Shift it left
        shlc                 ; 01a7:7e        ; 
        str r6               ; 01a8:56        ; 
        bnf _Left1           ; 01a9:3b b8     ; No bit out, skip
        dec r6               ; 01ab:26        ; Set bit in 2nd byte
        ldn r6               ; 01ac:06        ; 
        ori 001h             ; 01ad:f9 01     ; 
        str r6               ; 01af:56        ; 
        inc r6               ; 01b0:16        ; Fix it back again
        ghi re               ; 01b1:9e        ; If the right side , skip
        bnz _Left1           ; 01b2:3a b8     ;
        ldi 080h             ; 01b4:f8 80     ; Else swap them around
        phi re               ; 01b6:be        ; 
        dec rd               ; 01b7:2d        ; Adjust pointer
_Left1:
        inc r6               ; 01b8:16        ; Point to next byte
        dec re               ; 01b9:2e        ; Decrement height counter
        br  _Left            ; 01ba:30 97     ; And do for all the data

_DrawSprite:
        ghi r3               ; 01bc:93        ; Set up RC to point to the
        phi rc               ; 01bd:bc        ; XOR Plot drawing subroutine
        ldi XORPlot & 255    ; 01be:f8 eb     ;
        plo rc               ; 01c0:ac        ; 

        ghi r1               ; 01c1:91        ; Clear the collision flag
        plo rf               ; 01c2:af        ; 

        ghi re               ; 01c3:9e        ; Check flip (draw direction)
        bz  _DrawIt          ; 01c4:32 d4     ; bit.
        dec rd               ; 01c6:2d        ;

_DrawIt2:
        glo re               ; 01c7:8e        ; Exit if height counter is zero
        bz  ExitDraw         ; 01c8:32 e1     ;
        sep rc               ; 01ca:dc        ; Xor draw part 0 on left
        inc rd               ; 01cb:1d        ; 
        sep rc               ; 01cc:dc        ; Xor Draw part 1 on right
        glo rd               ; 01cd:8d        ; Next vertical line down
        adi 007h             ; 01ce:fc 07     ; 
        plo rd               ; 01d0:ad        ; 
        dec re               ; 01d1:2e        ; Decrement Height Counter
        br _DrawIt2          ; 01d2:30 c7     ; Loop back till finished

_DrawIt:
        glo re               ; 01d4:8e        ; Exit if height counter is zero
        bz  ExitDraw         ; 01d5:32 e1     ;
        sep rc               ; 01d7:dc        ; Xor Draw part 0 on right
        dec rd               ; 01d8:2d        ; 
        sep rc               ; 01d9:dc        ; Xor Draw part 1 on left
        glo rd               ; 01da:8d        ; Next vertical line down
        adi 009h             ; 01db:fc 09     ; 
        plo rd               ; 01dd:ad        ; 
        dec re               ; 01de:2e        ; Decrement height counter
        br  _DrawIt          ; 01df:30 d4     ; And keep going until finished.

ExitDraw:
        glo rf               ; 01e1:8f        ; Look at collision flag
        bnz _CSJ             ; 01e2:3a e6     ; If collide then short jump
        inc r5               ; 01e4:15        ; Skip address and return
        sep r4               ; 01e5:d4        ;
_CSJ:
        ldn r5               ; 01e6:05        ; Do a short jump to the
        plo r5               ; 01e7:a5        ; following address
        sep r4               ; 01e8:d4        ; Next instruction
;
        inc r6               ; 01e9:16        ; Next data item
        sep r3               ; 01ea:d3        ; Exit
;
;       RD.0 points to a video memory location. XOR Plot Memory[R6]
;       at that byte, post incrementing R6. Set RF.0 non zero if collision
;
XORPlot:
        ldi 009h             ; 01eb:f8 09     ; Point RD to video memory
        phi rd               ; 01ed:bd        ; 
        sex rd               ; 01ee:ed        ; R[X] is video byte
        ldn r6               ; 01ef:06        ; And screen with R6
        and                  ; 01f0:f2        ; 
        bz  _NoCollide       ; 01f1:32 f4     ; if zero, then no collision
        plo rf               ; 01f3:af        ; set collision flag
_NoCollide:
        ldn r6               ; 01f4:06        ; Read pixel data
        xor                  ; 01f5:f3        ; Xor with screen
        str rd               ; 01f6:5d        ; Write back to screen
        br 001e9h            ; 01f7:30 e9     ; 
;
;       Decrement horizontal move counter (offset $20), update bit 7
;       of Height, update new position, and return.
;
_DecMoveCtr:
        sep rc               ; 01f9:dc        ; Point to horiz move counter
        .db 20h              ; 01fa:20        ;
        ldn rf               ; 01fb:0f        ; Read value
        smi 001h             ; 01fc:ff 01     ; Subtract 1
        str rf               ; 01fe:5f        ; Write back

        sep rc               ; 01ff:dc        ; Point to height
        .db 08h              ; 0200:08        ;
        ldn rf               ; 0201:0f        ; Copy new bit 7 back in from
        ani 00fh             ; 0202:fa 0f     ; RE.1. Mask out height
        str rf               ; 0204:5f        ; 
        ghi re               ; 0205:9e        ; Get new bit 7
        or                   ; 0206:f1        ; Or with value
        str rf               ; 0207:5f        ; save it back

        glo rd               ; 0208:8d        ; Copy new position back
        str r7               ; 0209:57        ; 
        sep r4               ; 020a:d4        ; Return

; *****************************************************************************
;
;          Beep, and wait for key selected to be released.
;
; *****************************************************************************


        .db  022h,0F9h                         ; CALL $2F9 [Beep and Delay]
        .db  023h,0C3h                         ; CALL $3C3 [Wait for key release]
        .db  0C0h                              ; RET

; *****************************************************************************
;
;                     Offsets in this page to number data
;
; *****************************************************************************

NumberGraphicOffset:
        .db _Zero & 255                       ; Digit 0
        .db _One & 255       ; 0211:1a        ; Digit 1
        .db _Two & 255       ; 0212:25        ; Digit 2
        .db _Three & 255     ; 0213:1f        ; Digit 3
        .db _Four & 255      ; 0214:38 23     ; Digit 4
        .db _Five & 255                       ; Digit 5
        .db _Six & 255       ; 0216:27        ; Digit 6
        .db _Seven & 255     ; 0217:33 29     ; Digit 7
        .db _Eight & 255                      ; Digit 8
        .db _Nine & 255      ; 0219:2b        ; Digit 9

; *****************************************************************************
;
;                               Number Graphic Data
;
; *****************************************************************************

_One:
        .db  060h            ; 021a:60        ; .xx.....
        .db  020h            ; 021b:20        ; ..x.....
        .db  020h            ; 021c:20        ; ..x.....
        .db  020h            ; 021d:20        ; ..x.....
        .db  070h            ; 021e:70        ; .xxx....
_Three:
        .db  0f0h            ; 021f:f0        ; xxxx....
        .db  010h            ; 0220:10        ; ...x....
        .db  070h            ; 0221:70        ; .xxx....
        .db  010h            ; 0222:10        ; ...x....
_Five:
        .db  0f0h            ; 0223:f0        ; xxxx....
        .db  080h            ; 0224:80        ; x.......
_Two:
        .db  0f0h            ; 0225:f0        ; xxxx....
        .db  010h            ; 0226:10        ; ...x....
_Six:
        .db  0f0h            ; 0227:f0        ; xxxx....
        .db  080h            ; 0228:80        ; x.......
_Eight:
        .db  0f0h            ; 0229:f0        ; xxxx....
        .db  090h            ; 022a:90        ; x..x....
_Nine:
        .db  0f0h            ; 022b:f0        ; xxxx....
        .db  090h            ; 022c:90        ; x..x....
        .db  0f0h            ; 022d:f0        ; xxxx....
        .db  010h            ; 022e:10        ; ...x....
_Zero:
        .db  0f0h            ; 022f:f0        ; xxxx....
        .db  090h            ; 0230:90        ; x..x....
        .db  090h            ; 0231:90        ; x..x....
        .db  090h            ; 0232:90        ; x..x....
_Seven:
        .db  0f0h            ; 0233:f0        ; xxxx....
        .db  010h            ; 0234:10        ; ...x....
        .db  010h            ; 0235:10        ; ...x....
        .db  010h            ; 0236:10        ; ...x....
        .db  010h            ; 0237:10        ; ...x....
_Four:
        .db  0a0h            ; 0238:a0        ; x.x.....
        .db  0a0h            ; 0239:a0        ; x.x.....
        .db  0f0h            ; 023a:f0        ; xxxx....
        .db  020h            ; 023b:20        ; ..x.....
        .db  020h            ; 023c:20        ; ..x.....

; *****************************************************************************
;
;                   Lots of other interpreting routines
;
; *****************************************************************************
;
;       7rxx Add, (except for 70xx, Decrement and jump if not zero)
;
Cmd_Add:
        glo r6               ; 023d:86        ; Look at register number
        ani 00fh             ; 023e:fa 0f     ; 
        bz _Cmd70            ; 0240:32 47     ;
        sex r6               ; 0242:e6        ; Access register r
        lda r5               ; 0243:45        ; Read constant
        add                  ; 0244:f4        ; Add to r
        str r6               ; 0245:56        ; Update result
        sep r4               ; 0246:d4        ; Next instruction
_Cmd70:
        ldn r6               ; 0247:06        ; Read value
        smi 001h             ; 0248:ff 01     ; Decrement
        bnz _UpdateR         ; 024a:3a e1     ; if not 0, then store & jump
        inc r5               ; 024c:15        ; skip address
_Next0:
        sep r4               ; 024d:d4        ; Next instruction
;
;       5rnn    Skip if Register <> Constant
;
Cmd_SkipN:
        lda r5               ; 024e:45        ; Read the constant
_Compare:
        sex r6               ; 024f:e6        ; Access the first register
        xor                  ; 0250:f3        ; Compare them
        bz  _Next0           ; 0251:32 4d     ; If the same, do next instruction
        inc r5               ; 0253:15        ; Skip next instruction
        inc r5               ; 0254:15        ; 
        sep r4               ; 0255:d4        ; the *next* instruction
;
;       9xyf Memory Operations [9xy0 is skip if RX <> RY]
;
Cmd_Mem:
        ghi r6               ; 0256:96        ; RC := Memory page.Register y
        phi rc               ; 0257:bc        ; i.e. it is indirection.
        ldn r7               ; 0258:07        ; if R0 = $32 then 90xx points
        plo rc               ; 0259:ac        ; RC to $0832
        lda r5               ; 025a:45        ; Get the operation code & skip it
        shr                  ; 025b:f6        ; Bit 0 set ?
        bdf _CopyReg         ; 025c:33 9b     ; it is RX = RY
        shr                  ; 025e:f6        ; Bit 1 set ?
        bdf _ReadMem         ; 025f:33 6a     ; it is RX = Mem[RY]
        shr                  ; 0261:f6        ; Bit 2 set ?
        bdf _WriteMem        ; 0262:33 6d     ; it is Mem[RY] = RX
        shr                  ; 0264:f6        ; Bit 3 set ?
        bdf _BCDConv         ; 0265:33 70     ; it is RX->Mem[RY] as BCD
        ldn r7               ; 0267:07        ; Restore RY
        br  _Compare         ; 0268:30 4f     ;

_ReadMem:
        ldn rc               ; 026a:0c        ; Read Memory location
        str r6               ; 026b:56        ; Store in Rx
        sep r4               ; 026c:d4        ; 
_WriteMem:
        ldn r6               ; 026d:06        ; Read Rx
        str rc               ; 026e:5c        ; Store in Memory location Mem[Ry]
        sep r4               ; 026f:d4        ; 
_BCDConv:
        sex r6               ; 0270:e6        ; R[X] is Rx
        ldn r6               ; 0271:06        ; Save Rx value in RF.1
        phi rf               ; 0272:bf        ;
        ghi r1               ; 0273:91        ; 
        phi re               ; 0274:be        ; 
        ldi Power10 & 255    ; 0275:f8 bc     ; Set RE := Powers of 10 table
        plo re               ; 0277:ae        ; 
        dec rc               ; 0278:2c        ; Fix first check ?

_AnotherDigit:
        inc rc               ; 0279:1c        ; Look at next Mem[RY] byte
        ghi r1               ; 027a:91        ; Set it to zero
        str rc               ; 027b:5c        ; 
_RepSubtract:
        ldn re               ; 027c:0e        ; Read first power of 10
        sd                   ; 027d:f5        ; subtract that value
        bnf _NextDigit       ; 027e:3b 87     ; if borrow then done this one
        str r6               ; 0280:56        ; update the result
        ldn rc               ; 0281:0c        ; increment Mem[RY]
        adi 001h             ; 0282:fc 01     ; 
        str rc               ; 0284:5c        ; 
        br  _RepSubtract     ; 0285:30 7c     ; And go around again
_NextDigit:
        lda re               ; 0287:4e        ; Get the next value
        shr                  ; 0288:f6        ; is bit 0 set (e.g. it is 1)
        bnf _AnotherDigit    ; 0289:3b 79     ; if not, do another digit
        ghi rf               ; 028b:9f        ; Restore RX value
        str r6               ; 028c:56        ; 
        glo rc               ; 028d:8c        ; Restore RY value *updated*
        str r7               ; 028e:57        ; 
        sep r4               ; 028f:d4        ; and exit
;
_PRFExit:
        sex rf               ; 0290:ef        ; 
        sep r3               ; 0291:d3        ;
;
;       Sprite utility function
;
PointRFTo:
        ghi r6               ; 0292:96        ; RF.1 := $08
        phi rf               ; 0293:bf        ; 
        glo r7               ; 0294:87        ; D := R7.0 + Next Byte
        sex r3               ; 0295:e3        ; 
        add                  ; 0296:f4        ; 
        plo rf               ; 0297:af        ; RF = $08:(R7.0+Next Byte)
        inc r3               ; 0298:13        ; Skip over the added byte
        br  _PRFExit         ; 0299:30 90     ;
 
_CopyReg:
        ldn r6               ; 029b:06        ; Read x
        str r7               ; 029c:57        ; Store in Y
        sep r4               ; 029d:d4        ; 
;
;               Move Sprite R9 in direction RC R0 times.
;
MoveSpriteR0Times:
        .db     023h,036h                     ; CALL $336 Draw (perhaps remove) sprite
        .db     0E2h                          ; Move Sprite RA in direction RC
        .db     070h,09Eh                     ; Decr R0, if non-zero goto $29E
        .db     0C0h                          ; Return
;
;       Frnn    Extended functions, execute via jump to $02nn
;
Cmd_F:
        lda r5               ; 02a4:45        ; Get the byte
        plo r3               ; 02a5:a3        ; and jump there ($02R3)
;
;       FrA6    Read byte at Memory[Index] to Register
;
CmdF_ReadMemIndex:
        ldn ra               ; 02a6:0a        ; Read byte pointed to by index
        str r6               ; 02a7:56        ; Store in Rx
        sep r4               ; 02a8:d4        ; Return to caller
;
;       FrA9    Write Register to Memory[Index]
;
CmdF_WriteMemIndex:
        ldn r6               ; 02a9:06        ; Read byte
        str ra               ; 02aa:5a        ; Write to Memory[index]
        sep r4               ; 02ab:d4        ; Return
;
;       FrAC    Read byte at Memory[Index] to Register and Increment
;
CmdF_ReadMemIndexBump:
        lda ra               ; 02ac:4a        ; Read byte of mem, bump pointer
        str r6               ; 02ad:56        ; Save in register
        sep r4               ; 02ae:d4        ; Return
;
;       FrAF    Write byte to Memory[Index] and Increment
;
        ldn r6               ; 02af:06        ; Read byte from register
        str ra               ; 02b0:5a        ; Store at Mem[Index]
        inc ra               ; 02b1:1a        ; Inc Index
        sep r4               ; 02b2:d4        ; Next instruction
;
;       FrB3    Set LSB of index to Register
;
        ldn r6               ; 02b3:06        ; Get value in Rx
        plo ra               ; 02b4:aa        ; Put in index low
        sep r4               ; 02b5:d4        ; Next instruction
;
;       FrB6    And Register with 15, or with Index LSB
;
        ldn r6               ; 02b6:06        ; Get value in Rx
        ani 00fh             ; 02b7:fa 0f     ; only 4 bits relevant
        str r6               ; 02b9:56        ; Write it back
        sex r6               ; 02ba:e6        ; access via index
        glo ra               ; 02bb:8a        ; Or with Index LSB
        or                   ; 02bc:f1        ; 
        plo ra               ; 02bd:aa        ; 
        sep r4               ; 02be:d4        ; Next instruction
;
;       Dkaa Scan Keyboard. k = 0..9 the key, F key in RB. If successful
;       RB is set to the key number and the short branch is taken
;
Cmd_Key:
        ldi Carry & 255      ; 02bf:f8 cb     ; R7 = $08CB (RB the carry flag)
        plo r7               ; 02c1:a7        ; 
        glo r6               ; 02c2:86        ; Get k (x register number)
        ani 00fh             ; 02c3:fa 0f     ; 
        plo rf               ; 02c5:af        ; RF.0 = k
        xri 00fh             ; 02c6:fb 0f     ; Check k = $0F ?
        bnz _NotInd          ; 02c8:3a cc     ; if not RF then not direction
        ldn r7               ; 02ca:07        ; If F, read key in RB
        plo rf               ; 02cb:af
_NotInd:
        sex r2               ; 02cc:e2        ; Make space on the stack
        dec r2               ; 02cd:22        ; 
        glo rf               ; 02ce:8f        ; Get the key, normally the k value
        str r2               ; 02cf:52        ; Save it at that location
        out 2                ; 02d0:62        ; Output it and fix R2
        ldi Player & 255     ; 02d1:f8 ca     ; R6 = $08CA (RA)
        plo r6               ; 02d3:a6        ; 
        ldn r6               ; 02d4:06        ; Read $08CA
        bz  _KeyPad2         ; 02d5:32 db     ; if zero read keypad 2
        b3  _KeyPressed      ; 02d7:36 dd     ; if key pressed then handle it
_NoPress:
        inc r5               ; 02d9:15        ; skip 2nd part
        sep r4               ; 02da:d4        ; and exit
_KeyPad2:
        bn4 _NoPress         ; 02db:3f d9     ; if not pressed then skip
_KeyPressed:
        glo rf               ; 02dd:8f        ; Get actual key number
        str r7               ; 02de:57        ; Copy to RB
        br  _ShortBranch     ; 02df:30 e2     ;

_UpdateR:
        str r6               ; 02e1:56        ; Write value back to register
_ShortBranch:
        ldn r5               ; 02e2:05        ; Read second byte
        plo r5               ; 02e3:a5        ; Update Value
        sep r4               ; 02e4:d4        ; Next instruction
;
;       Bcnn Store constant at index and increment
;
Cmd_LCI:
        lda r5               ; 02e5:45        ; Get LSB of instruction
        str ra               ; 02e6:5a        ; Store at Index register
        dec r2               ; 02e7:22        ; Make space on stack
        sex r2               ; 02e8:e2        ; use stack as index
        glo r6               ; 02e9:86        ; get address of Rc
        ani 00fh             ; 02ea:fa 0f     ; get the register number (c)
        str r2               ; 02ec:52        ; store at the stack space
        glo ra               ; 02ed:8a        ; Add c to Index, LSB only
        add                  ; 02ee:f4        ; 
        plo ra               ; 02ef:aa        ; 
        inc r2               ; 02f0:12        ; Fix stack space
        sep r4               ; 02f1:d4        ; Next instruction
;
;       $FxF2 : Clear page, from index value nnn, to n00, index clear on exit
;
CmdF_ClearPage:
        ghi r1               ; 02f2:91        ; D = 0
        str ra               ; 02f3:5a        ; Store at RA
        glo ra               ; 02f4:8a        ; Get Index Low
        dec ra               ; 02f5:2a        ; Decrement it
        bnz 002f2h           ; 02f6:3a f2     ; If non-zero loop back
        sep r4               ; 02f8:d4        ; 

; *****************************************************************************
;
;       Interpreted code subroutine. Does a short beep, and delays
;       for approximately 1/5 second
;
; *****************************************************************************

        .db     06Dh,002h                     ; RD := $02 (Sound Timer)   [6D02]
        .db     06Eh,00Ah                     ; RE := $0A (General Timer) [6E0A]
_IntWait:
        .db     03Eh,(_IntWait & 255)         ; JZ RE,_IntWait            [3EFD]
        .db     0C0h                          ; RET [C0xx]

.end

