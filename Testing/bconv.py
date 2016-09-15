#
#	Binary Convertor
#

def convert(sourceFile,name,address,dataFile,execFile):
	f = open(sourceFile,"rb")
	code = []
	bytes = f.read(8192)
	f.close()

	for b in bytes:
		code.append(str(ord(b)))
	size = len(code)
	code = "{" + (",".join(code))+"}"

	execCode = "prog_uchar "+name+"[] PROGMEM = "+code+";"+"\n"
	dataFile.write(execCode)

	execCode = "RAMUpload("+name+","+str(size)+","+str(address)+");\n"
	execFile.write(execCode)

fData = open("binary_data.h","w")
fExec = open("binary_code.h","w")
convert("speed.asm.bin","speed",0,fData,fExec)
fData.close()
fExec.close()

