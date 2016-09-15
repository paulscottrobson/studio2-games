//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Debug.C
//      Purpose:    Debugger
//      Author:     Paul Robson
//      Date:       28th February 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include "general.h"
#include "hardware.h"
#include "debugscreen.h"
#include "debug.h"
#include "cpu.h"

static BOOL inDebugMode = TRUE;                                                     // True if in debugger mode
static int  programPointer;                                                         // Displayed code
static int  dataPointer;                                                            // Displayed data
static int  breakPoint;                                                             // Current break
static int  lastKey;                                                                // Last key status

static void DBG_KeyCommand(char cmd);

//*******************************************************************************************************
//                                          Full System Reset
//*******************************************************************************************************

void DBG_Reset()
{
    CPU_Reset();                                                                    // Reset CPU define RAM.
    inDebugMode = TRUE;                                                             // Start in Debug Mode
    programPointer = 0x0000;                                                        // Start point
    dataPointer = 0x0800;                                                           // Data at $0000
    breakPoint = 0xFFFF;                                                            // Break off (effectively)
}

//*******************************************************************************************************
//                                              Main Execution
//*******************************************************************************************************

void DBG_Execute()
{
    if (inDebugMode)                                                                // Debug mode
    {
        int i,currentKey = -1;
        for (i = ' ';i <= 'Z';i++)                                                  // Get current key pressed
        {
            if (IF_KeyPressed(i)) currentKey = i;
        }
        if (currentKey != lastKey && currentKey != -1)                              // If key changed and one pressed
            DBG_KeyCommand(currentKey);                                             // Execute it.
        lastKey = currentKey;
        DBG_Draw(programPointer,dataPointer,breakPoint);                            // Update display
    }
    else                                                                            // Run mode
    {
        while (CPU_Execute() != 1 && CPU_ReadProgramCounter() != breakPoint)        // Execute till end of frame or break
        {
        }
        if (IF_KeyPressed('B') || CPU_ReadProgramCounter() == breakPoint)           // M or break returns to debug mode
        {
            inDebugMode = TRUE;
            programPointer = CPU_ReadProgramCounter();                              // Program pointer at R[P]
        }
        if (IF_KeyPressed('P'))                                                     // P is reset
        {
            DBG_Reset();
            inDebugMode = FALSE;
        }
        IF_DisplayScreen(FALSE,                                                     // Update display
                            CPU_GetScreenMemoryAddress(),CPU_GetScreenScrollOffset());
    }
}

//*******************************************************************************************************
//                                          Handle Debug Commands
//*******************************************************************************************************

static void DBG_KeyCommand(char cmd)
{
    if (isxdigit(cmd))                                                              // Hexadecimal character
    {
        int *p = (IF_ShiftPressed()) ? &dataPointer:&programPointer;                // If shift, change data, otherwise change pgm
        int n = (cmd >= 'A') ? cmd - 'A'+10 : cmd - '0';                            // Convert char to decimal
        *p = ((*p << 4) | n) & 0xFFFF;                                              // Adjust the selected pointer
    }
    else
    {
        int opcode;
        CPU1802STATE s;                                                             // Read CPU State
        CPU_ReadState(&s);
        switch(cmd)
        {
            case 'P':   DBG_Reset();                                                // P : Reset
                        break;
            case 'K':   breakPoint = programPointer;                                // K : Set Breakpoint
                        break;
            case 'H':   programPointer = s.R[s.P];                                  // H : Display code at R[P]
                        break;
            case 'X':   dataPointer = s.R[s.X];                                     // X : Display data at R[X]
                        break;
            case 'S':   CPU_Execute();                                              // S : Single step
                        CPU_ReadState(&s);
                        programPointer = s.R[s.P];
                        break;
            case 'G':   inDebugMode = FALSE;                                        // G : Run
                        break;
            case 'V':   opcode = CPU_ReadMemory(s.R[s.P]);                          // V : Step over
                        if ((opcode & 0xF0) == 0xD0)                                // if SEP R?
                        {
                            inDebugMode = FALSE;                                    // Run with break at R[P]+1
                            breakPoint = (s.R[s.P]+1) & 0xFFFF;
                        }
                        else                                                        // otherwise same as normal single step
                        {
                            CPU_Execute();
                            CPU_ReadState(&s);
                            programPointer = s.R[s.P];
                        }
                        break;
        }
    }
}
