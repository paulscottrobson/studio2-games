//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       General.H
//      Purpose:    General Constants, Includes
//      Author:     Paul Robson
//      Date:       24th Feb 2013
//
//*******************************************************************************************************
//*******************************************************************************************************

#ifndef _GENERAL_H
#define _GENERAL_H

typedef unsigned char BOOL;
typedef unsigned char BYTE8;                                                        // Type definitions used in CPU Emulation
typedef unsigned short WORD16;
typedef signed short INT16;

#define FALSE       (0)                                                             // Boolean type
#define TRUE        (!(FALSE))

#ifndef ARDUINO_VERSION                                                             // The arduino version doesn't need the CPU state
#define CPUSTATECODE                                                                // access stuff, which is for the debugger.
#endif

#endif



