//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       DebugScreen.C
//      Purpose:    Debug Screen Display
//      Author:     Paul Robson
//      Date:       27th February 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "general.h"
#include "cpu.h"
#include "hardware.h"
#include "mnemonics1802.h"

static void DBG_PrintString(int x,int y,char *text,int fgr);
static void DBG_PrintHex(int x,int y,int n,int fgr,int w);

//*******************************************************************************************************
//                                      Draw the debugger screen
//*******************************************************************************************************

void DBG_Draw(int programPointer,int dataPointer,int breakPoint)
{
    char *labels[] = { "D","DF","P","RP","X","RX","MX","Q","IE","T",NULL };
    int i = 0;
    while (labels[i] != NULL)
    {
        DBG_PrintString(15,i,labels[i],2);
        i++;
    }
    DBG_PrintString(24,7,"BP",2);
    DBG_PrintString(24,8,"CY",2);
    DBG_PrintString(24,9,"ST",2);

    CPU1802STATE s;
    CPU_ReadState(&s);
    i = 0;
    DBG_PrintHex(18,i++,s.D,3,2);DBG_PrintHex(18,i++,s.DF,3,1);DBG_PrintHex(18,i++,s.P,3,1);
    DBG_PrintHex(18,i++,s.R[s.P],3,4);DBG_PrintHex(18,i++,s.X,3,1);DBG_PrintHex(18,i++,s.R[s.X],3,4);
    DBG_PrintHex(18,i++,CPU_ReadMemory(s.R[s.X]),3,2);DBG_PrintHex(18,i++,s.Q,3,1);DBG_PrintHex(18,i++,s.IE,3,1);
    DBG_PrintHex(18,i++,s.T,3,2);
    i = 7;
    DBG_PrintHex(27,i++,breakPoint,3,4);DBG_PrintHex(27,i++,s.Cycles,3,4);DBG_PrintHex(27,i++,s.State,3,1);
    for (i = 0;i < 16;i++)
    {
        DBG_PrintString(i%4*8,i/4+11,"R",2);
        DBG_PrintHex(i%4*8+1,i/4+11,i,2,1);
        DBG_PrintHex(i%4*8+3,i/4+11,s.R[i],3,4);
    }
    for (i = 0;i < 8;i++)
        DBG_PrintHex(1,i+16,(dataPointer+i*8) & 0xFFFF,2,4);
    for (i = 0;i < 64;i++)
        DBG_PrintHex(i % 8 * 3 + 7,i/8+16,CPU_ReadMemory((i+dataPointer) & 0xFFFF),3,2);

    i = 0;
    while (i < 10)
    {
        char buffer[32];
        int isHome = (programPointer == s.R[s.P]);
        DBG_PrintHex(0,i,programPointer,isHome ? 3 : 2,4);
        if (programPointer == breakPoint) DBG_PrintString(4,i,"*",6);
        strcpy(buffer,_mnemonics[CPU_ReadMemory(programPointer++)]);
        if (buffer[strlen(buffer)-2] == '.')
        {
            if (buffer[strlen(buffer)-1] == '1')
            {
                sprintf(buffer+strlen(buffer)-2,"%02x",CPU_ReadMemory(programPointer));
                programPointer = (programPointer+1) & 0xFFFF;
            }
            else
            {
                sprintf(buffer+strlen(buffer)-2,"%02x%02x",CPU_ReadMemory(programPointer),CPU_ReadMemory((programPointer+1) & 0xFFFF));
                programPointer = (programPointer+2) & 0xFFFF;
            }
        }
        programPointer = programPointer & 0xFFFF;
        DBG_PrintString(5,i,buffer,isHome ? 3 : 2);
        i++;
    }
    IF_DisplayScreen(TRUE,CPU_GetScreenMemoryAddress(),CPU_GetScreenScrollOffset());
}

//*******************************************************************************************************
//                                          Print a string
//*******************************************************************************************************

static void DBG_PrintString(int x,int y,char *text,int fgr)
{
    while (*text != '\0')
    {
        IF_Write(x++,y,*text++,fgr);
    }
}

//*******************************************************************************************************
//                                  Print a hexadecimal constant
//*******************************************************************************************************

static void DBG_PrintHex(int x,int y,int n,int fgr,int w)
{
    char buffer[8];
    sprintf(buffer,"%0*x",w,n);
    DBG_PrintString(x,y,buffer,fgr);
}
