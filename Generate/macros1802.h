/* GENERATED */

#define ADD(n1,n2,n3) _temp = (n1)+(n2)+(n3);DF = _temp >> 8;D = _temp
#define SUB(n1,n2,n3) _temp = (n1)+((n2) ^ 0xFF)+(n3);DF = _temp >> 8;D = _temp
#define SHORT(b)   R[P] = (R[P] & 0xFF00) | (b)
#define LONG(a)   R[P] = (a)
#define LONGSKIP()   R[P] += 2
#define INTERRUPT()  if (IE != 0) { T = (X << 4) | P; P = 1; X = 2; IE = 0; }
#define RETURN()    _temp = READ(R[X]);R[X]++;X = _temp >> 4;P = _temp & 0x0F