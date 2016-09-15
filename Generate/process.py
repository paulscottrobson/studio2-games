#
#	Processor for cdp1802.gen
#
import re

def processIn(x):
	x = x.strip()
	n = x.find("//")
	if n >= 0:
		x = x[:n]
	return x.strip().replace("\t"," ")

def processOut(s,op):
	s = s.replace("{H}","%x" % (op % 16))
	s = s.replace("{P}",str(op % 8))
	s = s.replace("{R}",str(op % 16))

	if op/16 == 3 or op/16 == 12:
		cc = op & 0x0F if op/16 == 3 else op & 0x0B
		if op/16 == 12 and (op & 4) != 0:
			cc = cc ^ 8
		codes = [ "<Err>","Q","Z","DF","1","2","3","4","<Err>","NQ","NZ","NF","N1","N2","N3","N4"]
		s = s.replace("{C}",codes[cc])
		program = [ "<Err>","(Q != 0)","(D == 0)","(DF != 0)"]
		c = program[cc % 8] if cc % 8 < 4 else "(READEFLAG({0}) != 0)".format(cc % 8 - 3)
		s = s.replace("{T}",c)
	return s

lines = open("cdp1802.gen").readlines()
lines = [processIn(x) for x in lines]
lines = [x for x in lines if x != '']

macros = [x[1:].strip() for x in lines if x[0] == ':']
open ("macros1802.h","w").write("/* GENERATED */\n\n"+"\n".join(macros))

code = [""] * 256
mnemonics = [""] * 256
lines = [x for x in lines if x[0] != ':']
for l in lines:
	m = re.match("^([0-9A-FA-F\-]+)\s+\"([A-Za-z\s\{\}\.1268]*)\"\s+(.*)$",l)
	if m is None:
		raise Exception("Syntax Error "+l)
	if len(m.groups()) != 3:
		raise Exception("Syntax Error "+l)		
	orange = m.group(1)
	start = end = int(orange[:2],16)
	if len(orange) == 5:
		end = int(orange[-2:],16)

	for opcode in range(start,end+1):
		if mnemonics[opcode] != "":
			raise Exception("Duplicate opcode "+str(opcode)+" "+l)
		mnemonics[opcode] = ('"'+processOut(m.group(2),opcode)+'"').lower()
		code[opcode] = processOut(m.group(3),opcode)
		if code[opcode] != "" and code[opcode][-1] != ';':
			code[opcode] = code[opcode]+";"
for i in range(0,256):
	if mnemonics[i] == "":
		raise Exception("Opcode undefined "+str(i))

open("mnemonics1802.h","w").write("/* GENERATED */\n\nstatic char *_mnemonics[256] = { "+",".join(mnemonics)+ "};")

codefile = open("cpu1802.h","w")
codefile.write("/* GENERATED */\n\n")
for i in range(0,256):
	codefile.write("case 0x{0:02x}: /* {1} */\n".format(i,mnemonics[i]))
	codefile.write("    "+code[i]+"\n")
	codefile.write("    break;\n")

print "Generated source successfully."