#
#	Convert S9 file to binary (in pacman.asm.s9, out pacman.asm.bin)
#
import sys

binary = [0xFF	] * 4096 															# Empty binary storage
s9records = open(sys.argv[1],"r").readlines() 									# read in records
s9records = [x.strip() for x in s9records if x.strip() != ""] 					# remove control and blanks

highAddress = -1

for s9rec in s9records:
	if s9rec[:2] != "S1":														# Must begin with S1
		raise Exception("S1 missing at start	")
	s9rec = s9rec[2:]
	size = int(s9rec[:2],16)													# extract size
	s9rec = s9rec[2:]
	if len(s9rec) != size * 2:
		raise Exception("Wrong size")
	address = int(s9rec[:4],16)													# get address
	s9rec = s9rec[4:] 															# and strip it.
	while s9rec != "":
		binary[address] = int(s9rec[:2],16)
		highAddress = max(highAddress,address)
		address = address+1
		s9rec = s9rec[2:]

start = 0x400
end = 0x1000
binfile = open(sys.argv[1][:-3]+".bin","wb")
for a in range(start,end):
	binfile.write(chr(binary[a]))
binfile.close()

