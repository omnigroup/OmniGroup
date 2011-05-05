// Copyright 2011 Omni Development, Inc.  All rights reserved.
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

%%{

machine svgpath;
alphtype unsigned char;

#
#  Parse actions. Most of the work happens in got_number, if it sees that we've
#  accumulated emough operands in the operands[] array to satisfy the current
#  SVG operator.
#
#  Note that these are inlined directly into the body of OQScanSVGPath(), so if we
#  hit a failure condition we can just return 'false'.
#
action start_number {
    /* Note position */
    number_start = (const char *)p;
    /* printf(" Began number at %u (op='%c')\n", (unsigned)(p-d), svg.current_op); */
}
action got_number {
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
        if (!do_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}
action got_parameter {
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
        if (!do_operation(&svg, operands, performer, ctxt))
            return false;
        operands_seen = 0;
    }
}

}%%

static bool do_operation(struct svg_state *svg, double *operands, perform_op_fun performer, void *ctxt)
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

%%{

# When we see an operator we record how many operands it takes per invocation.
action op_expect_1operand  { svg.current_op = *p; operands_expected = 1; operands_seen = 0; }
action op_expect_2operands { svg.current_op = *p; operands_expected = 2; operands_seen = 0; }
action op_expect_4operands { svg.current_op = *p; operands_expected = 4; operands_seen = 0; }
action op_expect_6operands { svg.current_op = *p; operands_expected = 6; operands_seen = 0; }
action op_expect_7operands { svg.current_op = *p; operands_expected = 7; operands_seen = 0; }
# Except for closepath, which takes no operands, so we just execute it when we see it.
action op_closepath {
    bool ok = (*performer)(SVGc_closepath, NULL, ctxt );
    if (!ok)
        return false;
    svg.have_currentpoint = false;
    svg.have_previous_control_point = controlpoint_none;
}
action assert_operands_consumed {
    if (operands_seen != 0) {
        return false;
    }
}

# We use Ragel to recognize a number but not to actually parse it. It's more compact
# (and probably faster) to pass that task off to strtod().
digits = digit+ ;
sign = '+' | '-' ;
exponent = ( 'e' | 'E' ) sign? digits ;
inner_number = digits
             | digits '.' digits?
             | '.' digits
             ;
number_literal = ( sign? inner_number exponent? ) >start_number %got_number ;
number_parameter = '$' ( digits >start_number %got_parameter ) ;
number = number_literal | number_parameter ;

# This is the tricky part of the SVG path spec: adjacent numbers may
# be separated by whitespace, an optional comma, or nothing at all if
# the concatenation is unambiguous.
#
# The Ragel left-guarded concatenation operator almost does what we
# want here: any transition which begins to recognize a subsequent
# number while simultaneously recognizing more of the current number
# is trimmed. Unfortunately it's hard to use that while including the
# numbersep rule, so we use roughly equivalent priority assignments
# instead. Transitions within a number are given a high priority and
# entering/leaving transitions are given a low priority.
#
# This will accept some truly ambiguous strings like '3.2.3' (parsed
# as 3.2 followed by .3). I'm not sure what the SVG spec requires for
# that, but I suspect we're supposed to reject it.  OTOH, it's not a
# big problem if we accept some malformed input as long as we accept
# all correctly-formed input.

numbersep = space* ','? space* ;
numbers = number $(numbers,1) %(numbers,-1) ( numbersep number $(numbers,1) %(numbers,-1) >(numbers,-1) )* ;

svg_noarg_operator = [Zz] >op_closepath;
svg_arg_operator = [HhVv] >op_expect_1operand
                 | [MmLlTt] >op_expect_2operands
                 | [SsQq] >op_expect_4operands
                 | [Cc] >op_expect_6operands
                 | [Aa] >op_expect_7operands
                 ;

svgpath := space*  (
             ( 
                ( svg_arg_operator space* numbers space* ) %assert_operands_consumed |
                ( svg_noarg_operator space* )
             )
           )* ;

}%%

%%write data;

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
    %%{ write init; }%%

    /* None of these actually need to be initialized, but (except for Ragel output style -G2)
       the compiler can't analyze the state tables in order to prove it. */
    svg.current_op = 0;
    operands_expected = operands_seen = 0;
    number_start = NULL;
    svg.currentpoint_x = NAN;
    svg.currentpoint_y = NAN;
    svg.controlpoint_x = NAN;
    svg.controlpoint_y = NAN;

    %%{
        # Tell Ragel that the buffer continues to the end of the input
        variable pe eof;

        # Run the state machine on the input
        write exec;
    }%%

    /* At this point, we could be in a final state (success), an error state (failure),
    ** or a non-final state (also failure, because we require a complete path spec on input).
    */
    if (cs >= %%{ write first_final; }%% ) {
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
        case SVGc_arc:        assert(0); /* need to implement this */ break;
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
        case SVGc_arc:        assert(0); /* need to implement this */ break;
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
