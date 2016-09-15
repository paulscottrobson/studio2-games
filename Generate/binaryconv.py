#
#	File Conversions
#
def writeFile(code,start,length,target,name):
	code = code[start:start+length]
	out = ",".join(code)
	f = open(target,"w")
	f.write("/* GENERATED */\n\nstatic PROGMEM prog_uchar "+name+"["+str(len(code))+"] = {"+out+"};")	
	f.close()

bin = open("studio2.rom","rb").read()
code = []
for b in bin:
	code.append(str(ord(b)))
code[0x3E] = "56"			# Don't wait for B1
		
writeFile(code,0,2048,"studio2.h","_studio2")
writeFile(code,0,1024,"studio2_bios.h","_studio2_bios")
writeFile(code,1024,1024,"studio2_game.h","_studio2_game")
