//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Cpu.C
//      Purpose:    1802 Processor Emulation
//      Author:     Paul Robson
//      Date:       24th February 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#include <stdio.h>
#include <stdlib.h>
#include "general.h"
#include "cpu.h"
#include "system.h"

#include "macros1802.h"

#define CLOCK_SPEED             (3521280/2)                                         // Clock Frequency (1,760,640Hz)
#define CYCLES_PER_SECOND       (CLOCK_SPEED/8)                                     // There are 8 clocks in each cycle (220,080 Cycles/Second)
#define FRAMES_PER_SECOND       (60)                                                // NTSC Frames Per Second
#define LINES_PER_FRAME         (262)                                               // Lines Per NTSC Frame
#define CYCLES_PER_FRAME        (CYCLES_PER_SECOND/FRAMES_PER_SECOND)               // Cycles per Frame, Complete (3668)
#define CYCLES_PER_LINE         (CYCLES_PER_FRAME/LINES_PER_FRAME)                  // Cycles per Display Line (14)

#define VISIBLE_LINES           (128)                                               // 128 visible lines per frame
#define NON_DISPLAY_LINES       (LINES_PER_FRAME-VISIBLE_LINES)                     // Number of non-display lines per frame. (134)
#define EXEC_CYCLES_PER_FRAME   (NON_DISPLAY_LINES*CYCLES_PER_LINE)                 // Cycles where 1802 not generating video per frame (1876)

// Note: this means that there are 1876*60/2 approximately instructions per second, about 56,280. With an instruction rate of
// approx 8m per second, this means each instruction is limited to 8,000,000 / 56,280 * (128/312.5) about 58 AVR instructions for each
// 1802 instructions.

// State 1 : 1876 cycles till interrupt N1 = 0
// State 2 : 29 cycles with N1 = 1

#define STATE_1_CYCLES          (EXEC_CYCLES_PER_FRAME)
#define STATE_2_CYCLES          (29)

static BYTE8 D,X,P,T;                                                               // 1802 8 bit registers
static BYTE8 DF,IE,Q;                                                               // 1802 1 bit registers
static WORD16 R[16];                                                                // 1802 16 bit registers
static WORD16 _temp;                                                                // Temporary register
static INT16 Cycles;                                                                // Cycles till state switch
static BYTE8 State;                                                                 // Frame position state (NOT 1802 internal state)
static BYTE8 *screenMemory = NULL;                                                  // Current Screen Pointer (NULL = off)
static BYTE8 scrollOffset;                                                          // Vertical scroll offset e.g. R0 = $nnXX at 29 cycles
static BYTE8 screenEnabled;                                                         // Screen on (IN 1 on, OUT 1 off)
static BYTE8 keyboardLatch;                                                         // Value stored in Keyboard Select Latch (Studio 2)

#ifdef ARDUINO_VERSION
static BYTE8 studio2RAM[512] __attribute__ ((section (".noinit")));                 // Studio 2's internal RAM (ONLY)
#else
static BYTE8 studio24k[4096];                                                       // otherwise the whole 4k.
#endif

//*******************************************************************************************************
//                                      Load Binary image
//*******************************************************************************************************

#ifndef ARDUINO_VERSION
void CPU_LoadBinaryImage(char *fileName)
{
    FILE *f = fopen(fileName,"rb");
    int address = 0x400;
    while (!feof(f))
    {
        BYTE8 b = fgetc(f);
        if (address < 0x800 || address >= 0xA00) studio24k[address] = b;
        address++;
    }
    fclose(f);
}
#endif

//*******************************************************************************************************
//                                 Macros to Read/Write memory
//*******************************************************************************************************

#define READ(a)     CPU_ReadMemory(a)
#define WRITE(a,d)  CPU_WriteMemory(a,d)

//*******************************************************************************************************
//   Macros for fetching 1 + 2 BYTE8 operands, Note 2 BYTE8 fetch stores in _temp, 1 BYTE8 returns value
//*******************************************************************************************************

#define FETCH2()    (CPU_ReadMemory(R[P]++))
#define FETCH3()    { _temp = CPU_ReadMemory(R[P]++);_temp = (_temp << 8) | CPU_ReadMemory(R[P]++); }

//*******************************************************************************************************
//                      Macros translating Hardware I/O to hardwareHandler calls
//*******************************************************************************************************

#define READEFLAG(n)    CPU_ReadEFlag(n)
#define UPDATEIO(p,d)   CPU_OutputHandler(p,d)
#define INPUTIO(p)      CPU_InputHandler(p)

static BYTE8 CPU_ReadEFlag(BYTE8 flag)
{
    BYTE8 retVal = 0;
    switch (flag)
    {
        case 1:                                                                     // EF1 detects not in display
            retVal = 1;                                                             // Permanently set to '1' so BN1 in interrupts always fails
            break;
        case 3:                                                                     // EF3 detects keypressed on VIP and Elf but differently.
            SYSTEM_Command(HWC_SETKEYPAD,1);
            retVal = SYSTEM_Command(HWC_READKEYBOARD,keyboardLatch);
            break;
        case 4:                                                                     // EF4 is !IN Button
            SYSTEM_Command(HWC_SETKEYPAD,2);
            retVal = SYSTEM_Command(HWC_READKEYBOARD,keyboardLatch);
            break;
    }
    return retVal;
}

static BYTE8 CPU_InputHandler(BYTE8 portID)
{
    BYTE8 retVal = 0;
    switch (portID)
    {
        case 1:                                                                     // IN 1 turns the display on.
            screenEnabled = TRUE;
            break;
    }
    return retVal;
}

static void CPU_OutputHandler(BYTE8 portID,BYTE8 data)
{
    switch (portID)
    {
        case 0:                                                                     // Called with 0 to set Q
            SYSTEM_Command(HWC_UPDATEQ,data);                                       // Update Q Flag via HW Handler
            break;
        case 1:                                                                     // OUT 1 turns the display off
            screenEnabled = FALSE;
            break;
        case 2:                                                                     // OUT 2 sets the keyboard latch (both S2 & VIP)
            keyboardLatch = data & 0x0F;                                            // Lower 4 bits only :)
            break;
    }
}

//*******************************************************************************************************
//                                              Monitor ROM
//*******************************************************************************************************

#ifndef ARDUINO_VERSION                                                             // if not Arduino
#define PROGMEM                                                                     // fix usage of PROGMEM and prog_char
#define prog_uchar BYTE8
#endif

#include "studio2_rom.h"

//*******************************************************************************************************
//                          Reset the 1802 and System Handlers
//*******************************************************************************************************

void CPU_Reset()
{
    X = P = Q = R[0] = 0;                                                           // Reset 1802 - Clear X,P,Q,R0
    IE = 1;                                                                         // Set IE to 1
    DF = DF & 1;                                                                    // Make DF a valid value as it is 1-bit.

    State = 1;                                                                      // State 1
    Cycles = STATE_1_CYCLES;                                                        // Run this many cycles.
    screenEnabled = FALSE;

    #ifndef ARDUINO
    int i;                                                                          // PC Version copy code into 4k space.
    for (i = 0;i < 2048;i++) studio24k[i] = _studio2[i];
    #endif
}


//*******************************************************************************************************
//                                        Read a BYTE8 in memory
//*******************************************************************************************************

BYTE8 CPU_ReadMemory(WORD16 address)
{
    address &= 0xFFF;
    #ifdef ARDUINO_VERSION
    if (address < 0x800)
    {
        return pgm_read_byte_near(_studio2+address);
    }
    if (address >= 0x800 && address < 0xA00)
        return studio2RAM[address-0x800];
    return 0xFF;
    #else
    return studio24k[address];
    #endif
}

//*******************************************************************************************************
//                                          Write a BYTE8 in memory
//*******************************************************************************************************

void CPU_WriteMemory(WORD16 address,BYTE8 data)
{
    address = address & 0xFFF;
    if (address >= 0x800 && address < 0xA00)                                    // only RAM space is writeable
    {
        #ifdef ARDUINO_VERSION
        studio2RAM[address-0x800] = data;
        #else
        studio24k[address] = data;
        #endif
    }
}

//*******************************************************************************************************
//                                         Execute one instruction
//*******************************************************************************************************

BYTE8 CPU_Execute()
{
    BYTE8 rState = 0;
    BYTE8 opCode = CPU_ReadMemory(R[P]++);
    Cycles -= 2;                                                                    // 2 x 8 clock Cycles - Fetch and Execute.
    switch(opCode)                                                                  // Execute dependent on the Operation Code
    {
        #include "cpu1802.h"
    }
    if (Cycles < 0)                                                                 // Time for a state switch.
    {
        switch(State)
        {
        case 1:                                                                     // Main Frame State Ends
            State = 2;                                                              // Switch to Interrupt Preliminary state
            Cycles = STATE_2_CYCLES;                                                // The 29 cycles between INT and DMAOUT.
            if (screenEnabled)                                                      // If screen is on
            {
                if (CPU_ReadMemory(R[P]) == 0) R[P]++;                              // Come out of IDL for Interrupt.
                INTERRUPT();                                                        // if IE != 0 generate an interrupt.
            }
            break;
        case 2:                                                                     // Interrupt preliminary ends.
            State = 1;                                                              // Switch to Main Frame State
            Cycles = STATE_1_CYCLES;
            #ifdef ARDUINO_VERSION
            screenMemory = studio2RAM+(R[0] & 0xFF00)-0x800;                        // masking with $FF00
            #else
            screenMemory = studio24k+(R[0] & 0xFF00);                               // space for PC version
            #endif
            scrollOffset = R[0] & 0xFF;                                             // Get the scrolling offset (for things like the car game)
            SYSTEM_Command(HWC_FRAMESYNC,0);                                        // Synchronise.
            break;
        }
        rState = (BYTE8)State;                                                      // Return state as state has switched
        Cycles--;                                                                   // Time out when cycles goes -ve so deduct 1.
    }
    return rState;
}

//*******************************************************************************************************
//                                              Access CPU State
//*******************************************************************************************************

#ifdef CPUSTATECODE

CPU1802STATE *CPU_ReadState(CPU1802STATE *s)
{
    int i;
    s->D = D;s->DF = DF;s->X = X;s->P = P;s->T = T;s->IE = IE;s->Q = Q;
    s->Cycles = Cycles;s->State = State;
    for (i = 0;i < 16;i++) s->R[i] = R[i];
    return s;
}

#endif // CPUSTATECODE

//*******************************************************************************************************
//                         Get Current Screen Memory Base Address (ignoring scrolling)
//*******************************************************************************************************

BYTE8 *CPU_GetScreenMemoryAddress()
{
    if (scrollOffset != 0)
    {
        scrollOffset *= 1;
    }
    return (screenEnabled != 0) ? (BYTE8 *)screenMemory : NULL;
}

//*******************************************************************************************************
//                               Get Current Screen Memory Scrolling Offset
//*******************************************************************************************************

BYTE8 CPU_GetScreenScrollOffset()
{
    return scrollOffset;
}

//*******************************************************************************************************
//                                        Get Program Counter value
//*******************************************************************************************************

WORD16 CPU_ReadProgramCounter()
{
    return R[P];
}
