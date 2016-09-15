//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Cpu.H
//      Purpose:    1802 Processor Emulation Header
//      Author:     Paul Robson
//      Date:       24th February 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#ifndef _CPU_H
#define _CPU_H

#include "general.h"

BYTE8 CPU_Execute();
void CPU_Reset();
BYTE8  CPU_ReadMemory(WORD16 address);
void CPU_WriteMemory(WORD16 address,BYTE8 data);
BYTE8 *CPU_GetScreenMemoryAddress();
WORD16 CPU_ReadProgramCounter();
BYTE8 CPU_GetScreenScrollOffset();
void CPU_LoadBinaryImage(char *fileName);

#ifdef CPUSTATECODE

typedef struct _CPU1802_STATE
{
    int D,DF,X,P,T,IE,Q,R[16];
    int Cycles,State;
} CPU1802STATE;

CPU1802STATE *CPU_ReadState(CPU1802STATE *s);

#endif

#endif // _CPU_H



