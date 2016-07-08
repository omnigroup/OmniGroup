
#line 1 "OQSVGPath.rl"
// Copyright 2011-2016 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQDrawing.h>
#include <stdbool.h>  /* Using stdbool's bool type here because that's what CoreGraphics uses. */
#include <string.h>
#include <stdlib.h>
#include <OmniBase/rcsid.h>

RCS_ID("$Id$");

/* Sometimes we have to copy a number to a stack-allocated buffer.
   Numbers longer than this may be unparsable (even if they're
   strictly allowed by the SVG spec). */
#define MAX_NUMBER_LENGTH 128

/* We preprocess the various shorthand and relative SVG constructions
   into their logical equivalents */
enum SVG_condensed_op {
    SVGc_closepath,
    SVGc_moveto,
    SVGc_lineto,
    SVGc_cubic,
    SVGc_quadratic,
    SVGc_arc
};

typedef bool (*perform_op_fun)(enum SVG_condensed_op op, const double *operands, void *ctxt);

/* The S,s,T,t operations need to know the previous control point, as
   well as what kind of command generated it. */
enum previous_controlpoint_type {
    controlpoint_none,
    controlpoint_cubic,
    controlpoint_quadratic
};

struct svg_state {
    char current_op;

    /* SVG's state variables */
    double currentpoint_x, currentpoint_y, controlpoint_x, controlpoint_y;
    enum previous_controlpoint_type have_previous_control_point;
    bool have_currentpoint;
};

/* For assertion failures. We only use assert() for things that should
   literally not be possible. For failures which could happen on bad
   input or if Quartz hates the path, we return false. */
#define NOTREACHED 0


#line 134 "OQSVGPath.rl"


static bool svg_path_operation(struct svg_state *svg, double *operands, perform_op_fun performer, void *ctxt)
{
    /* If we have a full set of operands, perform the operation */
    if (1) {
        /* Most operators require a currentpoint. */
        if (!svg->have_currentpoint && ( svg->current_op != 'M' && svg->current_op != 'm' )) {
            return false;
        }

        /* SVG allows a wide variety of abbreviation and compaction for operantions. */
        /* We unpack those into a more uniform representation before calling the callback. */

        enum SVG_condensed_op condensed_opcode;

        switch (svg->current_op) {

        /* Moveto commands: SVG TR 8.3.3 */
        /* Movetos with multiple sets of args act as (moveto lineto+).
           We can modify the current_op here since further code for
           this action only uses the condensed opcode. */
        case 'M':
            condensed_opcode = SVGc_moveto;
            svg->current_op = 'L';
            break;
        case 'm':
            if (svg->have_currentpoint) { /* Currentpoint is optional here. */
                operands[0] += svg->currentpoint_x;
                operands[1] += svg->currentpoint_y;
            }
            condensed_opcode = SVGc_moveto;
            /* but even if we fell back to absolute moveto, the implied lineto is relative */
            svg->current_op = 'l';
            break;
        
        /* Lineto commands: SVG TR 8.3.4 */
        case 'l':
            operands[0] += svg->currentpoint_x;
            operands[1] += svg->currentpoint_y;
            condensed_opcode = SVGc_lineto;
            break;
        case 'L':
            condensed_opcode = SVGc_lineto;
            break;

        case 'H': /* Horizontal line */
            operands[1] = svg->currentpoint_y;
            condensed_opcode = SVGc_lineto;
            break;
        case 'V': /* Vertical line */
            operands[1] = operands[0];
            operands[0] = svg->currentpoint_x;
            condensed_opcode = SVGc_lineto;
            break;
        case 'h': /* Relative horizontal line */
            operands[0] += svg->currentpoint_x;
            operands[1] = svg->currentpoint_y;
            condensed_opcode = SVGc_lineto;
            break;
        case 'v': /* Relative vertical line */
            operands[1] = operands[0] + svg->currentpoint_y;
            operands[0] = svg->currentpoint_x;
            condensed_opcode = SVGc_lineto;
            break;
           
        /* Cubic curve commands: SVG TR 8.3.6 */
        case 'c':
            operands[0] += svg->currentpoint_x;
            operands[1] += svg->currentpoint_y;
            operands[2] += svg->currentpoint_x;
            operands[3] += svg->currentpoint_y;
            operands[4] += svg->currentpoint_x;
            operands[5] += svg->currentpoint_y;
            condensed_opcode = SVGc_cubic;
            break;
        case 'C':
            condensed_opcode = SVGc_cubic;
            break;
        case 's':
            operands[0] += svg->currentpoint_x;
            operands[1] += svg->currentpoint_y;
            operands[2] += svg->currentpoint_x;
            operands[3] += svg->currentpoint_y;
            /* FALL THROUGH */
        case 'S':
            operands[5] = operands[3];
            operands[4] = operands[2];
            operands[3] = operands[1];
            operands[2] = operands[0];
            if (svg->have_previous_control_point == controlpoint_cubic) {
                operands[0] = 2 * svg->currentpoint_x - svg->controlpoint_x;
                operands[1] = 2 * svg->currentpoint_y - svg->controlpoint_y;
            } else {
                operands[0] = svg->currentpoint_x;
                operands[1] = svg->currentpoint_y;
            }
            condensed_opcode = SVGc_cubic;
            break;

        /* Quadratic curve commands: SVG TR 8.3.7 */
        case 'q':
            operands[0] += svg->currentpoint_x;
            operands[1] += svg->currentpoint_y;
            operands[2] += svg->currentpoint_x;
            operands[3] += svg->currentpoint_y;
            condensed_opcode = SVGc_quadratic;
            break;
        case 'Q':
            condensed_opcode = SVGc_quadratic;
            break;
        case 't':
            operands[0] += svg->currentpoint_x;
            operands[1] += svg->currentpoint_y;
            /* FALL THROUGH */
        case 'T':
            operands[3] = operands[1];
            operands[2] = operands[0];
            if (svg->have_previous_control_point == controlpoint_quadratic) {
                operands[0] = 2 * svg->currentpoint_x - svg->controlpoint_x;
                operands[1] = 2 * svg->currentpoint_y - svg->controlpoint_y;
            } else {
                operands[0] = svg->controlpoint_x;
                operands[1] = svg->controlpoint_y;
            }
            condensed_opcode = SVGc_quadratic;
            break;

        case 'a':
            operands[5] += svg->currentpoint_x;
            operands[6] += svg->currentpoint_y;
            /* FALL THROUGH */
        case 'A':
            /* Pass the currentpoint to the arcto command, since CoreGraphics doesn't have an
               exact equivalent of this one and we need the currentpoint to compute an
               emulation. */
            operands[7] = svg->currentpoint_x;
            operands[8] = svg->currentpoint_y;
            condensed_opcode = SVGc_arc;
            break;

        default:
            /* This should not be able to happen - the scanner won't reach this state if
               the operation wasn't one we expect. */
            assert(NOTREACHED);
            return false;
        }

        if (!(*performer)(condensed_opcode, operands, ctxt)) {
            /* The callout failed for some reason. */
            return false;
        }

        /* All of these operations set the currentpoint. The only SVG
           op that doesn't is closepath, and it's handled by a
           different parser action. */
        svg->have_currentpoint = true;
        switch (condensed_opcode) {
        case SVGc_moveto:
        case SVGc_lineto:
            svg->currentpoint_x = operands[0];
            svg->currentpoint_y = operands[1];
            svg->controlpoint_x = NAN;
            svg->controlpoint_y = NAN;
            svg->have_previous_control_point = controlpoint_none;
            break;

        case SVGc_cubic:
            svg->controlpoint_x = operands[2];
            svg->controlpoint_y = operands[3];
            svg->currentpoint_x = operands[4];
            svg->currentpoint_y = operands[5];
            svg->have_previous_control_point = controlpoint_cubic;
            break;

        case SVGc_quadratic:
            svg->controlpoint_x = operands[0];
            svg->controlpoint_y = operands[1];
            svg->currentpoint_x = operands[2];
            svg->currentpoint_y = operands[3];
            svg->have_previous_control_point = controlpoint_quadratic;
            break;

        case SVGc_arc:
            svg->currentpoint_x = operands[5];
            svg->currentpoint_y = operands[6];
            svg->controlpoint_x = NAN;
            svg->controlpoint_y = NAN;
            svg->have_previous_control_point = controlpoint_none;
            break;

        default:
            assert(NOTREACHED);
            return false;
        }

    }
    
    return true;
}


#line 406 "OQSVGPath.rl"



#line 267 "OQSVGPath.m"
static const char _svgpath_actions[] = {
	0, 1, 0, 1, 1, 1, 2, 1, 
	3, 1, 4, 1, 5, 1, 6, 1, 
	7, 1, 8, 1, 9, 2, 1, 0, 
	2, 1, 9, 2, 2, 0, 2, 2, 
	9, 2, 9, 3, 2, 9, 4, 2, 
	9, 5, 2, 9, 6, 2, 9, 7, 
	2, 9, 8, 3, 1, 9, 3, 3, 
	1, 9, 4, 3, 1, 9, 5, 3, 
	1, 9, 6, 3, 1, 9, 7, 3, 
	1, 9, 8, 3, 2, 9, 3, 3, 
	2, 9, 4, 3, 2, 9, 5, 3, 
	2, 9, 6, 3, 2, 9, 7, 3, 
	2, 9, 8
};

static const unsigned char _svgpath_key_offsets[] = {
	0, 0, 9, 11, 14, 16, 20, 22, 
	45, 75, 105, 137, 167
};

static const unsigned char _svgpath_trans_keys[] = {
	32u, 36u, 43u, 45u, 46u, 9u, 13u, 48u, 
	57u, 48u, 57u, 46u, 48u, 57u, 48u, 57u, 
	43u, 45u, 48u, 57u, 48u, 57u, 32u, 65u, 
	67u, 72u, 81u, 83u, 84u, 86u, 90u, 97u, 
	99u, 104u, 113u, 115u, 116u, 118u, 122u, 9u, 
	13u, 76u, 77u, 108u, 109u, 32u, 36u, 44u, 
	46u, 65u, 67u, 72u, 81u, 83u, 84u, 86u, 
	90u, 97u, 99u, 104u, 113u, 115u, 116u, 118u, 
	122u, 9u, 13u, 43u, 45u, 48u, 57u, 76u, 
	77u, 108u, 109u, 32u, 36u, 44u, 46u, 65u, 
	67u, 72u, 81u, 83u, 84u, 86u, 90u, 97u, 
	99u, 104u, 113u, 115u, 116u, 118u, 122u, 9u, 
	13u, 43u, 45u, 48u, 57u, 76u, 77u, 108u, 
	109u, 32u, 36u, 44u, 46u, 65u, 67u, 69u, 
	72u, 81u, 83u, 84u, 86u, 90u, 97u, 99u, 
	101u, 104u, 113u, 115u, 116u, 118u, 122u, 9u, 
	13u, 43u, 45u, 48u, 57u, 76u, 77u, 108u, 
	109u, 32u, 36u, 44u, 46u, 65u, 67u, 72u, 
	81u, 83u, 84u, 86u, 90u, 97u, 99u, 104u, 
	113u, 115u, 116u, 118u, 122u, 9u, 13u, 43u, 
	45u, 48u, 57u, 76u, 77u, 108u, 109u, 32u, 
	36u, 44u, 46u, 65u, 67u, 69u, 72u, 81u, 
	83u, 84u, 86u, 90u, 97u, 99u, 101u, 104u, 
	113u, 115u, 116u, 118u, 122u, 9u, 13u, 43u, 
	45u, 48u, 57u, 76u, 77u, 108u, 109u, 0
};

static const char _svgpath_single_lengths[] = {
	0, 5, 0, 1, 0, 2, 0, 17, 
	20, 20, 22, 20, 22
};

static const char _svgpath_range_lengths[] = {
	0, 2, 1, 1, 1, 1, 1, 3, 
	5, 5, 5, 5, 5
};

static const unsigned char _svgpath_index_offsets[] = {
	0, 0, 8, 10, 13, 15, 19, 21, 
	42, 68, 94, 122, 148
};

static const char _svgpath_indicies[] = {
	0, 2, 3, 3, 4, 0, 5, 1, 
	6, 1, 7, 8, 1, 9, 1, 10, 
	10, 11, 1, 11, 1, 12, 13, 14, 
	15, 17, 17, 16, 15, 18, 13, 14, 
	15, 17, 17, 16, 15, 18, 12, 16, 
	16, 1, 19, 20, 22, 23, 25, 26, 
	27, 29, 29, 28, 27, 30, 25, 26, 
	27, 29, 29, 28, 27, 30, 19, 21, 
	24, 28, 28, 1, 31, 2, 0, 4, 
	32, 33, 34, 36, 36, 35, 34, 37, 
	32, 33, 34, 36, 36, 35, 34, 37, 
	31, 3, 5, 35, 35, 1, 38, 39, 
	41, 42, 43, 44, 45, 46, 48, 48, 
	47, 46, 49, 43, 44, 45, 46, 48, 
	48, 47, 46, 49, 38, 40, 9, 47, 
	47, 1, 38, 39, 41, 42, 43, 44, 
	46, 48, 48, 47, 46, 49, 43, 44, 
	46, 48, 48, 47, 46, 49, 38, 40, 
	11, 47, 47, 1, 38, 39, 41, 9, 
	43, 44, 45, 46, 48, 48, 47, 46, 
	49, 43, 44, 45, 46, 48, 48, 47, 
	46, 49, 38, 40, 8, 47, 47, 1, 
	0
};

static const char _svgpath_trans_targs[] = {
	1, 0, 2, 3, 4, 12, 8, 4, 
	12, 10, 6, 11, 7, 1, 1, 1, 
	1, 1, 7, 9, 2, 3, 1, 4, 
	8, 1, 1, 1, 1, 1, 7, 9, 
	1, 1, 1, 1, 1, 7, 9, 2, 
	3, 1, 4, 1, 1, 5, 1, 1, 
	1, 7
};

static const char _svgpath_trans_actions[] = {
	0, 0, 0, 1, 1, 1, 1, 0, 
	0, 0, 0, 0, 0, 15, 13, 7, 
	9, 11, 17, 5, 5, 27, 5, 27, 
	0, 91, 87, 75, 79, 83, 95, 0, 
	45, 42, 33, 36, 39, 48, 3, 3, 
	21, 3, 21, 67, 63, 0, 51, 55, 
	59, 71
};

static const char _svgpath_eof_actions[] = {
	0, 0, 0, 0, 0, 0, 0, 0, 
	30, 19, 24, 24, 24
};

static const int svgpath_start = 7;
static const int svgpath_first_final = 7;
static const int svgpath_error = 0;

static const int svgpath_en_svgpath = 7;


#line 409 "OQSVGPath.rl"

static int OQScanSVGPath(const unsigned char *d, size_t d_length,
                         perform_op_fun performer, void *ctxt,
                         const double *parameters, unsigned parameter_count)

{
    /* Ragel's state variables */
    int cs;
    const unsigned char *p = d;
    const unsigned char * const eof = d + d_length;

    /* Our state variables */
    int operands_expected, operands_seen;
    const char *number_start;
    double operands[9];

    /* SVG's state variables */
    struct svg_state svg;

    /* Initial state */
    svg.have_currentpoint = false;
    svg.have_previous_control_point = controlpoint_none;
    
#line 414 "OQSVGPath.m"
	{
	cs = svgpath_start;
	}

#line 431 "OQSVGPath.rl"


    /* None of these actually need to be initialized, but (except for Ragel output style -G2)
       the compiler can't analyze the state tables in order to prove it. */
    svg.current_op = 0;
    operands_expected = operands_seen = 0;
    number_start = NULL;
    svg.currentpoint_x = NAN;
    svg.currentpoint_y = NAN;
    svg.controlpoint_x = NAN;
    svg.controlpoint_y = NAN;

    
#line 433 "OQSVGPath.m"
	{
	int _klen;
	unsigned int _trans;
	const char *_acts;
	unsigned int _nacts;
	const unsigned char *_keys;

	if ( p == ( eof) )
		goto _test_eof;
	if ( cs == 0 )
		goto _out;
_resume:
	_keys = _svgpath_trans_keys + _svgpath_key_offsets[cs];
	_trans = _svgpath_index_offsets[cs];

	_klen = _svgpath_single_lengths[cs];
	if ( _klen > 0 ) {
		const unsigned char *_lower = _keys;
		const unsigned char *_mid;
		const unsigned char *_upper = _keys + _klen - 1;
		while (1) {
			if ( _upper < _lower )
				break;

			_mid = _lower + ((_upper-_lower) >> 1);
			if ( (*p) < *_mid )
				_upper = _mid - 1;
			else if ( (*p) > *_mid )
				_lower = _mid + 1;
			else {
				_trans += (unsigned int)(_mid - _keys);
				goto _match;
			}
		}
		_keys += _klen;
		_trans += _klen;
	}

	_klen = _svgpath_range_lengths[cs];
	if ( _klen > 0 ) {
		const unsigned char *_lower = _keys;
		const unsigned char *_mid;
		const unsigned char *_upper = _keys + (_klen<<1) - 2;
		while (1) {
			if ( _upper < _lower )
				break;

			_mid = _lower + (((_upper-_lower) >> 1) & ~1);
			if ( (*p) < _mid[0] )
				_upper = _mid - 2;
			else if ( (*p) > _mid[1] )
				_lower = _mid + 2;
			else {
				_trans += (unsigned int)((_mid - _keys)>>1);
				goto _match;
			}
		}
		_trans += _klen;
	}

_match:
	_trans = _svgpath_indicies[_trans];
	cs = _svgpath_trans_targs[_trans];

	if ( _svgpath_trans_actions[_trans] == 0 )
		goto _again;

	_acts = _svgpath_actions + _svgpath_trans_actions[_trans];
	_nacts = (unsigned int) *_acts++;
	while ( _nacts-- > 0 )
	{
		switch ( *_acts++ )
		{
	case 0:
#line 69 "OQSVGPath.rl"
	{
    /* Note position */
    number_start = (const char *)p;
    /* printf(" Began number at %u (op='%c')\n", (unsigned)(p-d), svg.current_op); */
}
	break;
	case 1:
#line 74 "OQSVGPath.rl"
	{
    /* Parse the number into the operand buffer */
    if (p < eof && (*p == ' ' || *p == ',')) {
        /* The number is delimited; we can call strtod() directly */
        operands[operands_seen++] = strtod(number_start, NULL);
    } else {
        char strtod_buffer[MAX_NUMBER_LENGTH];
        size_t number_len = ((const char *)p - number_start);
        if (number_len >= (MAX_NUMBER_LENGTH-1)) {
            /* An unreasonably long number. */
            return false;
        } else {
            memcpy(strtod_buffer, number_start, number_len);
            strtod_buffer[number_len] = 0x00;
            operands[operands_seen++] = strtod(strtod_buffer, NULL);
        }
    }
    
    /* If we have a full set of operands, perform the operation */
    if (operands_seen == operands_expected) {
        if (!svg_path_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}
	break;
	case 2:
#line 99 "OQSVGPath.rl"
	{
    /* Parse the parameter number */
    unsigned long parameter_index;
    
    if (p < eof && (*p == ' ' || *p == ',')) {
        /* The number is delimited; we can call strtoul() directly */
        parameter_index = strtoul(number_start, NULL, 10);
    } else {
        char strtoul_buffer[MAX_NUMBER_LENGTH];
        size_t number_len = ((const char *)p - number_start);
        if (number_len >= (MAX_NUMBER_LENGTH-1)) {
            /* An unreasonably long number. */
            return false;
        } else {
            memcpy(strtoul_buffer, number_start, number_len);
            strtoul_buffer[number_len] = 0x00;
            parameter_index = strtoul(strtoul_buffer, NULL, 10);
        }
    }
    
    if (parameter_index >= parameter_count) {
        /* Index is past last parameter */
        return false;
    }
    
    operands[operands_seen++] = parameters[parameter_index];
    
    /* If we have a full set of operands, perform the operation */
    if (operands_seen == operands_expected) {
        if (!svg_path_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}
	break;
	case 3:
#line 338 "OQSVGPath.rl"
	{ svg.current_op = *p; operands_expected = 1; operands_seen = 0; }
	break;
	case 4:
#line 339 "OQSVGPath.rl"
	{ svg.current_op = *p; operands_expected = 2; operands_seen = 0; }
	break;
	case 5:
#line 340 "OQSVGPath.rl"
	{ svg.current_op = *p; operands_expected = 4; operands_seen = 0; }
	break;
	case 6:
#line 341 "OQSVGPath.rl"
	{ svg.current_op = *p; operands_expected = 6; operands_seen = 0; }
	break;
	case 7:
#line 342 "OQSVGPath.rl"
	{ svg.current_op = *p; operands_expected = 7; operands_seen = 0; }
	break;
	case 8:
#line 344 "OQSVGPath.rl"
	{
    bool ok = (*performer)(SVGc_closepath, NULL, ctxt );
    if (!ok)
        return false;
    svg.have_currentpoint = false;
    svg.have_previous_control_point = controlpoint_none;
}
	break;
	case 9:
#line 351 "OQSVGPath.rl"
	{
    if (operands_seen != 0) {
        return false;
    }
}
	break;
#line 618 "OQSVGPath.m"
		}
	}

_again:
	if ( cs == 0 )
		goto _out;
	if ( ++p != ( eof) )
		goto _resume;
	_test_eof: {}
	if ( p == eof )
	{
	const char *__acts = _svgpath_actions + _svgpath_eof_actions[cs];
	unsigned int __nacts = (unsigned int) *__acts++;
	while ( __nacts-- > 0 ) {
		switch ( *__acts++ ) {
	case 1:
#line 74 "OQSVGPath.rl"
	{
    /* Parse the number into the operand buffer */
    if (p < eof && (*p == ' ' || *p == ',')) {
        /* The number is delimited; we can call strtod() directly */
        operands[operands_seen++] = strtod(number_start, NULL);
    } else {
        char strtod_buffer[MAX_NUMBER_LENGTH];
        size_t number_len = ((const char *)p - number_start);
        if (number_len >= (MAX_NUMBER_LENGTH-1)) {
            /* An unreasonably long number. */
            return false;
        } else {
            memcpy(strtod_buffer, number_start, number_len);
            strtod_buffer[number_len] = 0x00;
            operands[operands_seen++] = strtod(strtod_buffer, NULL);
        }
    }
    
    /* If we have a full set of operands, perform the operation */
    if (operands_seen == operands_expected) {
        if (!svg_path_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}
	break;
	case 2:
#line 99 "OQSVGPath.rl"
	{
    /* Parse the parameter number */
    unsigned long parameter_index;
    
    if (p < eof && (*p == ' ' || *p == ',')) {
        /* The number is delimited; we can call strtoul() directly */
        parameter_index = strtoul(number_start, NULL, 10);
    } else {
        char strtoul_buffer[MAX_NUMBER_LENGTH];
        size_t number_len = ((const char *)p - number_start);
        if (number_len >= (MAX_NUMBER_LENGTH-1)) {
            /* An unreasonably long number. */
            return false;
        } else {
            memcpy(strtoul_buffer, number_start, number_len);
            strtoul_buffer[number_len] = 0x00;
            parameter_index = strtoul(strtoul_buffer, NULL, 10);
        }
    }
    
    if (parameter_index >= parameter_count) {
        /* Index is past last parameter */
        return false;
    }
    
    operands[operands_seen++] = parameters[parameter_index];
    
    /* If we have a full set of operands, perform the operation */
    if (operands_seen == operands_expected) {
        if (!svg_path_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}
	break;
	case 9:
#line 351 "OQSVGPath.rl"
	{
    if (operands_seen != 0) {
        return false;
    }
}
	break;
#line 707 "OQSVGPath.m"
		}
	}
	}

	_out: {}
	}

#line 449 "OQSVGPath.rl"


    /* At this point, we could be in a final state (success), an error state (failure),
    ** or a non-final state (also failure, because we require a complete path spec on input).
    */
    if (cs >= 7 ) {
        return true;
    } else {
        return false;
    }
}

static bool applyToCGPath(enum SVG_condensed_op op, const double *operands, void *ctxt)
{
    CGMutablePathRef p = (CGMutablePathRef)ctxt;
    switch(op) {
        case SVGc_closepath:  CGPathCloseSubpath(p); break;
        case SVGc_moveto:     CGPathMoveToPoint(p, NULL, (CGFloat)operands[0], (CGFloat)operands[1]); break;
        case SVGc_lineto:     CGPathAddLineToPoint(p, NULL, (CGFloat)operands[0], (CGFloat)operands[1]); break;
        case SVGc_cubic:      CGPathAddCurveToPoint(p, NULL, (CGFloat)operands[0], (CGFloat)operands[1], (CGFloat)operands[2], (CGFloat)operands[3], (CGFloat)operands[4], (CGFloat)operands[5]); break;
        case SVGc_quadratic:  CGPathAddQuadCurveToPoint(p, NULL, (CGFloat)operands[0], (CGFloat)operands[1], (CGFloat)operands[2], (CGFloat)operands[3]); break;
        case SVGc_arc:
        {
            struct OQEllipseParameters arc;
            OQComputeEllipseParameters((CGFloat)(operands[5] - operands[7]),
                                       (CGFloat)(operands[6] - operands[8]),
                                       (CGFloat)(operands[0]), (CGFloat)(operands[1]),  (CGFloat)(operands[2]),
                                       operands[3]?YES:NO, operands[4]?YES:NO,
                                       &arc);
            if (!arc.numSegments) return false;
            CGFloat x0 = (CGFloat)operands[7];
            CGFloat y0 = (CGFloat)operands[8];
            for (unsigned int i = 0; i < arc.numSegments; i++)
                CGPathAddCurveToPoint(p, NULL,
                                      arc.points[3*i  ].x + x0, arc.points[3*i  ].x + y0,
                                      arc.points[3*i+1].x + x0, arc.points[3*i+1].x + y0,
                                      arc.points[3*i+2].x + x0, arc.points[3*i+2].x + y0);
            break;
        }
        default:              return false;
    }
    return true;
}

static bool applyToCGContext(enum SVG_condensed_op op, const double *operands, void *ctxt)
{
    CGContextRef cg = (CGContextRef)ctxt;
    switch(op) {
        case SVGc_closepath:  CGContextClosePath(cg); break;
        case SVGc_moveto:     CGContextMoveToPoint(cg, (CGFloat)operands[0], (CGFloat)operands[1]); break;
        case SVGc_lineto:     CGContextAddLineToPoint(cg, (CGFloat)operands[0], (CGFloat)operands[1]); break;
        case SVGc_cubic:      CGContextAddCurveToPoint(cg, (CGFloat)operands[0], (CGFloat)operands[1], (CGFloat)operands[2], (CGFloat)operands[3], (CGFloat)operands[4], (CGFloat)operands[5]); break;
        case SVGc_quadratic:  CGContextAddQuadCurveToPoint(cg, (CGFloat)operands[0], (CGFloat)operands[1], (CGFloat)operands[2], (CGFloat)operands[3]); break;
        case SVGc_arc:
        {
            struct OQEllipseParameters arc;
            OQComputeEllipseParameters((CGFloat)(operands[5] - operands[7]),
                                       (CGFloat)(operands[6] - operands[8]),
                                       (CGFloat)(operands[0]), (CGFloat)(operands[1]),  (CGFloat)(operands[2]),
                                       operands[3]?YES:NO, operands[4]?YES:NO,
                                       &arc);
            if (!arc.numSegments) return false;
            CGFloat x0 = (CGFloat)operands[7];
            CGFloat y0 = (CGFloat)operands[8];
            for (unsigned int i = 0; i < arc.numSegments; i++)
                CGContextAddCurveToPoint(cg,
                                         arc.points[3*i  ].x + x0, arc.points[3*i  ].x + y0,
                                         arc.points[3*i+1].x + x0, arc.points[3*i+1].x + y0,
                                         arc.points[3*i+2].x + x0, arc.points[3*i+2].x + y0);
            break;
        }
        default:              return false;
    }
    return true;
}

CGPathRef OQCGPathCreateFromSVGPath(const unsigned char *d, size_t d_length)
{
    CGMutablePathRef cgp = CGPathCreateMutable();
    
    if (OQScanSVGPath(d, d_length, applyToCGPath, (void *)cgp, NULL, 0)) {
        return cgp;
    } else {
        CGPathRelease(cgp);
        return NULL;
    }
}

CGPathRef OQCGPathCreateFromSVGPathString(NSString *string)
{
    const char *cString = [string UTF8String];
    return OQCGPathCreateFromSVGPath((void *)cString, strlen(cString));
}

int OQCGContextAddSVGPath(CGContextRef cgContext, const unsigned char *d, size_t d_length)
{
    return OQScanSVGPath(d, d_length, applyToCGContext, (void *)cgContext, NULL, 0);
}

#if 0

static bool print(enum SVG_condensed_op op, const double *operands, void *ctxt)
{
    switch(op) {
    case SVGc_closepath:  printf("closepath\n"); break;
    case SVGc_moveto:     printf("moveto %.1f %.1f\n", operands[0], operands[1]); break;
    case SVGc_lineto:     printf("lineto %.1f %.1f\n", operands[0], operands[1]); break;
    case SVGc_cubic:      printf("cubic %.1f,%.1f %.1f,%.1f %.1f,%.1f\n", 
                                 operands[0], operands[1], operands[2], operands[3], operands[4], operands[5]);
                          break;
    case SVGc_quadratic:  printf("quadratic %.1f,%.1f %.1f,%.1f\n",
                                 operands[0], operands[1], operands[2], operands[3]);
                          break;
    case SVGc_arc:        printf("svg-arc %.1f %.1f %.1f %s,%s %.1f %.1f\n",
                                 operands[0], operands[1], operands[2],
                                 operands[3]?"large":"small", operands[4]?"pos":"neg",
                                 operands[5], operands[6]);
                          break;
    default:              return false;
    }
    return true;
}


int main(int argc, char **argv)
{
  int pcount;
  double *pargs;
  
  if (argc > 2) {
    int j;
    pcount = argc-2;
    pargs = alloca(sizeof(*pargs) * pcount);
    for(j = 0; j < pcount; j++)
      pargs[j] = strtod(argv[j+2], NULL);
  } else {
    pcount = 0;
    pargs = NULL;
  }
    

  int i = OQScanSVGPath((const unsigned char *)argv[1], strlen(argv[1]), print, NULL, pargs, pcount);
    printf(" --> %d\n", i);
    exit(0);
}

#endif
