// *****************************************************************************************************************
// *****************************************************************************************************************
//
//								    	   Arduino version of Studio 2
//										   ===========================
//
//										 Written by Paul Robson March 2013
//
//	Note:	this requires the TVout1802 library which is a significantly modified version of "TVout"
//
//	Component List:
//
//			1 x Arduino Duemonalive/Uno or equivalent (Leonardo does not work as yet)
//			1 x 470R Resistor
// 			1 x 1k Resistor
// 			2 x 3x4 Keypads
//			1 x Piezo Buzzer
//			A composite video plug/socket to connect to display equipment.
//			Something to construct it on
//
// *****************************************************************************************************************
// *****************************************************************************************************************

#include "cpu.h"																	// Includes
#include <TVout1802.h>
#include <avr/pgmspace.h>

#define ARDUINO_VERSION 															// Conditional Compile (read pgm mem etc.)

#define TONEPIN		(11)															// Same pin as in TV1802/spec/hardware_setup.h

//
//	The beeper bin is determined by the TVout1802 file spec/hardware_setup.h - if you look here and go down to the "328"
//	section you'll see this is set to B3 which is what the AVR knows Arduino Pin 11 as. http://arduino.cc/en/Hacking/PinMapping168
//
//	The keypad connections are determined by rowpins and colpins further down. Using a stock keypad (123A/456B) that is commonly 
//	available the columns are the first four pins holding it upright, the rows the last four hence 0,1,2,3,4,5,6,8
//
//	On a standard 3 x 4 keyboard (123/456/789/*0#)  Left->Right with two 'border' pins.
//		1 		2 		3 		4 		5 		6 		7
//	   Col1    Row0    Col0    Row3    Col2    Row2    Row1
//
//	This is for these sorts of keypads http://www.acroname.com/robotics/parts/R257-3X4-KEYPAD.jpg (example) which appear to be
//	available from virtually all electronic suppliers.
//
//	Pin 7 is used for VideoOut by TVout1802 which is why the keyboard isn't connected to pins 0-7.
//	Pin 9 is used for the VideoSync.
//
																					
TVout1802 TV;																		// TVOut object modified for 64x32 display.

#include "cpu.c"																	// The 1802 CPU / Hardware code

// *****************************************************************************************************************
//										          Keypad configuration
// *****************************************************************************************************************

const byte rows = 4; 																// four rows
const byte cols = 3; 																// three columns

byte keyLoc[10][2] = {  { 3,1 }, 													// Keypad locations 0-9
					    { 0,0 }, { 0,1 }, { 0,2 },						
					 	{ 1,0 }, { 1,1 }, { 1,2 }, 
					 	{ 2,0 }, { 2,1 }, { 2,2 }  };

byte isPressed[16] = { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 };							// Flags for each key pressed.

byte rowPins[rows] = { 1,6,5,3 }; 													// connect to the row pinouts of the keypad
byte colPins[cols] = { 2,0,4 }; 													// connect to the column pinouts of the keypad

// *****************************************************************************************************************
//										  Check if all keys are pressed
// *****************************************************************************************************************

void CheckAllKeys() 
{
	for (byte r = 0; r < rows; r++) pinMode(rowPins[r],INPUT_PULLUP);				// Set all rows to Input/Pullup
	for (byte key = 0;key < 10;key++)												// Scan all keys.
	{
		byte c;
		for (c = 0; c < cols;c++) pinMode(colPins[c],INPUT);						// Input on all Columns
		c = keyLoc[key][1];															// Get the column to check
		pinMode(colPins[c],OUTPUT);
		digitalWrite(colPins[c], LOW);												// Make it low (as inputs pulled up)
		isPressed[key] = !digitalRead(rowPins[keyLoc[key][0]]);						// Key is pressed if Row 0 is low.
		digitalWrite(colPins[c],HIGH);												// Set it back to high
	}
}

// *****************************************************************************************************************
//												Hardware Interface
// *****************************************************************************************************************

static BYTE8 toneState = 0;															// Tone currently on/off ?
static BYTE8 toneTimer; 															// No of syncs tone has been on.

static BYTE8 selectedKeypad = 1;													// Currently selected keypad

BYTE8 SYSTEM_Command(BYTE8 cmd,BYTE8 param)
{
	BYTE8 retVal = 0;
	switch(cmd)
	{
		case  HWC_READKEYBOARD:														// Read the keypad 
			retVal = isPressed[param & 0x0F];										// I only have one keypad so shared for S2
			break;    

		case  HWC_UPDATEQ:             
			if (param != toneState) 												// Has it changed state ?
			{
				toneState = param;													// If so save new state
				if (toneState != 0) TV.tone(625); else TV.noTone();					// and set the beeper accordingly.
				toneTimer = 0;
			} 																		// 2,945 Hz is from CCT Diagram values on
			break;    																// NE555V in RCA Cosmac VIP.

		case  HWC_FRAMESYNC:
			setDisplayPointer(CPU_GetScreenMemoryAddress());						// Set the display pointer to "whatever it is"
			setScrollOffset(CPU_GetScreenScrollOffset());							// Set the current scrolling offset.
			if (toneState != 0 && toneTimer != 25) 
			{
				toneTimer++;
				if ((toneTimer & 1) == 0) TV.tone(625-toneTimer*4);
			}
			CheckAllKeys();															// Rescan the keyboard.
			break;    

		case HWC_SETKEYPAD:															// Studio 2 has two keypads, this chooses the
			selectedKeypad = param;													// currently selected one (for HWC_READKEYBOARD)
			break;																	// Not fully implemented here :)
	}
	return retVal;
}

// *****************************************************************************************************************
//									Generated PROGMEM data for uploading into RAM
// *****************************************************************************************************************

void setup() 
{
	CheckAllKeys();																	// Copy state of keys into isPressed[]
  	TV.begin(NTSC,8,2);																// Initialise TVout (8,2) smallest working size
  	CPU_Reset();																	// Initialise CPU
}

// *****************************************************************************************************************
//															Main loop
// *****************************************************************************************************************

void loop() 
{
  	CPU_Execute();
}

