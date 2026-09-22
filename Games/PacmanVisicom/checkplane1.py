#!/usr/bin/env python3
#
#   checkplane1.py <state-dump> [--map]
#
# Checks the Visicom build's second bit plane against what it is supposed to
# contain. Plane 1 has no "does it look right": a wrong bit there is just a
# coloured pixel somewhere plausible. It does have an exact invariant --
#
#   plane 1 == XOR of every graphic whose plane mask has bit 1 set, stamped at
#              the position in its sprite record, plus the power pills still on
#              the board
#
# -- and that is what this checks. Zero mismatch is the pass. The only
# legitimate non-zero is about one sprite's worth, when the dump caught the CPU
# part way through a draw or an erase.
#
# Do NOT do this against the rendered frame: the picture is assembled over a
# whole DMA scan, so a moving sprite tears across it and a real error hides
# inside a plausible amount of noise. It has to be the plane as it sits in
# memory. The MiSTer core's headless Verilator sim will print it given twelve
# lines in dump_state():
#
#   #define PL1RAM (top->rootp->top__DOT__rcastudioii__DOT__sram2__DOT__mem)
#   ...
#   if (RS(machine) == 3) {
#       fprintf(f, "-- Visicom plane 1 $1300-$13FF --\n");
#       for (int r = 0; r < 256; r += 16) {
#           fprintf(f, "  %04X: ", 0x1300 + r);
#           for (int c = 0; c < 16; c++) fprintf(f, "%02X ", PL1RAM[r + c]);
#           fprintf(f, "\n");
#       }
#   }
#
# then run it with  --dump <frame> --vram  and feed the output to this script.
#
import sys, re

# the Graphics table from pacman.asm, and the plane masks from PlaneTable
GFX = {0x40: ('Pellet',    1, [0x00, 0x20, 0x00, 0x00]),
       0x44: ('PowerPill', 2, [0x00, 0x70, 0x70, 0x00]),
       0x48: ('PacClosed', 2, [0x70, 0xF8, 0xF8, 0x70]),
       0x4C: ('PacUp',     2, [0x50, 0xF8, 0xF8, 0x70]),
       0x50: ('PacDown',   2, [0x70, 0xF8, 0xF8, 0x50]),
       0x54: ('PacLeft',   2, [0x70, 0x38, 0x38, 0x70]),
       0x58: ('PacRight',  2, [0x70, 0xE0, 0xE0, 0x70]),
       0x5C: ('Ghost1',    3, [0x70, 0xA8, 0xF8, 0x50]),
       0x60: ('Ghost2',    3, [0x70, 0xA8, 0xF8, 0xA8]),
       0x64: ('GhostRev',  1, [0x70, 0x88, 0x88, 0x50]),
       0x68: ('Cherry',    2, [0x40, 0x20, 0xD8, 0xD8]),
       0x6C: ('Blank',     1, [0x00, 0x00, 0x00, 0x00])}

text = open(sys.argv[1]).read()

def region(tag, pat):
    out = {}
    for m in re.finditer(pat, text.split(tag)[1], re.M):
        base = int(m.group(1), 16)
        for i, v in enumerate(m.group(2).split()):
            out[base + i] = int(v, 16)
    return out

ram = region('-- System RAM',      r'^  08([0-9A-F]{2}): ((?:[0-9A-F]{2} ){16})')
pl1 = region('-- Visicom plane 1', r'^  13([0-9A-F]{2}): ((?:[0-9A-F]{2} ){16})')

actual = [[(pl1[r * 8 + c // 8] >> (7 - c % 8)) & 1 for c in range(64)] for r in range(32)]
model  = [[0] * 64 for _ in range(32)]

def stamp(g, x, y):                             # a sprite is drawn at (x+1, y+1)
    if GFX[g][1] & 2 == 0: return
    for r in range(4):
        for c in range(5):
            if (GFX[g][2][r] >> (7 - c)) & 1:
                py, px = y + 1 + r, x + 1 + c
                if 0 <= py < 32 and 0 <= px < 64: model[py][px] ^= 1

for i in range(60):                             # the maze: bit 7 pill, bit 6 power pill
    if ram[i] & 0x80: stamp(0x44 if ram[i] & 0x40 else 0x40, (i % 10) * 6, (i // 10) * 5)

live = []
for n in range(6):                              # six sprite records, 16 bytes each
    b = 0x60 + n * 16
    if ram[b + 2]:
        stamp(ram[b + 2], ram[b], ram[b + 1])
        live.append("%d@(%d,%d)%s" % (n, ram[b], ram[b + 1], GFX[ram[b + 2]][0]))

bad = [(r, c) for r in range(32) for c in range(64) if actual[r][c] != model[r][c]]
print("loop=%-3d model=%-4d actual=%-4d mismatched=%-4d  %s"
      % (ram[0x4C], sum(map(sum, model)), sum(map(sum, actual)), len(bad), " ".join(live)))

if '--map' in sys.argv:
    for r in range(32):
        line = ''.join('X' if actual[r][c] != model[r][c] else ('o' if model[r][c] else '.')
                       for c in range(64))
        if line.strip('.'): print(' %2d |%s|' % (r, line))
    print("  X = wrong, o = correctly modelled")

sys.exit(1 if bad else 0)
