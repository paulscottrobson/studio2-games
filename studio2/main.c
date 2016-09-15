//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Main.C
//      Purpose:    Main program.
//      Author:     Paul Robson
//      Date:       28th February 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "general.h"
#include "cpu.h"
#include "hardware.h"
#include "debug.h"

//*******************************************************************************************************
//                                              Main Program
//*******************************************************************************************************

int main(int argc,char *argv[])
{
    BOOL quit = FALSE;
    IF_Initialise();                                                                    // Initialise the hardware
    DBG_Reset();
    if (argc == 2) CPU_LoadBinaryImage(argv[1]);
    while (!quit)                                                                       // Keep running till finished.
    {
        DBG_Execute();
        quit = IF_Render(TRUE);
    }
    IF_Terminate();
    return 0;
}
