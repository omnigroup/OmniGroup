# @file  Makefile
# @brief Makefile
#
# @author Mutsuo Saito (Hiroshima University)
# @author Makoto Matsumoto (Hiroshima University)
#
# Copyright (C) 2007 Mutsuo Saito, Makoto Matsumoto and Hiroshima
# University. All rights reserved.
#
# The new BSD License is applied to this software.
# see LICENSE.txt
#
# @note
# We could comple test-sse2-Mxxx using gcc 3.4.4 of cygwin.
# We could comple test-sse2-Mxxx using gcc 4.0.1 of Linux.
# We coundn't comple test-sse2-Mxxx using gcc 3.3.2 of Linux.
# We could comple test-alti-Mxxx using gcc 3.3 of osx.
# We could comple test-alti-Mxxx using gcc 4.0 of osx.

WARN = -Wmissing-prototypes -Wall #-Winline 
#WARN = -Wmissing-prototypes -Wall -W
OPTI = -O3 -finline-functions -fomit-frame-pointer -DNDEBUG \
-fno-strict-aliasing --param max-inline-insns-single=1800 
#--param inline-unit-growth=500 --param large-function-growth=900 #for gcc 4
#STD =
#STD = -std=c89 -pedantic
#STD = -std=c99 -pedantic
STD = -std=c99
CC = gcc
CCFLAGS = $(OPTI) $(WARN) $(STD)
ALTIFLAGS = -mabi=altivec -maltivec -DHAVE_ALTIVEC
OSXALTIFLAGS = -faltivec -maltivec -DHAVE_ALTIVEC
SSE2FLAGS = -msse2 -DHAVE_SSE2
STD_TARGET = test-std-M19937
BIG_TARGET = test-big64-M19937
ALL_STD_TARGET = test-std-M607 test-std-M1279 test-std-M2281 test-std-M4253 \
test-std-M11213 test-std-M19937 test-std-M44497 test-std-M86243 \
test-std-M132049 test-std-M216091
ALL_BIG_TARGET = test-big64-M607 test-big64-M1279 test-big64-M2281 \
test-big64-M4253 test-big64-M11213 test-big64-M19937 test-big64-M44497 \
test-big64-M86243 test-big64-M132049 test-big64-M216091
ALTI_TARGET = test-alti-M19937
ALL_ALTI_TARGET = test-alti-M607 test-alti-M1279 test-alti-M2281 \
test-alti-M4253 test-alti-M11213 test-alti-M19937 test-alti-M44497 \
test-alti-M86243 test-alti-M132049 test-alti-M216091
ALL_ALTIBIG_TARGET = test-alti64-M607 test-alti64-M1279 test-alti64-M2281 \
test-alti64-M4253 test-alti64-M11213 test-alti64-M19937 test-alti64-M44497 \
test-alti64-M86243 test-alti64-M132049 test-alti64-M216091
SSE2_TARGET = test-sse2-M19937
ALL_SSE2_TARGET = test-sse2-M607 test-sse2-M1279 test-sse2-M2281 \
test-sse2-M4253 test-sse2-M11213 test-sse2-M19937 test-sse2-M44497 \
test-sse2-M86243 test-sse2-M132049 test-sse2-M216091
# ==========================================================
# comment out or EDIT following lines to get max performance
# ==========================================================
# --------------------
# for gcc 4
# --------------------
#CCFLAGS += --param inline-unit-growth=500 \
#--param large-function-growth=900
# --------------------
# for icl
# --------------------
#CC = icl /Wcheck /O3 /QxB /Qprefetch
# -----------------
# for PowerPC
# -----------------
#CCFLAGS += -arch ppc
# -----------------
# for Pentium M
# -----------------
#CCFLAGS += -march=prescott
# -----------------
# for Athlon 64
# -----------------
#CCFLAGS += -march=athlon64

.PHONY: std-check sse2-check alti-check

std: ${STD_TARGET}

sse2:${SSE2_TARGET}

alti:${ALTI_TARGET}

osx-alti:
	make "ALTIFLAGS=${OSXALTIFLAGS}" alti

big:${BIG_TARGET}

std-check: ${ALL_STD_TARGET}
	./check.sh 32 test-std

sse2-check: ${ALL_SSE2_TARGET}
	./check.sh 32 test-sse2

alti-check: ${ALL_ALTI_TARGET}
	./check.sh 32 test-alti

osx-alti-check:
	make "ALTIFLAGS=${OSXALTIFLAGS}" alti-check

big-check: ${ALL_BIG_TARGET} ${ALL_STD_TARGET}
	./check.sh 64 test-big64

altibig-check: ${ALL_ALTIBIG_TARGET} ${ALL_STD_TARGET}
	./check.sh 64 test-alti64

osx-altibig-check:
	make "ALTIFLAGS=${OSXALTIFLAGS}" altibig-check

test-std-M607: test.c SFMT.c SFMT.h SFMT-params607.h
	${CC} ${CCFLAGS} -DMEXP=607 -o $@ test.c

test-alti-M607: test.c SFMT.c SFMT.h SFMT-alti.h SFMT-params607.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=607 -o $@ test.c

test-sse2-M607: test.c SFMT.c SFMT.h SFMT-sse2.h SFMT-params607.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=607 -o $@ test.c

test-std-M1279: test.c SFMT.c SFMT.h SFMT-params1279.h
	${CC} ${CCFLAGS} -DMEXP=1279 -o $@ test.c

test-alti-M1279: test.c SFMT.c SFMT.h SFMT-alti.h SFMT-params1279.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=1279 -o $@ test.c

test-sse2-M1279: test.c SFMT.c SFMT.h SFMT-sse2.h SFMT-params1279.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=1279 -o $@ test.c

test-std-M2281: test.c SFMT.c SFMT.h SFMT-params2281.h
	${CC} ${CCFLAGS} -DMEXP=2281 -o $@ test.c

test-alti-M2281: test.c SFMT.c SFMT.h SFMT-alti.h SFMT-params2281.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=2281 -o $@ test.c

test-sse2-M2281: test.c SFMT.c SFMT.h SFMT-sse2.h SFMT-params2281.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=2281 -o $@ test.c

test-std-M4253: test.c SFMT.c SFMT.h SFMT-params4253.h
	${CC} ${CCFLAGS} -DMEXP=4253 -o $@ test.c

test-alti-M4253: test.c SFMT.c SFMT.h SFMT-alti.h SFMT-params4253.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=4253 -o $@ test.c

test-sse2-M4253: test.c SFMT.c SFMT.h SFMT-sse2.h SFMT-params4253.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=4253 -o $@ test.c

test-std-M11213: test.c SFMT.c SFMT.h SFMT-params11213.h
	${CC} ${CCFLAGS} -DMEXP=11213 -o $@ test.c

test-alti-M11213: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params11213.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=11213 -o $@ test.c

test-sse2-M11213: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params11213.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=11213 -o $@ test.c

test-std-M19937: test.c SFMT.c SFMT.h SFMT-params19937.h
	${CC} ${CCFLAGS} -DMEXP=19937 -o $@ test.c

test-alti-M19937: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params19937.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=19937 -o $@ test.c

test-sse2-M19937: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params19937.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=19937 -o $@ test.c

test-std-M44497: test.c SFMT.c SFMT.h SFMT-params44497.h
	${CC} ${CCFLAGS} -DMEXP=44497 -o $@ test.c

test-alti-M44497: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params44497.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=44497 -o $@ test.c

test-sse2-M44497: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params44497.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=44497 -o $@ test.c

test-std-M86243: test.c SFMT.c SFMT.h SFMT-params86243.h
	${CC} ${CCFLAGS} -DMEXP=86243 -o $@ test.c

test-alti-M86243: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params86243.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=86243 -o $@ test.c

test-sse2-M86243: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params86243.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=86243 -o $@ test.c

test-std-M132049: test.c SFMT.c SFMT.h SFMT-params132049.h
	${CC} ${CCFLAGS} -DMEXP=132049 -o $@ test.c

test-alti-M132049: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params132049.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=132049 -o $@ test.c

test-sse2-M132049: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params132049.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=132049 -o $@ test.c

test-std-M216091: test.c SFMT.c SFMT.h SFMT-params216091.h
	${CC} ${CCFLAGS} -DMEXP=216091 -o $@ test.c

test-alti-M216091: test.c SFMT.c SFMT.h SFMT-alti.h \
	SFMT-params216091.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DMEXP=216091 -o $@ test.c

test-sse2-M216091: test.c SFMT.c SFMT.h SFMT-sse2.h \
	SFMT-params216091.h
	${CC} ${CCFLAGS} ${SSE2FLAGS} -DMEXP=216091 -o $@ test.c

test-big64-M607: test.c SFMT.c SFMT.h SFMT-params607.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=607 -o $@ test.c

test-alti64-M607: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params607.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=607 -o $@ test.c

test-big64-M1279: test.c SFMT.c SFMT.h SFMT-params1279.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=1279 -o $@ test.c

test-alti64-M1279: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params1279.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=1279 -o $@ test.c

test-big64-M2281: test.c SFMT.c SFMT.h SFMT-params2281.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=2281 -o $@ test.c

test-alti64-M2281: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params2281.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=2281 -o $@ test.c

test-big64-M4253: test.c SFMT.c SFMT.h SFMT-params4253.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=4253 -o $@ test.c

test-alti64-M4253: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params4253.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=4253 -o $@ test.c

test-big64-M11213: test.c SFMT.c SFMT.h SFMT-params11213.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=11213 -o $@ test.c

test-alti64-M11213: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params11213.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=11213 -o $@ test.c

test-big64-M19937: test.c SFMT.c SFMT.h SFMT-params19937.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=19937 -o $@ test.c

test-alti64-M19937: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params19937.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=19937 -o $@ test.c

test-big64-M44497: test.c SFMT.c SFMT.h SFMT-params44497.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=44497 -o $@ test.c

test-alti64-M44497: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params44497.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=44497 -o $@ test.c

test-big64-M86243: test.c SFMT.c SFMT.h SFMT-params86243.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=86243 -o $@ test.c

test-alti64-M86243: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params86243.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=86243 -o $@ test.c

test-big64-M132049: test.c SFMT.c SFMT.h SFMT-params132049.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=132049 -o $@ test.c

test-alti64-M132049: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params132049.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=132049 -o $@ test.c

test-big64-M216091: test.c SFMT.c SFMT.h SFMT-params216091.h
	${CC} ${CCFLAGS} -DONLY64 -DMEXP=216091 -o $@ test.c

test-alti64-M216091: test.c SFMT.c SFMT.h SFMT-alti.h \
		  SFMT-params216091.h
	${CC} ${CCFLAGS} ${ALTIFLAGS} -DONLY64 -DMEXP=216091 -o $@ test.c

clean:
	rm -f *.o *~
