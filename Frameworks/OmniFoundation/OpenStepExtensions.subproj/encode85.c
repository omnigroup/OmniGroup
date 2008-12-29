// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/* encode85 -- convert to ascii85 format */

#include <stdio.h>
#include <OmniBase/rcsid.h>

RCS_ID("$Id$")

#define	atoi(s)	strtol(s, 0, 0)

static unsigned long width = 72, pos = 0, tuple = 0;
static int count = 0;

void init85(void) {
	printf("<~");
	pos = 2;
}

void encode(unsigned long tuple, int count) {
	int i;
	char buf[5], *s = buf;
	i = 5;
	do {
		*s++ = tuple % 85;
		tuple /= 85;
	} while (--i > 0);
	i = count;
	do {
		putchar(*--s + '!');
		if (pos++ >= width) {
			pos = 0;
			putchar('\n');
		}
	} while (i-- > 0);
}

void put85(unsigned c) {
	switch (count++) {
	case 0:	tuple |= (c << 24); break;
	case 1: tuple |= (c << 16); break;
	case 2:	tuple |= (c <<  8); break;
	case 3:
		tuple |= c;
		if (tuple == 0) {
			putchar('z');
			if (pos++ >= width) {
				pos = 0;
				putchar('\n');
			}
		} else
			encode(tuple, count);
		tuple = 0;
		count = 0;
		break;
	}
}

void cleanup85(void) {
	if (count > 0)
		encode(tuple, count);
	if (pos + 2 > width)
		putchar('\n');
	printf("~>\n");
}

void copy85(FILE *fp) {
	unsigned c;
	while ((c = getc(fp)) != EOF)
		put85(c);
}

void usage(void) {
	fprintf(stderr, "usage: encode85 [-w width] file ...\n");
	exit(1);
}

extern int getopt(int, char *[], const char *);
extern int optind;
extern char *optarg;

int main(int argc, char *argv[]) {
	int i;
	while ((i = getopt(argc, argv, "w:?")) != EOF)
		switch (i) {
		case 'w':
			width = atoi(optarg);
			if (width == 0)
				width = ~0;
			break;
		case '?':
			usage();
		}
	
	init85();
	if (optind == argc)
		copy85(stdin);
	else
		for (i = optind; i < argc; i++) {
			FILE *fp = fopen(argv[i], "r");
			if (fp == NULL) {
				perror(argv[i]);
				return 1;
			}
			copy85(fp);
			fclose(fp);
		}
	cleanup85();
	return 0;
}
