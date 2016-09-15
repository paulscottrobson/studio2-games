//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Hardware.H
//      Purpose:    Hardware Interface Headers
//      Author:     Paul Robson
//      Date:       28th July 2012
//
//*******************************************************************************************************
//*******************************************************************************************************

#include "general.h"

#ifndef _HARDWARE_H
#define _HARDWARE_H

void IF_Initialise(void);
BOOL IF_Render(BOOL debugMode);
void IF_Terminate(void);
void IF_Write(int x,int y,char ch,int colour);
BOOL IF_KeyPressed(char ch);
BOOL IF_ShiftPressed(void);
void IF_DisplayScreen(BOOL isDebugMode,BYTE8 *screenData,BYTE8 scrollOffset);
void IF_SetSound(BOOL isOn);
int IF_GetTime(void);

#endif
