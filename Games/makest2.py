#
#	ST2 File Constructor.
#
class ST2File:
	def __init__(self):
		self.bytes = [0] * 8192 								# Allocate 8192 for final st2 file
		self.codeFile = None 									# No binary file (list of ints)
		self.outputFile = None 									# Target file name
		self.writeASCII("RCA2",0) 								# Set 0-3 to RCA2
		self.bytes[4] = 1										# 1 Page
		self.bytes[5] = 1 										# Format version 1
		self.bytes[6] = 0 										# Normal Studio2 Video Driver
		self.writeASCII("????",8) 								# Dumper and Author both unknown
		self.bytes[16] = 0; 									# RCA Catalogue Code (ASCIIZ String)
		self.bytes[32] = 0; 									# Title (ASCIIZ String)
		st2file = open("st2file").readlines() 					# Open file, remove comments and strip junk.
		st2file = [s.strip() for s in st2file if (s+" ")[0] != ';' and s.strip() != ""]
		for cmd in st2file:										# Work through commands
			p = cmd.find(":") 									# Find splitting colon
			self.execute(cmd[:p].strip().upper(),cmd[p+1:].strip())

	def writeASCII(self,text,offset): 							# Write text at offset (no ending zero)
		for n in range(0,len(text)):
			self.bytes[offset+n] = ord(text[n])

	def execute(self,command,param):
		if command == "AUTHOR": 								# Change Author ID
			self.writeASCII(param[:2],8)
		elif command == "DUMPER": 								# Change Dumper ID
			self.writeASCII(param[:2],10)
		elif command == "CAT": 									# Change RCA Catalogue #
			self.writeASCII(param+chr(0),16)
		elif command == "TITLE": 								# Change title
			self.writeASCII(param+chr(0),32)
		elif command == "CODE": 								# Include part of the binary
			self.includeCode(param)
		elif command == "BINARY": 								# Name output file.
			self.outputFile = param
		elif command == "SOURCE":								# Load Binary Code file.
			self.codeFile = self.loadCode(param)
		else:
			raise Exception("Unknown command "+command)


	def loadCode(self,fileName):
		f = open(fileName,"rb")									# Open file for binary reading
		contents = f.read(8192); 								# Read in lots and lots 
		f.close()
		code = []												# convert it to numeric list
		for c in contents:
			code.append(ord(c))
		print "Read in {0} length {1} bytes.".format(fileName,len(code))
		return code 											# return the list

	def includeCode(self,param):
		param = param.split(",")								# page count, offset.
		offset = int(param[0],16) 								# get offset in binary
		count = int(param[1],16) 								# get count of pages
		while count > 0:										# while more pages
			self.includePage(offset) 							# include page in ST2 file.
			offset = offset+256 								# go to net page
			count = count-1										# one fewer page to do.

	def includePage(self,address):
		pageNumber = self.bytes[4]+1							# add one new  page
		self.bytes[4] = pageNumber  							# write page number back.
		self.bytes[64+pageNumber-2] = address/256
		print "Loading page at {0:x} to ST2 page {1}.".format(address,pageNumber)
		for i in range(0,256):									# copy one page over.
			self.bytes[(pageNumber-2)*256+i+256] = self.codeFile[address+i-0x400]

	def write(self):
		print "Writing {0} length {1} bytes".format(self.outputFile,256*self.bytes[4])
		f = open(self.outputFile,"wb")							# output write file in binary
		for i in range(0,256*self.bytes[4]):
			f.write(chr(self.bytes[i]))
		f.close()

b = ST2File()
b.write()

