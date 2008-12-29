// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/* decode85 -- convert from ascii85 format */

#include <stdio.h>
#include <OmniBase/rcsid.h>

RCS_ID("$Id$")

static unsigned long pow85[] = {
	85*85*85*85, 85*85*85, 85*85, 85, 1
};

void wput(unsigned long tuple, int bytes) {
	switch (bytes) {
	case 4:
		putchar(tuple >> 24);
		putchar(tuple >> 16);
		putchar(tuple >>  8);
		putchar(tuple);
		break;
	case 3:
		putchar(tuple >> 24);
		putchar(tuple >> 16);
		putchar(tuple >>  8);
		break;
	case 2:
		putchar(tuple >> 24);
		putchar(tuple >> 16);
		break;
	case 1:
		putchar(tuple >> 24);
		break;
	}
}

void decode85(FILE *fp, const char *file) {
	unsigned long tuple = 0;
	int c, count = 0;
	for (;;)
		switch (c = getc(fp)) {
		default:
			if (c < '!' || c > 'u') {
				fprintf(stderr, "%s: bad character in ascii85 region: %#o\n", file, c);
				exit(1);
			}
			tuple += (c - '!') * pow85[count++];
			if (count == 5) {
				wput(tuple, 4);
				count = 0;
				tuple = 0;
			}
			break;
		case 'z':
			if (count != 0) {
				fprintf(stderr, "%s: z inside ascii85 5-tuple\n", file);
				exit(1);
			}
			putchar(0);
			putchar(0);
			putchar(0);
			putchar(0);
			break;
		case '~':
			if (getc(fp) == '>') {
				if (count > 0) {
					count--;
					tuple += pow85[count];
					wput(tuple, count);
				}
				c = getc(fp);
				return;
			}
			fprintf(stderr, "%s: ~ without > in ascii85 section\n", file);
			exit(1);
		case '\n': case '\r': case '\t': case ' ':
		case '\0': case '\f': case '\b': case 0177:
			break;
		case EOF:
			fprintf(stderr, "%s: EOF inside ascii85 section\n", file);
			exit(1);
		}
}

void decode(FILE *fp, const char *file, int preserve) {
	int c;
	while ((c = getc(fp)) != EOF)
		if (c == '<')
			if ((c = getc(fp)) == '~')
				decode85(fp, file);
			else {
				if (preserve)
					putchar('<');
				if (c == EOF)
					break;
				if (preserve)
					putchar(c);
			}
		else
			if (preserve)
				putchar(c);
}

void usage(void) {
	fprintf(stderr, "usage: decode85 [-p] file ...\n");
	exit(1);
}

extern int getopt(int, char *[], const char *);
extern int optind;
extern char *optarg;

int main(int argc, char *argv[]) {
	int i, preserve;
	preserve = 0;
	while ((i = getopt(argc, argv, "p?")) != EOF)
		switch (i) {
		case 'p': preserve = 1; break;
		case '?': usage();
		}
	

	if (optind == argc)
		decode(stdin, "decode85", preserve);
	else
		for (i = optind; i < argc; i++) {
			FILE *fp = fopen(argv[i], "r");
			if (fp == NULL) {
				perror(argv[i]);
				return 1;
			}
			decode(fp, argv[i], preserve);
			fclose(fp);
		}
	return 0;
}
