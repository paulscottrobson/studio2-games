//*******************************************************************************************************
//*******************************************************************************************************
//
//      Name:       Hardware.C
//      Purpose:    Hardware Interface Layer
//      Author:     Paul Robson
//      Date:       28th July 2012
//
//*******************************************************************************************************
//*******************************************************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "hardware.h"

#include <SDL.h>

#include "font.h"                                                                       // 5 x 7 font data.

//#define SOUND                                                                           // Sound on.
#define BEEPFREQUENCY   (625)

static SDL_Window *window;
static SDL_Surface *screen;                                                             // Screen used for rendering
static BOOL keyStatus[128];                                                             // Status of Keys.
static BOOL isSoundOn = FALSE;                                                          // Sound status.
static int cyclePos;                                                                    // Position in wave cycle.

static SDL_Keycode keyConvert[] = {                                                     // Known keyboard keys.
    SDLK_0,SDLK_1,SDLK_2,SDLK_3,SDLK_4,SDLK_5,SDLK_6,SDLK_7,                            // 0-9 : 0-9
    SDLK_8,SDLK_9,SDLK_a,SDLK_b,SDLK_c,SDLK_d,SDLK_e,SDLK_f,                            // 10-35 : A-Z
    SDLK_g,SDLK_h,SDLK_i,SDLK_j,SDLK_k,SDLK_l,SDLK_m,SDLK_n,
    SDLK_o,SDLK_p,SDLK_q,SDLK_r,SDLK_s,SDLK_t,SDLK_u,SDLK_v,
    SDLK_w,SDLK_x,SDLK_y,SDLK_z,SDLK_RSHIFT,SDLK_LSHIFT                                 // 36,37 shift keys.
};

static void audioCallback(void *_beeper, Uint8 *_stream, int _length);

//*******************************************************************************************************
//                          Initialise the Interface Layer
//*******************************************************************************************************

#define WIDTH   (1024)
#define HEIGHT  (768)

void IF_Initialise(void)
{
    int i;
    if (SDL_Init(SDL_INIT_VIDEO||SDL_INIT_AUDIO)<0)                                     // Initialise SDL
        exit(printf( "Unable to init SDL: %s\n", SDL_GetError() ));
    atexit(IF_Terminate);                                                               // Call terminate on the way out.

    window = SDL_CreateWindow("RCA Studio II Emulator", SDL_WINDOWPOS_UNDEFINED,        // Try to create a window
                            SDL_WINDOWPOS_UNDEFINED, WIDTH,HEIGHT, SDL_WINDOW_SHOWN );
    if (window == NULL)
        exit(printf("Unable to set video: %s\n", SDL_GetError()));
    screen = SDL_GetWindowSurface(window);
    for (i = 0; i < 128; i++) keyStatus[i] = FALSE;                                     // Reset all key statuses.
    #ifdef SOUND
    SDL_AudioSpec desiredSpec;                                                          // Create an SDL Audio Specification.
    desiredSpec.freq = 44100;
    desiredSpec.format = AUDIO_S16SYS;
    desiredSpec.channels = 1;
    desiredSpec.samples = 2048;
    desiredSpec.callback = audioCallback;
    SDL_AudioSpec obtainedSpec;                                                         // Request the specification.
    SDL_OpenAudio(&desiredSpec, &obtainedSpec);
    isSoundOn = FALSE;
    IF_SetSound(FALSE);                                                                 // Sound off.
    #endif
}

//*******************************************************************************************************
//                      Render the interface layer - in debug mode, or not
//*******************************************************************************************************

BOOL IF_Render(BOOL debugMode)
{
    int i;
    SDL_Keycode key;
    SDL_Event event;
    BOOL quit = FALSE;
    while(SDL_PollEvent(&event))                                                        // Empty the event queue.
    {
        if (event.type == SDL_KEYUP || event.type == SDL_KEYDOWN)                       // Is it a key event
        {
            key = event.key.keysym.sym;                                                 // This is the SDL Key Code

            for (i = 0;i < sizeof(keyConvert)/sizeof(SDL_Keycode);i++)                  // Scan through known keys
                if (key == keyConvert[i])                                               // If found
                    keyStatus[i < 10 ? i+'0':i-10+'A'] = (event.type == SDL_KEYDOWN);   // Update status.
            if (key == SDLK_ESCAPE)                                                     // Esc key ends program.
                                quit = TRUE;

        } // end switch
    } // end of message processing

    SDL_UpdateWindowSurface(window);                                                    // Flip screens
    SDL_FillRect(screen, 0, SDL_MapRGB(screen->format, 0, 0, 64));                      // Erase for next time.
    return quit;
}

//*******************************************************************************************************
//                      Write Character to screen square (x,y) - 32 x 24
//*******************************************************************************************************

void IF_Write(int x,int y,char ch,int colour)
{
    int xCSize = screen->w / 32;                                                        // Work out character box size.
    int yCSize = screen->h / 24;
    SDL_Rect rc;
    rc.x = xCSize * x;rc.y = yCSize * y;                                                // Erase character background.
    rc.w = xCSize;rc.h = yCSize;
    SDL_FillRect(screen,&rc,SDL_MapRGB(screen->format,0,0,64));
    if (ch <= ' ' || ch > 127) return;                                                  // Don't render control and space.
    unsigned char *byteData = fontdata + (int)((ch - ' ') * 5);                         // point to the font data
    int xp,yp,pixel;
    rc.w = xCSize * 16 / 100;                                                           // Work out pixel sizes
    rc.h = yCSize * 14 / 100;
    Uint32 fgr = SDL_MapRGB(screen->format,                                             // Foreground colour.
                    (colour & 1) ? 255:0,(colour & 2) ? 255:0,(colour & 4) ? 255:0);
    for (xp = 0;xp < 5;xp++)                                                            // Font data is stored vertically
    {
        rc.x = xp * rc.w + x * xCSize;                                                  // Horizontal value
        pixel = *byteData++;                                                            // Pixel data for vertical line.
        for (yp = 0;yp < 7;yp++)                                                        // Work through pixels.
        {
            if (pixel & (1 << yp))                                                      // Bit 0 is the top pixel, if set.
            {
                rc.y = yp * rc.h + y * yCSize;                                          // Vertical value
                SDL_FillRect(screen,&rc,fgr);                                           // Draw Cell.
            }
        }
    }
}

//*******************************************************************************************************
//                              Terminate the interface layer
//*******************************************************************************************************

void IF_Terminate(void)
{
    SDL_Quit();
}

//*******************************************************************************************************
//                              Check to see if a key is pressed
//*******************************************************************************************************

BOOL IF_KeyPressed(char ch)
{
    return keyStatus[toupper(ch)];
}

//*******************************************************************************************************
//                               Check to see if SHIFT is pressed.
//*******************************************************************************************************

BOOL IF_ShiftPressed(void)
{
    return keyStatus['Z'+1] || keyStatus['Z'+2];
}

//*******************************************************************************************************
//                                 Display the pixel screen
//*******************************************************************************************************

void IF_DisplayScreen(BOOL isDebugMode,BYTE8 *screenData,BYTE8 scrollOffset)
{
    int xc,yc,xs,ys,x,y,pixByte;
    SDL_Rect rc;
    xc = 0;yc = 0;xs = screen->w / 64;ys = screen->h / 32;                              // Main display.
    if (isDebugMode)                                                                    // Debug display.
    {
        xc = screen->w*24/32;yc = 0;xs =(screen->w-xc)/64;ys = screen->h*6/24/32;       // Make it fit in space.
    }
    rc.x = xc;rc.y = yc;rc.w = xs * 64;rc.h = ys*32;                                    // Erase screen display
    SDL_FillRect(screen,&rc,SDL_MapRGB(screen->format,0,0,0));
    if (screenData == NULL) return;                                                     // Screen off, exit.
    Uint32 fgr = SDL_MapRGB(screen->format,255,255,255);                                // Painting colour.
    rc.w = xs;rc.h = ys;                                                                // Set cell width and height
    if (isDebugMode) rc.w--,rc.h--;                                                     // Debug mode show individual cells.
    for (y = 0;y < 32;y++)                                                              // One line at a time.
    {
        BYTE8 *pixels = screenData + ((y * 8 + scrollOffset) & 0xFF);                   // Work out where data comes from.
        rc.y = yc + ys * y;                                                             // Calculate vertical coordinate
        for (x = 0;x < 8;x++)                                                           // 8 bytes per line.
        {
            pixByte = *pixels++;                                                        // Get next pixel.
            rc.x = xc + x * xs * 8;                                                     // Calculate horizontal coordinate
            while (pixByte != 0)                                                        // if something to render.
            {
                if (pixByte & 0x80) SDL_FillRect(screen,&rc,fgr);                       // if bit 7 set draw pixel
                pixByte = (pixByte << 1) & 0xFF;                                        // shift to left, lose overflow.
                rc.x = rc.x + xs;                                                       // next coordinate across.
            }
        }

    }
}

//*******************************************************************************************************
//                                    Control sound.
//*******************************************************************************************************

void IF_SetSound(BOOL isOn)
{
    if (isSoundOn == isOn) return;                                                      // No status change.
    isSoundOn = isOn;                                                                   // Update status
    #ifdef SOUND
    SDL_PauseAudio(isOn == 0);                                                          // If sound built in, turn on/off.
    #endif
}

//*******************************************************************************************************
//                              Audio Callback Function
//*******************************************************************************************************

static void audioCallback(void *_beeper, Uint8 *_stream, int _length)
{
    Sint16 *stream = (Sint16*) _stream;                                                 // Pointer to audio data
    int length = _length / 2;                                                           // Length of audio data
    int i;
    for (i = 0;i < length;i++)                                                          // Fill buffer with data
    {
        stream[i] = (cyclePos > 22050 ? -32767:32767);                                  // Square Wave - it's a 555
        cyclePos = (cyclePos + BEEPFREQUENCY) % 44100;                                  // Note the CCT Resistors (470R and 1M) must be wrong !
    }
}

//*******************************************************************************************************
//                  Get Tick Timer - needs about a 20Hz minimum granularity.
//*******************************************************************************************************

int IF_GetTime(void)
{
    return SDL_GetTicks();
}
