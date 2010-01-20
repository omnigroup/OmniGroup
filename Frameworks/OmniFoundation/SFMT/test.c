/**
 * @file  test.c
 * @brief test program for 32-bit and 64-bit output of SFMT.
 *
 * @author Mutsuo Saito (Hiroshima-univ)
 *
 * Copyright (C) 2007 Mutsuo Saito, Makoto Matsumoto and Hiroshima
 * University. All rights reserved.
 *
 * The new BSD License is applied to this software, see LICENSE.txt
 */

#include <stdio.h>
#include <limits.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>

#include "SFMT.c"

#define BLOCK_SIZE 100000
#define BLOCK_SIZE64 50000
#define COUNT 1000

void check32(void);
void speed32(void);
void check64(void);
void speed64(void);

#if defined(HAVE_ALTIVEC)
static vector unsigned int array1[BLOCK_SIZE / 4];
static vector unsigned int array2[10000 / 4];
#elif defined(HAVE_SSE2)
static __m128i array1[BLOCK_SIZE / 4];
static __m128i array2[10000 / 4];
#else
static uint64_t array1[BLOCK_SIZE / 4][2];
static uint64_t array2[10000 / 4][2];
#endif

#ifndef ONLY64
void check32(void) {
    int i;
    uint32_t *array32 = (uint32_t *)array1;
    uint32_t *array32_2 = (uint32_t *)array2;
    uint32_t ini[4] = {0x1234, 0x5678, 0x9abc, 0xdef0};
    uint32_t r32;

    if (get_min_array_size32() > 10000) {
	printf("array size too small!\n");
	exit(1);
    }
    printf("%s\n32 bit generated randoms\n", get_idstring());
    printf("init_gen_rand__________\n");
    /* 32 bit generation */
    init_gen_rand(1234);
    fill_array32(array32, 10000);
    fill_array32(array32_2, 10000);
    init_gen_rand(1234);
    for (i = 0; i < 10000; i++) {
	if (i < 1000) {
	    printf("%10u ", array32[i]);
	    if (i % 5 == 4) {
		printf("\n");
	    }
	}
	r32 = gen_rand32();
	if (r32 != array32[i]) {
	    printf("\nmismatch at %d array32:%x gen:%x\n", 
		   i, array32[i], r32);
	    exit(1);
	}
    }
    for (i = 0; i < 700; i++) {
	r32 = gen_rand32();
	if (r32 != array32_2[i]) {
	    printf("\nmismatch at %d array32_2:%x gen:%x\n", 
		   i, array32_2[i], r32);
	    exit(1);
	}
    }
    printf("\n");
    init_by_array(ini, 4);
    printf("init_by_array__________\n");
    fill_array32(array32, 10000);
    fill_array32(array32_2, 10000);
    init_by_array(ini, 4);
    for (i = 0; i < 10000; i++) {
	if (i < 1000) {
	    printf("%10u ", array32[i]);
	    if (i % 5 == 4) {
		printf("\n");
	    }
	}
	r32 = gen_rand32();
	if (r32 != array32[i]) {
	    printf("\nmismatch at %d array32:%x gen:%x\n", 
		   i, array32[i], r32);
	    exit(1);
	}
    }
    for (i = 0; i < 700; i++) {
	r32 = gen_rand32();
	if (r32 != array32_2[i]) {
	    printf("\nmismatch at %d array32_2:%x gen:%x\n", 
		   i, array32_2[i], r32);
	    exit(1);
	}
    }
}

void speed32(void) {
    int i, j;
    clock_t clo;
    clock_t min = LONG_MAX;
    uint32_t *array32 = (uint32_t *)array1;

    if (get_min_array_size32() > BLOCK_SIZE) {
	printf("array size too small!\n");
	exit(1);
    }
    /* 32 bit generation */
    init_gen_rand(1234);
    for (i = 0; i < 10; i++) {
	clo = clock();
	for (j = 0; j < COUNT; j++) {
	    fill_array32(array32, BLOCK_SIZE);
	}
	clo = clock() - clo;
	if (clo < min) {
	    min = clo;
	}
    }
    printf("32 bit BLOCK:%.0f", (double)min * 1000/ CLOCKS_PER_SEC);
    printf("ms for %u randoms generation\n",
	   BLOCK_SIZE * COUNT);
    min = LONG_MAX;
    init_gen_rand(1234);
    for (i = 0; i < 10; i++) {
	clo = clock();
	for (j = 0; j < BLOCK_SIZE * COUNT; j++) {
	    gen_rand32();
	}
	clo = clock() - clo;
	if (clo < min) {
	    min = clo;
	}
    }
    printf("32 bit SEQUE:%.0f", (double)min * 1000 / CLOCKS_PER_SEC);
    printf("ms for %u randoms generation\n",
	   BLOCK_SIZE * COUNT);
}
#endif

void check64(void) {
    int i;
    uint64_t *array64;
    uint64_t *array64_2;
    uint64_t r;
    uint32_t ini[] = {5, 4, 3, 2, 1};

    array64 = (uint64_t *)array1;
    array64_2 = (uint64_t *)array2;
    if (get_min_array_size64() > 5000) {
	printf("array size too small!\n");
	exit(1);
    }
    printf("%s\n64 bit generated randoms\n", get_idstring());
    printf("init_gen_rand__________\n");
    /* 64 bit generation */
    init_gen_rand(4321);
    fill_array64(array64, 5000);
    fill_array64(array64_2, 5000);
    init_gen_rand(4321);
    for (i = 0; i < 5000; i++) {
	if (i < 1000) {
	    printf("%20"PRIu64" ", array64[i]);
	    if (i % 3 == 2) {
		printf("\n");
	    }
	}
	r = gen_rand64();
	if (r != array64[i]) {
	    printf("\nmismatch at %d array64:%"PRIx64" gen:%"PRIx64"\n", 
		   i, array64[i], r);
	    exit(1);
	}
    }
    printf("\n");
    for (i = 0; i < 700; i++) {
	r = gen_rand64();
	if (r != array64_2[i]) {
	    printf("\nmismatch at %d array64_2:%"PRIx64" gen:%"PRIx64"\n", 
		   i, array64_2[i], r);
	    exit(1);
	}
    }
    printf("init_by_array__________\n");
    /* 64 bit generation */
    init_by_array(ini, 5);
    fill_array64(array64, 5000);
    fill_array64(array64_2, 5000);
    init_by_array(ini, 5);
    for (i = 0; i < 5000; i++) {
	if (i < 1000) {
	    printf("%20"PRIu64" ", array64[i]);
	    if (i % 3 == 2) {
		printf("\n");
	    }
	}
	r = gen_rand64();
	if (r != array64[i]) {
	    printf("\nmismatch at %d array64:%"PRIx64" gen:%"PRIx64"\n", 
		   i, array64[i], r);
	    exit(1);
	}
    }
    printf("\n");
    for (i = 0; i < 700; i++) {
	r = gen_rand64();
	if (r != array64_2[i]) {
	    printf("\nmismatch at %d array64_2:%"PRIx64" gen:%"PRIx64"\n", 
		   i, array64_2[i], r);
	    exit(1);
	}
    }
}

void speed64(void) {
    int i, j;
    uint64_t clo;
    uint64_t min = LONG_MAX;
    uint64_t *array64 = (uint64_t *)array1;

    if (get_min_array_size64() > BLOCK_SIZE64) {
	printf("array size too small!\n");
	exit(1);
    }
    /* 64 bit generation */
    init_gen_rand(1234);
    for (i = 0; i < 10; i++) {
	clo = clock();
	for (j = 0; j < COUNT; j++) {
	    fill_array64(array64, BLOCK_SIZE64);
	}
	clo = clock() - clo;
	if (clo < min) {
	    min = clo;
	}
    }
    printf("64 bit BLOCK:%.0f", (double)min * 1000/ CLOCKS_PER_SEC);
    printf("ms for %u randoms generation\n",
	   BLOCK_SIZE64 * COUNT);
    min = LONG_MAX;
    init_gen_rand(1234);
    for (i = 0; i < 10; i++) {
	clo = clock();
	for (j = 0; j < BLOCK_SIZE64 * COUNT; j++) {
	    gen_rand64();
	}
	clo = clock() - clo;
	if (clo < min) {
	    min = clo;
	}
    }
    printf("64 bit SEQUE:%.0f", (double)min * 1000 / CLOCKS_PER_SEC);
    printf("ms for %u randoms generation\n",
	   BLOCK_SIZE64 * COUNT);
}

int main(int argc, char *argv[]) {
    int i;
    int speed = 0;
    int bit64 = 0;
#ifndef ONLY64
    int bit32 = 0;
#endif

    for (i = 1; i < argc; i++) {
	if (strncmp(argv[1],"-s", 2) == 0) {
	    speed = 1;
	}
	if (strncmp(argv[1],"-b64", 4) == 0) {
	    bit64 = 1;
	}
#ifndef ONLY64
	if (strncmp(argv[1],"-b32", 4) == 0) {
	    bit32 = 1;
	}
#endif
    }
#ifdef ONLY64
    if (speed + bit64 == 0) {
	printf("usage:\n%s [-s | -b64]\n", argv[0]);
	return 0;
    }
#else
    if (speed + bit32 + bit64 == 0) {
	printf("usage:\n%s [-s | -b32 | -b64]\n", argv[0]);
	return 0;
    }
#endif
    if (speed) {
#ifndef ONLY64
	speed32();
#endif
	speed64();
    }
#ifndef ONLY64
    if (bit32) {
	check32();
    }
#endif
    if (bit64) {
	check64();
    }
    return 0;
}
