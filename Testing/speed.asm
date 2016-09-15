;
;	speed test program - for the ELF II emulation, also checks hardware is working.
;

	ldi 	start/256						; get away from P=0 to P=3, IRQ breaks P.
	phi 	r3
	ldi 	start%256
	plo 	r3
	sep 	r3

start:
	

	ldi		DisplayRoutine / 256
	phi 	r1
	ldi 	DisplayRoutine % 256
	plo 	r1

	ldi 	1								; $100 is the screen
	phi 	rb
	ldi 	0
	plo 	rb
clear:
	ldi 	0
	str 	rb
	inc 	rb
	glo 	rb
	bnz		clear
	dec 	rb 								; after last INC rb is $200, set back to $1xx
	glo	rb	
	str 	rb

	ldi 	2 								; set stack to $2FF
	phi 	r2
	ldi 	$FF
	plo 	r2

	sex 	r2 								; screen on.
	inp  	1

wait:
	ghi 	rb 								; R4 = Screen address 
	phi 	r4 								; it binary counts with whole bytes representing a bit of the
	ldi 	0 								; counter vertically down the screen
	plo 	r4
incloop:
	ldn 	r4 								; toggle all bits at current location
	xri 	255
	str 	r4
	bnz 	status 							; if non-zero update status
	glo 	r4 								; get the screen position
	inc 	r4
	inc 	r4
	str 	r4 								; store 2 further on - as a marker.
	adi 	8 								; next screen line down
	plo 	r4 								
	br 		incloop 						; go back and increment that

status:
	ldi 	7								; read IN 4 to $407
	plo 	r4
	sex 	r4
	inp 	4

	ldi 	7+16							; check EF3 (key pressed)
	plo		r4
	ldi 	255
	b3		isPressed
	ldi  	129
isPressed:
	str 	r4

	ldi 	7+32 							; check EF4 (not in)
	plo		r4
	ldi 	255
	bn4		isPressed2
	ldi  	129
isPressed2:
	str 	r4


	ldi 	8*10 							; use one of the counting bars to toggle Q
	plo		r4
	ldn 	r4
	req
	bz 		missQ
	seq
missQ:

	ldi 	7+48 							; check Q
	plo		r4
	ldi 	255
	bq		isPressed3
	ldi  	129
isPressed3:
	str 	r4

	br 		wait

EndInterrupt:
 	ldxa 							        ; RESTORE D
    ret 							        ; RESTORE XP

DisplayRoutine:
	dec   	r2         						; SAVE X P & D ON STK (2)
	sav 									; (4)

	dec   	r2 								; (6)
	str 	r2 								; (8)

	nop 									; (11)
	nop 									; (14)
	nop 									; (17)

	ghi		rb 								; (19)
	phi 	r0 								; (21)
	ldi 	0 								; (23)
	plo 	r0								; (25)
DisplayContinue:
	glo 	r0 								; (27)
 	sex  	r2 								; (29)

 	sex 	r2
 	dec 	r0
 	plo 	r0

 	sex 	r2
 	dec 	r0
 	plo 	r0

 	sex 	r2
 	dec 	r0
 	plo 	r0

 	bn1 	DisplayContinue
 	br 		EndInterrupt

