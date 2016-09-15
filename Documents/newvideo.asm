; *****************************************************************************
;
;               Code to patch in the new Video Interrupt
;
; *****************************************************************************

        ldi     $FF             ; set R9.0 to $FF.
        plo     r9              ; after this instruction R9.1 will be $FF, or $00 if INT occurred.

WaitForInterruptToPatch:
        glo     r9              ; r9 is incremented by the S2 BIOS, so when this is zero INT has just occurred
        bz      WaitForInterruptToPatch

        ldi     >VideoNew       ; update the IRQ handler address, because INT won't happen for another frame.
        phi     r1              ; so you can't get an INT when it has half changed.
        ldi     <VideoNew
        plo     r1

        (code continues)

; *****************************************************************************
;
;       New Studio 2 Video Interrupt. Based on the routine at $001C
;
;       This routine is entirely non-destructive. Obviously you cannot use
;       R1 (IRQ routine)     r2 (stack). Uses 5 bytes of stack space
;       
;       Changes:
;               1. Pushes r0 on the stack so r0 is available for use.
;               2. Does nothing else at all at present, no counters etc.
;               3. Does NOT push DF on the stack, so Arithmetic instructions are
;                  unavailable.
;               4. No scrolling, can be done by replacing ldi $00 with glo rb
;
;       So you can now use : R0, R8, R9 and three timers at $8CD/E/F 
;       $8CD = beeper
;       
; *****************************************************************************

VideoNew:
        dec     r2              ; Save (X,P) at r2-1    [2,2]
        sav                     ;                       [2,4]
        dec     r2              ; Save D at r2-1        [2,6]
        stxd                    ;                       [2,8]
        glo     r0              ; Save r0.L at r2-1     [2,10]
        stxd                    ;                       [2,12]
        ghi     r0              ; Save r0.H at r2-1     [2,14]
        stxd                    ;                       [2,16]
        ldi     $09             ; Set r0.HL = $0900     [2,18]
        phi     r0              ;                       [2,20]
        ldi     $00             ;                       [2,22]
        plo     r0              ;                       [2,24]
        nop                     ; now waste cycles      [3,27]
        sex     r2              ; this too.             [2,29] 

                                ; D & r0.0 now point to the first row here $900.
                                ; this next section is copied from the BIOS disassembly.
        ; ==== DMA OUT ====
        sex     r2              ; R0.0 now $0908
VideoRefresh:
        dec     r0               
        plo     r0              ; Fix r0.0 back to start of row
        ; ==== DMA OUT ====
        sex     r2               
        dec     r0                 
        plo     r0              ; Fix r0.0 back to start of row
        ; ==== DMA OUT ====
        sex     r2              
        dec     r0              
        plo     r0              ; Fix r0.0 back to start of row
        ; ==== DMA OUT ====
        glo     r0              ; glo r0 makes D next row.
        dec     r0              
        plo     r0              
        ; ==== DMA OUT ====
        bn1     VideoRefresh    ; Not end of this frame (e.g. 32 times round)

                                ; wait for EF1 to go high removed.
                                ; per frame code goes here - push and restore DF if you use it.

        lda     r2              ; restore r0.1, r0.0 
        phi     r0
        lda     r2
        plo     r0
        lda     r2              ; restore D
        ret                     ; and return to caller.

;
;       Non destructive counter code.
;
        shlc                    ; DF -> D bit 0
        stxd                    ; save on stack

        ldi     $8              ; set R0 to $804
        phi     r0
        ldi     $4
        plo     r0
        ldn     r0              ; read $804
        bz      NoTimer1        ; if zero, skip it.
        smi     1               ; otherwise subtract 1 and write back
        str     r0
NoTimer1:
        ..
        ..
        lda     r2              ; pop D bit 0 off stack
        shr                     ; shift into DF

