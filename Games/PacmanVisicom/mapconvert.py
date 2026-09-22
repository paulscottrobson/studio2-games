#
#	Converts cut map.dat from spreadsheet to a working map.
#

class FakeScreen:
	def __init__(self):
		self.screen = [" "*64]*32
	def printScreen(self):		
		print "\n".join(self.screen)
	def set(self,x,y):
		self.screen[y] = self.screen[y][:x] + "*" + self.screen[y][x+1:]
	def hline(self,x,y,s):
		while s > 0:
			self.set(x,y)
			x = x + 1
			s = s - 1
	def vline(self,x,y,s):
		while s > 0:
			self.set(x,y)
			y = y + 1
			s = s - 1

lines = open("map.dat").readlines()
lines = [x.strip() for x in lines if x.strip() != "" and (x+" ")[0] != ';']

if len(lines) != 6:
	raise Exception("Should be 6 lines of map data")

mapBytes = [0] * 60
row = 0
for l in lines:
	ln = l.replace("\t"," ").replace("  "," ").split(" ")
	if len(ln) != 10:
		raise Exception("Malformed line : "+str(ln))
	column = 0
	for ri in ln:
		cell = row * 10 +column
		if ri.find("U") >= 0:
			mapBytes[cell] |= 1
			if row > 0:
				mapBytes[cell-10] |= 8
		if ri.find("L") >= 0:
			mapBytes[cell] |= 2
			if column > 0:
				mapBytes[cell-1] |= 4
		
		if row != 3 and column == 9:
				mapBytes[cell] |= 4
		if row == 5:
				mapBytes[cell] |= 8

		column = column+1
	row = row + 1

mapBytes[0*10+0] |= 64
mapBytes[0*10+9] |= 64
mapBytes[5*10+0] |= 64
mapBytes[5*10+9] |= 64

for n in range(0,60): 			# set all the powerpill/dot bits present
	mapBytes[n] |= 0x80

mapBytes[34] &= 0x7F			# clear pacman power pill bits
mapBytes[35] &= 0x7F

mapBytes[54] &= 0x7F 			# clear dots/pills bit for start position 
mapBytes[55] &= 0x7F 			# symmetrical.

for n in range(0,60):
	if n % 6 == 0:
		mapBytes[n] |= 32
	if n % 5 == 0:
		mapBytes[n] |= 16

print mapBytes
s = FakeScreen()

for row in range(0,10):
	for col in range(0,6):
		x = row * 6
		y = col * 5
		cellByte = mapBytes[row+col*10]
		if cellByte & 1 != 0:
			s.hline(x,y,7)
		if cellByte & 8 != 0:
			s.hline(x,y+5,7)
		if cellByte & 2 != 0:
			s.vline(x,y,6)
		if cellByte & 4 != 0:
			s.vline(x+6,y,6)
		if cellByte & 64 != 0:
			s.hline(x+2,y+2,3)
			s.hline(x+2,y+3,3)

s.printScreen()

for n in range(0,60):
	mapBytes[n] = "${0:02x}".format(mapBytes[n])

f = open("mapbytes.inc","w")
for row in range(0,6):
	f.write("        .db     "+",".join(mapBytes[row*10:row*10+10])+"\n");
f.close()	