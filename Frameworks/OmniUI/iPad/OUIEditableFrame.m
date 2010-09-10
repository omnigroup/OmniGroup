// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIEditableFrame.h"
#import "OUITextThumb.h"

#import "OUEFTextPosition.h"
#import "OUEFTextRange.h"
#import "OUITextInputStringTokenizer.h"
#import "OUITextCursorOverlay.h"
#import "OUILoupeOverlay.h"
#import "OUEFTextSpan.h"
#import "OUIDirectTapGestureRecognizer.h"

#import "OUIColorInspectorSlice.h"
#import "OUIFontInspectorSlice.h"
#import "OUIParagraphStyleInspectorSlice.h"

#import <OmniUI/OUITextLayout.h>
#import <OmniQuartz/OQColor.h>
#import <Foundation/NSAttributedString.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFNull.h>
#import <MobileCoreServices/UTCoreTypes.h>

#include <execinfo.h>
#include <stdlib.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_TEXT(format, ...) NSLog(@"TEXT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_TEXT(format, ...)
#endif

/* TODO: If low memory and not first responder, clear out actionRecognizers[] */

/* TODO: If low memory and not first responder, clear out selection layers */

/* TODO: If low memory and not complex selection, clear out the complex selection layer */

#define CARET_ACTIVITY_SOLID_INTERVAL 0.75

#if 1

#pragma mark Debugging helpers

static const struct enumName {
    int value;
    CFStringRef name;
} directions[] = {
    { UITextStorageDirectionForward, CFSTR("Forward") },
    { UITextStorageDirectionBackward, CFSTR("Backward") },
    { UITextLayoutDirectionRight, CFSTR("Right") },
    { UITextLayoutDirectionLeft, CFSTR("Left") },
    { UITextLayoutDirectionUp, CFSTR("Up") },
    { UITextLayoutDirectionDown, CFSTR("Down") },
    { 0, NULL }    
}, granularities[] = {
    { UITextGranularityCharacter, CFSTR("Character") },
    { UITextGranularityWord, CFSTR("Word") },
    { UITextGranularitySentence, CFSTR("Sentence") },
    { UITextGranularityParagraph, CFSTR("Paragraph") },
    { UITextGranularityLine, CFSTR("Line") },
    { UITextGranularityDocument, CFSTR("Document") },
    { 0, NULL }    
};

static NSString *nameof(NSInteger v, const struct enumName *ns)
{
    int value = (int)v;
    while(ns->name) {
        if (ns->value == value)
            return (NSString *)(ns->name);
        ns ++;
    }
    return [NSString stringWithFormat:@"<%d>", value];
}

static void btrace(void)
{
#define NUMB 24
    void *fps[NUMB];
    int numb = backtrace(fps, NUMB);
    backtrace_symbols_fd(fps + 1, numb - 1, 2);
}

#endif

@interface OUIEditableFrame (/*Private*/)
- (CFRange)_lineRangeForStringRange:(NSRange)queryRange;
- (CGRect)_caretRectForPosition:(OUEFTextPosition *)position affinity:(int)affinity bloomScale:(double)s;
- (CGRect)_boundsOfRange:(OUEFTextRange *)range;
- (void)_setNeedsDisplayForRange:(OUEFTextRange *)range;
- (void)_setSolidCaret:(int)delta;
- (void)_setSelectionToIndex:(NSUInteger)ix;
- (void)_setSelectedTextRange:(OUEFTextRange *)newRange notifyDelegate:(BOOL)shouldNotify;
- (void)_idleTap;
- (void)_activeTap:(UITapGestureRecognizer *)r;
- (void)_inspectTap:(UILongPressGestureRecognizer *)r;
- (void)_drawSelectionInContext:(CGContextRef)ctx;
- (void)_drawDecorations:(CGContextRef)ctx;
- (void)_didChangeContent;
- (void)_updateLayout:(BOOL)computeDrawnFrame;
- (void)_moveInDirection:(UITextLayoutDirection)direction;
@end

@implementation OUIEditableFrame

static id do_init(OUIEditableFrame *self)
{
    self.contentMode = UIViewContentModeRedraw;
    self.clearsContextBeforeDrawing = YES;

    /* Need to have *some* fallback font. This more or less matches what UITextView does. */
    if (!self->defaultFont)
        self->defaultFont = CFRetain(OUIGlobalDefaultFont());
    
    self->generation = 1;
    self->markedRange.location = 0;
    self->markedRange.length = 0;
    self->layoutSize.width = 0;
    self->layoutSize.height = 0;
    self->flags.textNeedsUpdate = 1;
    self->flags.delegateRespondsToLayoutChanged = 0;
    self->flags.showSelectionThumbs = 1;
    self->flags.showInspector = 0;  // Temporarily disabling the text style inspector since it isn't quite ready for prime time
    self->selectionDirtyRect = CGRectNull;
    self->markedTextDirtyRect = CGRectNull;
    
    // Avoid ugly stretchy text
    self.contentMode = UIViewContentModeTopLeft;

    self->_linkTextAttributes = [[OUITextLayout defaultLinkTextAttributes] copy];
    
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self->tapSelectionGranularity = UITextGranularityWord;

    // You can turn autocorrection on, but it's currently pretty broken: see RADAR 7881864 (dup of 7696512), 7914098 (dup of 7673939).
    self.autocorrectionType = UITextAutocorrectionTypeNo;

    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    self.userInteractionEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return do_init(self);
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return do_init(self);
}

#pragma mark -
#pragma mark Utility functions and private methods

/* Returns true if CFIndex i is within NSRange r. (Notice the differing types.) */
static inline BOOL in_range(NSRange r, CFIndex i)
{
    if (i < 0)
        return 0;
    NSUInteger u = (NSUInteger)i;
    return (u >= r.location && ( u - r.location ) < r.length);
}

/* Returns the square of the distance between two points; useful if you only need it for comparison with other distances */
static inline CGFloat dist_sqr(CGPoint a, CGPoint b)
{
    CGFloat dx = (a.x - b.x);
    CGFloat dy = (a.y - b.y);
    return dx*dx + dy*dy;
}

/*
 Searches for the CTLine containing a given string index (queryIndex), confining the search to the range [l,h).
 The line's index is returned and a line ref is stored in *foundLine.
 If the index is not found, a value outside [l,h) returned and *foundLine is not modified.
 Note that the index is interpreted as referring to a character, not to an intercharacter space.
*/
static CFIndex bsearchLines(CFArrayRef lines, CFIndex l, CFIndex h, CFIndex queryIndex, CTLineRef *foundLine)
{
    CFIndex orig_h = h;
    
    while (h > l) {
        CFIndex m = ( h + l - 1 ) >> 1;
        CTLineRef line = CFArrayGetValueAtIndex(lines, m);
        CFRange lineRange = CTLineGetStringRange(line);
        
        if (lineRange.location > queryIndex) {
            h = m;
        } else if ((lineRange.location + lineRange.length) > queryIndex) {
            if (foundLine)
                *foundLine = line;
            return m;
        } else {
            l = m + 1;
        }
    }
    return ( l < orig_h )? kCFNotFound : l;
}

/* Similar to bsearchLines(), but finds a CTRun within a CTLine. */
/* We can't do a binary search, because runs are visually ordered, not logically ordered (experimentally true, but undocumented) */
/* Hopefully a given character index will only ever be claimed by one run... */
static CFIndex searchRuns(CFArrayRef runs, CFIndex l, CFIndex h, CFIndex queryIndex, CTRunRef *foundRun)
{
    while (l < h) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, l);
        CFRange runRange = CTRunGetStringRange(run);
        
        if (runRange.location <= queryIndex && (runRange.location+runRange.length) > queryIndex) {
            *foundRun = run;
            return l;
        }
        
        l ++;
    }

    return kCFNotFound;
}

enum runPosition {
    pastLeft = -1,
    middle = 0,
    pastRight = 1
};

/* Given a run's range and flags, returns whether a given (logical) string index is to the left, within, or to the right of the run */
static enum runPosition __attribute__((const)) runOffset(CTRunStatus runFlags, CFRange runRange, CFIndex pos)
{
    /* TODO: Deal with nonmonotonic layouts */
    
    if (pos < runRange.location) {
        if (runFlags & kCTRunStatusRightToLeft)
            return pastRight;
        else
            return pastLeft;
    }
    
    if (pos >= (runRange.location + runRange.length)) {
        if (runFlags & kCTRunStatusRightToLeft)
            return pastLeft;
        else
            return pastRight;
    }
    
    return middle;
}

/* These flags are passed to the rectanglesInRangeCallback to indicate why the left and right edges of a given rectangle are where they are. An edge might be the beginning or the end of the range being iterated over; they might be caused by a line break; or they could be caused by a run break in mixed-direction text (if neither RangeBoundary nor LineWrap are set). */
#define rectwalker_LeftIsRangeBoundary  ( 00001 )
#define rectwalker_RightIsRangeBoundary ( 00002 )
#define rectwalker_LeftIsLineWrap       ( 00004 )
#define rectwalker_RightIsLineWrap      ( 00010 )
#define rectwalker_FirstRectInLine      ( 00020 )
#define rectwalker_FirstLine            ( 00040 )

#define rectwalker_LeftFlags (rectwalker_LeftIsRangeBoundary|rectwalker_LeftIsLineWrap)
#define rectwalker_RightFlags (rectwalker_RightIsRangeBoundary|rectwalker_RightIsLineWrap)
#define rectwalker_LineFlags (rectwalker_FirstLine /* | rectwalker_LastLine */ )

typedef BOOL (*rectanglesInRangeCallback)(CGPoint origin, CGFloat width, CGFloat trailingWhitespaceWidth, CGFloat ascent, CGFloat descent, /* NSRange textRange, */ unsigned flags, void *p);

static CGFloat __attribute__((const)) min4(CGFloat a, CGFloat b, CGFloat c, CGFloat d)
{
    a = MIN(a, b);
    c = MIN(c, d);
    return MIN(a,c);
}
static CGFloat __attribute__((const)) max4(CGFloat a, CGFloat b, CGFloat c, CGFloat d)
{
    a = MAX(a, b);
    c = MAX(c, d);
    return MAX(a,c);
}

static CGFloat leftRunBoundary(CTLineRef line, CTRunRef run)
{
    /* There doesn't seem to be an explicit way to get the left boundary of a run, so we just return the x-position of its first glyph. */
    const CGPoint *positions = CTRunGetPositionsPtr(run);
    if (positions)
        return positions[0].x;
    
    CGPoint position[1];
    CTRunGetPositions(run, (CFRange){0, 1}, position);
    
    return position[0].x;
}

/* Macros for invoking the callback (usually with a 0 for the trailing whitespace width) */
#define RECT_tww(start, end, tww, flags) do{ CGFloat start_ = (start); BOOL shouldContinue = (*cb)( (CGPoint){ lineOrigin.x + start_, lineOrigin.y }, (end) - start_, tww, ascent, descent, (flags) | (rectsIssued? 0 : rectwalker_FirstRectInLine) | lineFlags, ctxt); if (!shouldContinue) return -1; rectsIssued ++; }while(0)
#define RECT(start, end, flags) RECT_tww(start, end, 0, flags)

static unsigned int rectanglesInLine(CTLineRef line, CGPoint lineOrigin, NSRange r, unsigned boundaryFlags, rectanglesInRangeCallback cb, void *ctxt)
{
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex runCount = CFArrayGetCount(runs);
    CGFloat ascent = NAN, descent = NAN;
    CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    int rectsIssued = 0;
    
    /* Since different runs have different layout directions, a selection of a single line can cover multiple noncontiguous rectangles. However, each rectangle boundary is either at the position of the selection's start/end, or it's at a run boundary. (I'm ignoring nonmonotonic runs since I don't know what situation might generate them or what the proper selection display is in those situations.) */
    
    CGFloat startPosSecondaryOffset, endPosSecondaryOffset;
    CGFloat startPosOffset = CTLineGetOffsetForStringIndex(line, r.location, &startPosSecondaryOffset);
    CGFloat endPosOffset = CTLineGetOffsetForStringIndex(line, r.location + r.length, &endPosSecondaryOffset);
    unsigned leftFlags = ( boundaryFlags & rectwalker_LeftFlags );   // Flags to apply to the leftmost rectangle
    unsigned rightFlags = ( boundaryFlags & rectwalker_RightFlags ); // Flags to apply to the rightmost rectangle
    unsigned lineFlags = ( boundaryFlags & rectwalker_LineFlags );   // Flags to apply to all rectangles in this line
    
    /* Loop through all the runs in the line, figuring out whether the range intersects the run's range at all, and if so, what it contributes to the list of rectangles we're delivering to the callback. */
    
    for(CFIndex i = 0; i < runCount; i++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, i);
        CFRange runRange = CTRunGetStringRange(run);
        CTRunStatus runFlags = CTRunGetStatus(run);
        
        enum runPosition p1 = runOffset(runFlags, runRange, r.location);
        enum runPosition p2 = runOffset(runFlags, runRange, r.location + r.length);
                
        CGFloat rectStart;
        int rectFlags;

        if (p1 == pastLeft) {
            if (p2 == pastLeft) {
                // If this run contains nothing from our range, we don't need to return it.
                continue;
            }
            rectStart = leftRunBoundary(line, run);
            rectFlags = 0; // Left edge of rect is synthetic (run boundary not range boundary)
            if (i == 0)
                rectFlags |= leftFlags; // But it may be a line wrap
            if (p2 == pastRight) {
                // Fall through to multiple-run case
            } else {
                // p2 == middle
                RECT(rectStart, MAX(endPosOffset, endPosSecondaryOffset), rectFlags | rectwalker_RightIsRangeBoundary);
                continue;
            }
        } else if (p1 == middle) {
            if (p2 == pastLeft) {
                rectFlags = rectwalker_RightIsRangeBoundary;
                if (i == 0)
                    rectFlags |= leftFlags; // First (leftmost) run in line may be wrapped from previous line
                RECT(leftRunBoundary(line, run), MAX(startPosOffset, startPosSecondaryOffset), rectFlags);
                continue;
            } else if (p2 == middle) {
                RECT(min4(startPosOffset, startPosSecondaryOffset, endPosOffset, endPosSecondaryOffset),
                     max4(startPosOffset, startPosSecondaryOffset, endPosOffset, endPosSecondaryOffset),
                     rectwalker_LeftIsRangeBoundary | rectwalker_RightIsRangeBoundary);
                continue;
            } else {
                // p2 == pastRight
                rectStart = MIN(startPosOffset, startPosSecondaryOffset);
                rectFlags = rectwalker_LeftIsRangeBoundary;
                // Fall through to multiple-run case
            }
        } else /* if (p1 == pastRight) */ {
            if (p2 == pastLeft) {
                rectStart = leftRunBoundary(line, run);
                rectFlags = 0; // Left edge of rect is synthetic (run boundary not range boundary)
                if (i == 0)
                    rectFlags |= leftFlags; // But leftmost run in line may be a line wrap
                // Fall through to multiple-run case
            } else if (p2 == middle) {
                rectStart = MIN(endPosOffset, endPosSecondaryOffset);
                rectFlags = rectwalker_LeftIsRangeBoundary;
                // Fall through to multiple-run case
            } else {
                // If this run contains nothing from our range, we don't need to return it.
                continue;
            }
        }
        
        // If we reach this point, either p1 or p2 was pastRight, so we've started a rect (offset stored in rectStart) but not finished it yet.
        BOOL ended = NO;
        for(i++; i < runCount; i++) {
            run = CFArrayGetValueAtIndex(runs, i);
            runRange = CTRunGetStringRange(run);
            runFlags = CTRunGetStatus(run);
            
            enum runPosition p1 = runOffset(runFlags, runRange, r.location);
            enum runPosition p2 = runOffset(runFlags, runRange, r.location + r.length);
            
            if (p1 == pastLeft) {
                if (p2 == pastLeft) {
                    // Weird, but OK.
                    RECT(rectStart, leftRunBoundary(line, run), rectFlags);
                    ended = YES;
                    break;
                } else if (p2 == middle) {
                    RECT(rectStart, MAX(endPosOffset, endPosSecondaryOffset), rectFlags | rectwalker_RightIsRangeBoundary);
                    ended = YES;
                    break;
                } else {
                    // p2 == pastRight; keep searching
                }
            } else if (p1 == middle) {
                if (p2 == pastLeft) {
                    RECT(rectStart, MAX(startPosOffset, startPosSecondaryOffset), rectFlags | rectwalker_RightIsRangeBoundary);
                    ended = YES;
                    break;
                } else if (p2 == middle) {
                    RECT(rectStart, leftRunBoundary(line, run), rectFlags);
                    RECT(min4(startPosOffset, startPosSecondaryOffset, endPosOffset, endPosSecondaryOffset),
                         max4(startPosOffset, startPosSecondaryOffset, endPosOffset, endPosSecondaryOffset),
                         rectwalker_LeftIsRangeBoundary | rectwalker_RightIsRangeBoundary);
                    ended = YES;
                    break;
                } else {
                    // p2 is pastRight; we'll need to end one rect and start another.
                    RECT(rectStart, leftRunBoundary(line, run), rectFlags);
                    rectStart = MIN(startPosOffset, startPosSecondaryOffset);
                    rectFlags = rectwalker_LeftIsRangeBoundary;
                    // ended = NO;  (actually, ended and began again)
                }
            } else {
                // p1 == pastRight
                if (p2 == pastLeft) {
                    // keep searching
                } else if (p2 == middle) {
                    // We'll need to end one rect and start another.
                    RECT(rectStart, leftRunBoundary(line, run), rectFlags);
                    rectStart = MIN(endPosOffset, endPosSecondaryOffset);
                    rectFlags = rectwalker_LeftIsRangeBoundary;
                    // ended = NO;  (actually, ended and began again)
                } else {
                    // p2 == pastRight
                    // I don't think this should happen, but I guess we can handle it
                    RECT(rectStart, leftRunBoundary(line, run), rectFlags);
                    ended = YES;
                    break;
                }
            }
        }
        
        if (!ended) {
            // Must have run off the end of the line. 
            RECT_tww(rectStart, lineWidth, CTLineGetTrailingWhitespaceWidth(line), rectFlags | rightFlags);
        }
        
    }
    
    return rectsIssued;
}

static void rectanglesInRange(CTFrameRef frame, NSRange r, BOOL sloppy, rectanglesInRangeCallback cb, void *ctxt)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    CFIndex firstLine = bsearchLines(lines, 0, lineCount, r.location, NULL);
    if (firstLine < 0 || firstLine >= lineCount)
        return;
    
    for (CFIndex lineIndex = firstLine; lineIndex < lineCount; lineIndex ++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
        CFRange lineRange = CTLineGetStringRange(line);
        CGFloat left, right;
        CGFloat ascent = NAN, descent = NAN;
        CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
        NSRange spanRange;
        int flags = ( lineIndex == firstLine )? rectwalker_FirstLine : 0;
        
        /* We know that lineRange.location >= 0 here, so it's safe to cast it to NSUInteger */
        if (r.location + r.length < (NSUInteger)lineRange.location)
            break;
        else if (r.location <= (NSUInteger)lineRange.location) {
            left = 0;
            spanRange.location = (NSUInteger)lineRange.location;
            flags |= rectwalker_LeftIsLineWrap;
        } else {
            left = CTLineGetOffsetForStringIndex(line, r.location, NULL);
            spanRange.location = r.location;
            flags |= rectwalker_LeftIsRangeBoundary;
        }
        
        BOOL lastLine;
        
        if (in_range(r, lineRange.location + lineRange.length)) {
            right = lineWidth;
            spanRange.length = ( lineRange.location + lineRange.length ) - spanRange.location;
            if ((lineIndex+1) < lineCount)
                lastLine = NO;
            else
                lastLine = YES;
            flags |= rectwalker_RightIsLineWrap;
        } else {
            right = CTLineGetOffsetForStringIndex(line, r.location + r.length, NULL);
            spanRange.length = ( r.location + r.length ) - spanRange.location;
            lastLine = YES;
            flags |= rectwalker_RightIsRangeBoundary;
        }
        
        /* Go ahead and be precise instead of sloppy if there's only one line involved */
        if (lastLine && sloppy && lineIndex == firstLine)
            sloppy = NO;
        
        CGPoint lineOrigin[1];
        CTFrameGetLineOrigins(frame, (CFRange){ lineIndex, 1 }, lineOrigin);
        
        BOOL keepGoing;
        
        if (! (flags & (rectwalker_LeftIsRangeBoundary|rectwalker_RightIsRangeBoundary))  ||  sloppy) {
            flags |= rectwalker_FirstRectInLine; // the only rect in the line, in fact
            CGFloat trailingWhitespace = (flags & rectwalker_RightIsLineWrap)? CTLineGetTrailingWhitespaceWidth(line) : 0;
            keepGoing = (*cb)( (CGPoint){ lineOrigin[0].x + left, lineOrigin[0].y }, right - left, trailingWhitespace, ascent, descent, flags, ctxt);
        } else {
            int parts = rectanglesInLine(line, lineOrigin[0], r, flags, cb, ctxt);
            if (parts < 0)
                keepGoing = NO;
            else {
                keepGoing = YES;
            }
        }
        
        if (!keepGoing || lastLine)
            break;
    }
}

struct typographicPosition {
    CFIndex lineIndex;                // The line in the laid-out frame
    CTLineRef line;                   // The line object
    CFIndex adjustedIndex;            // String index
    enum typographicCaretContext {
        beginsText = -2,
        beginsLine = -1,
        midLine    =  0,
        endsLine   =  1,
        endsText   =  2
    } position;
};

#if 0

/* These used to be computed by getTypographicPosition(), but only one caller currently wants them, so they're computed by that caller now. */
struct typographicPositionMetrics {
    CGPoint baselinePoint;            // The typographic position relative to lineOrigin
    CGPoint lineOrigin;               // The line's origin in layout space
    CGFloat ascent, descent;          // The line's ascent and descent, typically poth are positive
    CGFloat secondaryOffset;          // CoreText gives this to us but I'm not sure what it's for
};

#endif

static void getTypographicPosition(CFArrayRef lines, NSUInteger posIndex, int affinity, struct typographicPosition *result)
{
    CFIndex lineCount = CFArrayGetCount(lines);
    CFIndex posIndex_s = (CFIndex)posIndex;
    CFIndex adjustedIndex;
    
    CTLineRef line = NULL;
    CFIndex caretLineNumber = bsearchLines(lines, 0, lineCount, posIndex_s, &line);
    
    if (!line) {
        if (caretLineNumber < 0 && lineCount > 0) {
            caretLineNumber = 0;
            line = CFArrayGetValueAtIndex(lines, caretLineNumber);
            result->position = beginsText;
            CFRange lineRange = CTLineGetStringRange(line);
            adjustedIndex = lineRange.location;
        } else if (lineCount == 0) {
            result->lineIndex = kCFNotFound;
            result->line = NULL;
            return;
        } else /* if (caretLineNumber >= lineCount) */ {
            if (affinity < 0) {
                caretLineNumber = lineCount-1;
                line = CFArrayGetValueAtIndex(lines, caretLineNumber);
                result->position = endsText;
                CFRange lineRange = CTLineGetStringRange(line);
                adjustedIndex = lineRange.location + lineRange.length;
            } else {
                result->lineIndex = kCFNotFound;
                result->line = NULL;
                return;
            }
        }
    } else {
        CFRange lineRange = CTLineGetStringRange(line);
        if (lineRange.location >= posIndex_s) {
            if (affinity < 0 && caretLineNumber > 0) {
                caretLineNumber --;
                line = CFArrayGetValueAtIndex(lines, caretLineNumber);
                result->position = endsLine;
            } else {
                result->position = beginsLine;
            }
        } else if (lineRange.location + lineRange.length <= posIndex_s) {
            if (affinity > 0 && caretLineNumber+1 < lineCount) {
                caretLineNumber = caretLineNumber+1;
                line = CFArrayGetValueAtIndex(lines, caretLineNumber);
                result->position = beginsLine;
            } else {
                result->position = endsLine;
            }
        } else {
            result->position = midLine;
        }
        adjustedIndex = posIndex_s;
    }
    
    result->lineIndex = caretLineNumber;
    result->line = line;
    result->adjustedIndex = adjustedIndex;
}

- (void)dealloc;
{
    for(int i = 0; i < EF_NUM_ACTION_RECOGNIZERS; i++) {
        [actionRecognizers[i] release];
    }

    [focusRecognizer release];
    [_rangeSelectionColor release];
    
    if (defaultParagraphStyle)
        CFRelease(defaultParagraphStyle);
    if (defaultFont)
        CFRelease(defaultFont);
    [textColor release];
    [_content release];
    [selection release];
    [typingAttributes release];
    [_insertionPointSelectionColor release];
    [markedTextStyle release];
    [_linkTextAttributes release];
    [immutableContent release];
    if (framesetter)
        CFRelease(framesetter);
    if (drawnFrame)
        CFRelease(drawnFrame);
    [_loupe release];
    [tokenizer release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Conversion between CoreGraphics text and UIKIt coodinates

/*
 We have a bunch of coordinate systems:
 
 The "view" coordinate system is the UIView frame/bounds coordinates. Its Y-coordinate always increases downwards ("flipped") and its units are the same size as the rasterization pixels (device pixels or layer pixels or whatever).
 
 The "text" or "rendering" coordinate system is the interior scaled, (de-)flipped, and possibly translated system for CoreGraphics calls to draw stuff.
 
 The "layout" coordinate system is translated from the rendering coordinate system because CTFramesetter is particular about where it puts its text.
 
 Some locations are in a line-based coordinate system, which is the text layout coordinate system translated so that a given line's origin is at (0,0).

*/

#pragma mark -
#pragma mark Drawing and display

/* We have four possible selection display modes:
 1. No selection displayed
 2. Caret displayed
 3. Simple selection (a simple rectangle)
 4. Complex selection (arbitrary region, eg multi-line selection)
 */

#pragma mark -
#pragma mark Properties and API

@synthesize textColor;

@synthesize selectionColor = _insertionPointSelectionColor;
- (void)setSelectionColor:(UIColor *)color;
{
    if (OFISEQUAL(_insertionPointSelectionColor, color))
        return;
    
    [_insertionPointSelectionColor release];
    _insertionPointSelectionColor = [color retain];
    
    [_rangeSelectionColor release];
    _rangeSelectionColor = [[_insertionPointSelectionColor colorWithAlphaComponent:0.5] retain];
    
    if (selection)
        [self setNeedsDisplay];
}

@synthesize textInset = textInset;
- (void)setTextInset:(UIEdgeInsets)newInset;
{
    if (UIEdgeInsetsEqualToEdgeInsets(newInset, textInset))
        return;
    textInset = newInset;
    [self setNeedsDisplay];
}

@synthesize textLayoutSize = layoutSize;
- (void)setTextLayoutSize:(CGSize)size;
{
    if (CGSizeEqualToSize(layoutSize, size))
        return;
    layoutSize = size;
    
    if (drawnFrame) {
        CFRelease(drawnFrame);
        drawnFrame = NULL;
    }
    [self setNeedsLayout];
}

- (CGSize)textUsedSize;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    OBASSERT(drawnFrame);
    if (drawnFrame) {
        CGSize textSize = _usedSize;
        textSize.width += textInset.left + textInset.right;
        textSize.height += textInset.top + textInset.bottom;
        
        return textSize;
    }
    return CGSizeZero;
}

- (CGSize)viewUsedSize;
{
    CGSize textUsedSize = self.textUsedSize;
    CGFloat scale = self.scale;
    return CGSizeMake(textUsedSize.width * scale, textUsedSize.height * scale);
}

- (void)setDelegate:(id <OUIEditableFrameDelegate>)newDelegate
{
    delegate = newDelegate;
    
    flags.delegateRespondsToLayoutChanged = ( newDelegate && [newDelegate respondsToSelector:@selector(textViewLayoutChanged:)] )? 1 : 0;
    flags.delegateRespondsToContentsChanged = ( newDelegate && [newDelegate respondsToSelector:@selector(textViewContentsChanged:)] )? 1 : 0;
}

@synthesize delegate;

- (void)setDefaultCTFont:(CTFontRef)newFont
{
    if (!newFont)
        newFont = OUIGlobalDefaultFont();
    
    if (newFont == defaultFont)
        return;
    
    if (defaultFont)
        CFRelease(defaultFont);
    defaultFont = CFRetain(newFont);
}

- (CTFontRef)defaultCTFont;
{
    return defaultFont;
}

- (void)setDefaultCTParagraphStyle:(CTParagraphStyleRef)newStyle
{
    if (newStyle == defaultParagraphStyle)
        return;
    
    if (defaultParagraphStyle)
        CFRelease(defaultParagraphStyle);
    defaultParagraphStyle = CFRetain(newStyle);
}

- (CTParagraphStyleRef)defaultCTParagraphStyle;
{
    return defaultParagraphStyle;
}

@synthesize linkTextAttributes = _linkTextAttributes;

- (void)setupCustomMenuItemsForMenuController:(UIMenuController *)menuController;
{
    UIMenuItem *items[1];
        
    /* If we have a range selection, allow the user to inspect its attributes */
    /* If we don't have a selection, this item will be disabled via -canPerformAction:withSender: */
    items[0] = [[UIMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Style", @"OmniUI", OMNI_BUNDLE, @"Contextual menu item") action:@selector(inspectSelectedText:)];
    
    menuController.menuItems = [NSArray arrayWithObjects:items count:1];
    
    [items[0] release];
}

- (void)thumbBegan:(OUITextThumb *)thumb;
{
    if (!_loupe) {
        _loupe = [[OUILoupeOverlay alloc] initWithFrame:[self frame]];
        [_loupe setSubjectView:self];
        [[[[self window] subviews] lastObject] addSubview:_loupe];
    }
    
    [self _setSolidCaret:1];
}

- (void)thumbMoved:(OUITextThumb *)thumb targetPosition:(CGPoint)pt;
{
    _loupe.touchPoint = pt;
    _loupe.mode = OUILoupeOverlayRectangle;
    
    OUEFTextPosition *pp;
    
    if (selection && ![selection isEmpty]) {
        OUEFTextRange *selectableSpan;
        
        if ([thumb isEndThumb])
            selectableSpan = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self positionFromPosition:[selection start] offset:1]
                                                              end:(OUEFTextPosition *)[self endOfDocument]];
        else
            selectableSpan = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self beginningOfDocument]
                                                              end:(OUEFTextPosition *)[self positionFromPosition:[selection end] offset:-1]];
        
        pp = (OUEFTextPosition *)[self closestPositionToPoint:pt withinRange:selectableSpan];
        
        [selectableSpan release];
    } else {
        pp = (OUEFTextPosition *)[self closestPositionToPoint:pt];
    }

    if (!pp)
        return;
        
    if (thumb.isEndThumb) {
        OUEFTextPosition *st = (OUEFTextPosition *)(selection.start);
        
        if ([st compare:pp] != NSOrderedAscending)
            return;
        
        [self setSelectedTextRange:[[[OUEFTextRange alloc] initWithStart:st end:pp] autorelease]];
    } else {
        OUEFTextPosition *en = (OUEFTextPosition *)(selection.end);
        
        if ([en compare:pp] != NSOrderedDescending)
            return;
        
        [self setSelectedTextRange:[[[OUEFTextRange alloc] initWithStart:pp end:en] autorelease]];
    }
}

- (void)thumbEnded:(OUITextThumb *)thumb normally:(BOOL)normalEnd;
{
    _loupe.mode = OUILoupeOverlayNone;
    [self _setSolidCaret:-1];
}

- (id <NSObject>)attribute:(NSString *)attr inRange:(UITextRange *)r;
{
    NSUInteger pos = ((OUEFTextPosition *)(r.start)).index;
    return [_content attribute:attr atIndex:pos effectiveRange:NULL];
}

/* The pattern of housekeeping we need to do around every change to our content. Call beforeMutate() before changing _content, afterMutate() after changing the content, and notifyAfterMutate() some time after that before returning from the method. */
static BOOL beforeMutate(OUIEditableFrame *self, SEL _cmd)
{
    NSUInteger wasGeneration = self->generation;
    
    // We generally don't want to show the context menu while the user is typing.
    if (self->flags.showingEditMenu) {
        DEBUG_TEXT(@"Dismissing context menu (%@)", NSStringFromSelector(_cmd));
        self->flags.showingEditMenu = 0;
        [self setNeedsLayout];
    }
    
    DEBUG_TEXT(@">>> textWillChange (%@)", NSStringFromSelector(_cmd));
    [self->inputDelegate textWillChange:self];
    DEBUG_TEXT(@"<<< textWillChange (%@)", NSStringFromSelector(_cmd));
    
    if (wasGeneration != self->generation) {
        DEBUG_TEXT(@"Aborting %@ due to stupidity of UITextInputDelegate (RADAR 7881864 / 7696512)", NSStringFromSelector(_cmd));
        DEBUG_TEXT(@">>> textDidChange (%@/abort)", NSStringFromSelector(_cmd));
        [self->inputDelegate textDidChange:self];
        DEBUG_TEXT(@"<<< textDidChange (%@/abort)", NSStringFromSelector(_cmd));
        return NO;
    }
    
    [self->immutableContent release];
    self->immutableContent = nil;
    
    [self->_content beginEditing];
    
    return YES;
}

static inline void afterMutate(OUIEditableFrame *self, SEL _cmd)
{
    [self _didChangeContent];
    [self->_content endEditing];
}

static void notifyAfterMutate(OUIEditableFrame *self, SEL _cmd)
{
    DEBUG_TEXT(@">>> textDidChange (%@)", NSStringFromSelector(_cmd));
    [self->inputDelegate textDidChange:self];
    if (self->flags.delegateRespondsToContentsChanged)
        [self->delegate textViewContentsChanged:self];
    DEBUG_TEXT(@"<<< textDidChange (%@)", NSStringFromSelector(_cmd));
}

- (void)setValue:(id)value forAttribute:(NSString *)attr inRange:(UITextRange *)r;
{
    OBPRECONDITION([r isKindOfClass:[OUEFTextRange class]]);
    
    DEBUG_TEXT(@"Setting %@ to %@ in %@", attr, value, r);
    
    NSUInteger st = ((OUEFTextPosition *)(r.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(r.end)).index;
    
    if (en < st) {
        OBASSERT_NOT_REACHED("Bad selection range");
        return;
    }
    
    [self _setSolidCaret:0];
    
    if (!beforeMutate(self, _cmd))
        return;
    
    NSUInteger adjustedContentLength = [_content length] - 1; // don't molest the trailing newline
    if (en > adjustedContentLength)
        en = adjustedContentLength;
    if (st > en)
        st = en;
    NSRange cr = [[_content string] rangeOfComposedCharacterSequencesForRange:(NSRange){ st, en - st }];
    if (cr.location + cr.length > adjustedContentLength)
        cr.length = ( adjustedContentLength - cr.location );
    if (value)
        [_content addAttribute:attr value:value range:cr];
    else
        [_content removeAttribute:attr range:cr];
    afterMutate(self, _cmd);
    notifyAfterMutate(self, _cmd);
    
    [self setNeedsDisplay];
}

static BOOL _eventTouchesView(UIEvent *event, UIView *view)
{
    if (view.hidden || !view.superview)
        return NO;
    
    if ([[event touchesForView:view] count] > 0)
        return YES;
    
    return NO;
}

- (BOOL)hasTouchesForEvent:(UIEvent *)event;
{
    // Thumbs extent outside our bounds, so check them too
    return _eventTouchesView(event, self) || _eventTouchesView(event, startThumb) || _eventTouchesView(event, endThumb);
}

static BOOL _recognizerTouchedView(UIGestureRecognizer *recognizer, UIView *view)
{
    if (view.hidden || !view.superview)
        return NO;
    
    return CGRectContainsPoint(view.bounds, [recognizer locationInView:view]);
}

- (BOOL)hasTouchByGestureRecognizer:(UIGestureRecognizer *)recognizer;
{
    OBPRECONDITION(recognizer);
    
    // Thumbs extent outside our bounds, so check them too
    return _recognizerTouchedView(recognizer, self) || _recognizerTouchedView(recognizer, startThumb) || _recognizerTouchedView(recognizer, endThumb);
}

#pragma mark -
#pragma mark OUIScalingView subclass

- (void)setScale:(CGFloat)scale;
{
    [super setScale:scale];
    
    // Mark this as invalid; will rebuild with a new CGPath on the next display (the super implementation calls -setNeedsDisplay).
    // TODO: This (a) should be unnecessary and (b) if it is necessary should be done in -scaleChanged
    if (framesetter) {
        CFRelease(framesetter);
        framesetter = NULL;
    }
}

- (BOOL)wantsUnflippedCoordinateSystem;
{
    return YES;
}

- (void)drawScaledContent:(CGRect)rect;
{
    // Updated by -drawRect:
    OBPRECONDITION(drawnFrame);
    OBPRECONDITION(flags.textNeedsUpdate == NO);
    if (!drawnFrame || flags.textNeedsUpdate)
        return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    UIColor *background = self.backgroundColor;
    if (background) {
        [background setFill];
        CGContextFillRect(ctx, rect);
    }
    
    /* We want to draw any range selections under the text, and we want to draw insertion carets (non-range selections) and markedText hairlines over the text. */
    
    [self _drawSelectionInContext:ctx];
    
    OUITextLayoutDrawFrame(ctx, drawnFrame, self.bounds, layoutOrigin);
    
    [self _drawDecorations:ctx];
}

#pragma mark -
#pragma mark UIView subclass

- (void)drawRect:(CGRect)rect;
{
    DEBUG_TEXT(@"Drawing %@: frame=%@ bounds=%@ center=%@",
               NSStringFromCGRect(rect), NSStringFromCGRect(self.frame), NSStringFromCGRect(self.bounds), NSStringFromCGPoint(self.center));
    
    if (CGRectContainsRect(rect, selectionDirtyRect))
        selectionDirtyRect = CGRectNull;
    if (CGRectContainsRect(rect, markedTextDirtyRect))
        markedTextDirtyRect = CGRectNull;
        
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    [super drawRect:rect];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    // NSLog(@"Laying out: solidCaret = %u", flags.solidCaret);
    
    BOOL amFirstResponder = [self isFirstResponder];
    
    /* Show or hide the selection thumbs */
    if (selection && ![selection isEmpty] && flags.showSelectionThumbs && amFirstResponder) {
        if (!drawnFrame || flags.textNeedsUpdate)
            [self _updateLayout:YES];
        
        CGRect caretRect;
        
        if (!startThumb) {
            startThumb = [[OUITextThumb alloc] init];
            startThumb.isEndThumb = NO;
            [self addSubview:startThumb];
            // [[startThumb gestureRecognizers] makeObjectsPerformSelector:@selector(setDelegate:) withObject:self];
        }
        caretRect = [self _caretRectForPosition:(OUEFTextPosition *)selection.start affinity:1 bloomScale:0];
        if (CGRectIsNull(caretRect)) {
            // This doesn't make a lot of sense, but it can happen if the layout height is finite
            startThumb.hidden = YES;
        } else {
            // Convert to our bounds' coordinate system, and add a few pixels for visibility
            caretRect = CGRectInset([self convertRectToRenderingSpace:caretRect], -1, -1); // Method's name is misleading
            [startThumb setCaretRectangle:caretRect];
            startThumb.hidden = NO;
        }
        
        if (!endThumb) {
            endThumb = [[OUITextThumb alloc] init];
            endThumb.isEndThumb = YES;
            [self addSubview:endThumb];
            // [[endThumb gestureRecognizers] makeObjectsPerformSelector:@selector(setDelegate:) withObject:self];
        }
        caretRect = [self _caretRectForPosition:(OUEFTextPosition *)selection.end affinity:-1 bloomScale:0];
        if (CGRectIsNull(caretRect)) {
            // This doesn't make a lot of sense, but it can happen if the layout height is finite
            endThumb.hidden = YES;
        } else {
            caretRect = CGRectInset([self convertRectToRenderingSpace:caretRect], -1, -1); // Method's name is misleading
            [endThumb setCaretRectangle:caretRect];
            endThumb.hidden = NO;
        }
    } else {
        // Hide thumbs if we've got 'em
        if (startThumb) {
            startThumb.hidden = YES;
        }
            
        if (endThumb) {
            endThumb.hidden = YES;
        }
    }
    
    /* Show or hide the layer-based blinking cursor */
    if (drawnFrame && !flags.textNeedsUpdate && selection && [selection isEmpty] && !flags.solidCaret && amFirstResponder) {
        CGRect caretRect = [self _caretRectForPosition:(OUEFTextPosition *)(selection.start) affinity:1 bloomScale:self.scale];
        
        caretRect = [self convertRectToRenderingSpace:caretRect];  // method name is misleading
        
        if (!_cursorOverlay) {
            _cursorOverlay = [[OUITextCursorOverlay alloc] initWithFrame:caretRect];
            [_cursorOverlay setCursorFrame:caretRect];
            [self addSubview:_cursorOverlay];
            [_cursorOverlay release];
            _cursorOverlay.foregroundColor = _insertionPointSelectionColor;
            
            [_cursorOverlay startBlinking];
        } else {
            [_cursorOverlay setCursorFrame:caretRect];
            if (_cursorOverlay.hidden) {
                _cursorOverlay.hidden = NO;
                [_cursorOverlay startBlinking];
            }
        }
    } else {
        if (_cursorOverlay && !(_cursorOverlay.hidden)) {
            [_cursorOverlay stopBlinking];
            _cursorOverlay.hidden = YES;
        }
    }
    
    /* Show or hide the selection context menu. Always suppress it if the loupe is up, though. */
    if (selection != nil && ![selection isEmpty])
        flags.showingEditMenu = 1;
    BOOL suppressContextMenu = (_loupe != nil && _loupe.mode != OUILoupeOverlayNone) ||
                                (_textInspector != nil && _textInspector.isVisible) ||
                                (delegate && [delegate respondsToSelector:@selector(textViewCanShowContextMenu:)] && ![delegate textViewCanShowContextMenu:self]);
    if (!flags.showingEditMenu || suppressContextMenu || !amFirstResponder) {
        if (_selectionContextMenu) {
            [_selectionContextMenu setMenuVisible:NO animated:( suppressContextMenu? NO : YES )];
            [_selectionContextMenu autorelease];
            _selectionContextMenu = nil;
        }
    } else {
        BOOL alreadyVisible;
        if (!_selectionContextMenu) {
            UIMenuController *menuController = [UIMenuController sharedMenuController];
            [self setupCustomMenuItemsForMenuController:menuController];
            _selectionContextMenu = [menuController retain];
            alreadyVisible = NO;
        } else {
            alreadyVisible = [_selectionContextMenu isMenuVisible];
        }
        
        /* Get the bounding rect of our selection */
        CGRect selectionRectangle = [self _boundsOfRange:selection];
        
        selectionRectangle = CGRectIntegral(selectionRectangle);
        
        [_selectionContextMenu setTargetRect:selectionRectangle inView:self];
        
        if (!alreadyVisible) {
            DEBUG_TEXT(@"Showing context menu");
            [_selectionContextMenu setMenuVisible:YES animated:YES];
        }
    }
}

- (CGSize)sizeThatFits:(CGSize)maximumSize
{
    OBASSERT_NOT_REACHED("Don't call this");
    
    // CTFramesetterSuggestFrameSizeWithConstraints is useless (see OUITextLayout.m for diatribe).
    // Instead, set the layout constraints on this instance via layoutSize and ask it for -usedSize;
    return maximumSize;
#if 0
    if (!framesetter || flags.textNeedsUpdate)
        [self _updateLayout:NO];
    
    /* TODO: Adjust size to include the virtual blank line at the end if text ends in \n ? Or only if the selection is down there? */
    
    CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                                                               (CFRange){ 0, 0 },
                                                               NULL /* frameAttributes */,
                                                               maximumSize,
                                                               NULL);
    
    // Size returned by CT is in its CoreGraphics rendering system, but we're returning view coordinates
    CGFloat scale = self.scale;
    CGSize viewSize;
    //    viewSize.width = ceil(ceil(size.width) * scale);
    //    viewSize.height = ceil(ceil(size.height) * scale);
    viewSize.width = size.width * scale;
    viewSize.height = size.height * scale;
    
    DEBUG_TEXT(@"CT says %@, scale is %f -> %@", NSStringFromCGSize(size), scale, NSStringFromCGSize(viewSize));
    
    return viewSize;
#endif
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    // We lazily initialize some attributes when we move to a window for the first time.
    
    if (!_insertionPointSelectionColor)
        self.selectionColor = [UIColor colorWithHue:214.0/360.0 saturation:0.73 brightness:0.95 alpha:1.0];
    
    if (!focusRecognizer) {
        UITapGestureRecognizer *tap1 = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_idleTap)];
        [self addGestureRecognizer:tap1];
        focusRecognizer = tap1;
    }

    if (!_content)
        [self setAttributedText:nil]; // Triggers all our sanity-ensuring checks
}

- (void)setFrame:(CGRect)newFrame
{
    DEBUG_TEXT(@"Frame is getting set to %@", NSStringFromCGRect(newFrame));
    
    if (drawnFrame && !CGSizeEqualToSize(newFrame.size, self.frame.size)) {
        CFRelease(drawnFrame);
        drawnFrame = NULL;
        [self setNeedsDisplay];
    }
    
    [super setFrame:newFrame];
}

- (void)setBounds:(CGRect)newBounds
{
    DEBUG_TEXT(@"Bounds are getting set to %@", NSStringFromCGRect(newBounds));
    
    if (drawnFrame && !CGSizeEqualToSize(newBounds.size, self.bounds.size)) {
        CFRelease(drawnFrame);
        drawnFrame = NULL;
        [self setNeedsDisplay];
    }
    
    [super setBounds:newBounds];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    // We want our thumbs to receive touches even when they extend a bit outside our area.
    
    UIView *hitStartThumb = startThumb? [startThumb hitTest:[self convertPoint:point toView:startThumb] withEvent:event] : nil;
    UIView *hitEndThumb = endThumb? [endThumb hitTest:[self convertPoint:point toView:endThumb] withEvent:event] : nil;
    
    if (hitStartThumb && hitEndThumb) {
        // Direct touches to one thumb or the other depending on closeness, ignoring their z-order.
        // (This comes into play when the thumbs are close enough to each other that their areas overlap.)
        CGFloat dStart = [startThumb distanceFromPoint:point];
        CGFloat dEnd = [endThumb distanceFromPoint:point];
        
        if (dStart < dEnd)
            return hitStartThumb;
        else
            return hitEndThumb;
    } else if (hitStartThumb)
        return hitStartThumb;
    else if (hitEndThumb)
        return hitEndThumb;
    
    // But by default, use our superclass's behavior
    return [super hitTest:point withEvent:event];
}

#pragma mark -
#pragma mark UIResponder subclass

- (BOOL)becomeFirstResponder
{
    DEBUG_TEXT(@">> become first responder");
    BOOL didBecomeFirstResponder = [super becomeFirstResponder];
    
    if (didBecomeFirstResponder && !actionRecognizers[0]) {
        UITapGestureRecognizer *singleTap = [[OUIDirectTapGestureRecognizer alloc] initWithTarget:self action:@selector(_activeTap:)];
        actionRecognizers[0] = singleTap;
        [self addGestureRecognizer:singleTap];
        // singleTap.maximumSingleTapDuration = 1.5;
        // singleTap.maximumIntervalBetweenSuccessiveTaps = 5./16.;
        
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_activeTap:)];
        doubleTap.numberOfTapsRequired = 2;
        actionRecognizers[1] = doubleTap;
        [self addGestureRecognizer:doubleTap];
        
        UILongPressGestureRecognizer *inspectTap = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_inspectTap:)];
        actionRecognizers[2] = inspectTap;
        [self addGestureRecognizer:inspectTap];
        
        assert(3 == EF_NUM_ACTION_RECOGNIZERS);
    }
    
    if (didBecomeFirstResponder) {
        focusRecognizer.enabled = NO;
        for(int i = 0; i < EF_NUM_ACTION_RECOGNIZERS; i++)
            actionRecognizers[i].enabled = YES;
    }
    
    [self setNeedsLayout];
    
    if (selection)
        [self setNeedsDisplay];
    
    DEBUG_TEXT(@"<< become first responder");
    return didBecomeFirstResponder;
}

- (BOOL)resignFirstResponder;
{
    DEBUG_TEXT(@">> resign first responder");
    BOOL b = [super resignFirstResponder];
    
    if (![self isFirstResponder]) {
        focusRecognizer.enabled = YES;
        for(int i = 0; i < EF_NUM_ACTION_RECOGNIZERS; i++) {
            UIGestureRecognizer *recognizer = actionRecognizers[i];
            if (recognizer)
                recognizer.enabled = NO;
        }
        
        if (startThumb) {
            [startThumb removeFromSuperview];
            [startThumb release];
            startThumb = nil;
        }
        if (endThumb) {
            [endThumb removeFromSuperview];
            [endThumb release];
            endThumb = nil;
        }
    }
    
    [self setNeedsLayout];
    
    if (selection)
        [self setNeedsDisplay];
    
    if (delegate && [delegate respondsToSelector:@selector(textViewDidEndEditing:)])
        [delegate textViewDidEndEditing:self];
    
    DEBUG_TEXT(@"<< resign first responder");
    return b;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark UIResponderStandardEditActions

- (void)copy:(id)sender;
{
    if (selection) {
        // TODO: Invent a pasteboard format for attributed strings... sigh.
        NSString *txt = [self textInRange:selection];
        [UIPasteboard generalPasteboard].string = txt;
    }
}

- (void)cut:(id)sender;
{
    if (selection) {
        [self copy:sender];
        [self replaceRange:selection withText:@""];
    }
}

- (void)delete:(id)sender;
{
    if (selection && ![selection isEmpty]) {
        [self replaceRange:selection withText:@""];
    }    
}

- (void)paste:(id)sender;
{
    NSString *scrap = [UIPasteboard generalPasteboard].string;
    if (scrap) {
        UITextRange *seln = self.selectedTextRange;
        if (!seln) {
            seln = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self endOfDocument] end:(OUEFTextPosition *)[self endOfDocument]];
        }
        [self replaceRange:seln withText:scrap];
    }
}

/* TODO
- (void)select:(id)sender;
{
}
*/

- (void)selectAll:(id)sender;
{
    OUEFTextRange *all = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self beginningOfDocument] end:(OUEFTextPosition *)[self endOfDocument]];
    [self setSelectedTextRange:all];
    [all release];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(inspectSelectedText:) && !flags.showInspector)
        return NO;

    if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(delete:) || action == @selector(inspectSelectedText:)) {
        return selection && ![selection isEmpty];
    }
    
    if (action == @selector(paste:)) {
        return [[UIPasteboard generalPasteboard] containsPasteboardTypes:UIPasteboardTypeListString];
    }
    
    if (action == @selector(selectAll:)) {
        if (!selection)
            return YES;
        if (![selection.start isEqual:[self beginningOfDocument]] ||
            ![selection.end isEqual:[self endOfDocument]])
            return YES;
        return NO;
    }

    return [super canPerformAction:action withSender:sender];
}

#pragma mark -
#pragma mark UIKeyInput protocol
@synthesize autocorrectionType = _autocorrectionType;
@synthesize autocapitalizationType = _autocapitalizationType;

- (void)_didChangeContent
{
    [immutableContent release];
    immutableContent = nil;
    
    generation ++;
    flags.textNeedsUpdate = YES;
    
    /* Ensure that each paragraph has no more than one paragraph style */
    OUITextLayoutFixupParagraphStyles(_content);
    
    /* Set default font, color, and paragraph styles on any runs that don't have them. */
    if (defaultFont || textColor || defaultParagraphStyle) {
        CGColorRef textCGColor = [textColor CGColor];
        NSUInteger contentLength = [_content length];
        NSRange cursor;
        cursor.location = 0;
        
        while (cursor.location < contentLength) {
            NSDictionary *run = [_content attributesAtIndex:cursor.location effectiveRange:&cursor];
            
            if (defaultFont && ![run objectForKey:(id)kCTFontAttributeName])
                [_content addAttribute:(id)kCTFontAttributeName value:(id)defaultFont range:cursor];
            if (textCGColor && ![run objectForKey:(id)kCTForegroundColorAttributeName])
                [_content addAttribute:(id)kCTForegroundColorAttributeName value:(id)textCGColor range:cursor];
            if (defaultParagraphStyle && ![run objectForKey:(id)kCTParagraphStyleAttributeName])
                [_content addAttribute:(id)kCTParagraphStyleAttributeName value:(id)defaultParagraphStyle range:cursor];

            cursor.location += cursor.length;
        }
    }
}

- (NSDictionary *)typingAttributes
{
    if (typingAttributes)
        return typingAttributes;

    NSUInteger insertAt;
    NSUInteger contentLength = [_content length];
    
    if (contentLength == 0)
        return nil;

    if (!selection) {
        insertAt = contentLength;
    } else {
        insertAt = ((OUEFTextPosition *)(self.selectedTextRange.end)).index;
        if (insertAt > contentLength)
            insertAt = contentLength;
    }
    
    return [_content attributesAtIndex:(insertAt > 0 ? insertAt-1 : 0) effectiveRange:NULL];
}

@synthesize typingAttributes;

- (NSAttributedString *)attributedText;
{
    // If we have an immutable copy that doesn't have attribute transforms applied, return a substring from it (which could potentially just reference the original immutable copy).
    if (immutableContent && !flags.immutableContentHasAttributeTransforms) {
        NSUInteger len = [immutableContent length];
        return [immutableContent attributedSubstringFromRange:(NSRange){0, len-1}];
    }
    
    NSUInteger len = [_content length];
    if (len < 1)
        return nil;  // Shouldn't happen, actually
    
    // Strip off our implicit trailing newline.
    return [_content attributedSubstringFromRange:(NSRange){0, len-1}];
}

- (void)setAttributedText:(NSAttributedString *)newContent
{
    if (!_content || ![_content length]) {
        NSMutableDictionary *allDefaultAttributes = [NSMutableDictionary dictionary];
        if (defaultParagraphStyle)
            [allDefaultAttributes setObject:(id)defaultParagraphStyle forKey:(id)kCTParagraphStyleAttributeName];
        if (defaultFont)
            [allDefaultAttributes setObject:(id)defaultFont forKey:(id)kCTFontAttributeName];
        if (textColor)
            [allDefaultAttributes setObject:(id)[textColor CGColor] forKey:(id)kCTForegroundColorAttributeName];
        [_content autorelease];
        _content = [[NSMutableAttributedString alloc] initWithString:@"\n" attributes:allDefaultAttributes];
    }
    
    if (!beforeMutate(self, _cmd))
        return;

    NSInteger len = [_content length];
    if (newContent) {
        [_content replaceCharactersInRange:(NSRange){0, len-1} withAttributedString:newContent];
        len = [_content length];
        if (len >= 2)
            [_content setAttributes:[_content attributesAtIndex:len-2 effectiveRange:NULL] range:(NSRange){len-1, 1}];
    } else {
        /* Delete everything except the magic trailing newline */
        if (len > 1)
            [_content deleteCharactersInRange:(NSRange){0, len-1}];
    }
    afterMutate(self, _cmd);
    [self unmarkText];
    [self _setSelectionToIndex:[_content length]-1];
    [inputDelegate textDidChange:self];
    
    /* GraphSketcher's TextEditor class doesn't expect us to call it back here. Not sure which way is better. 
    if (flags.delegateRespondsToContentsChanged)
        [delegate textViewContentsChanged:self];
     */
    
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIKeyInput

- (BOOL)hasText;
{
    return ([_content length] > 1 );
}

// These show up, at least when simulating a hardward keyboard in the simulator. They at least match NSEvent.h
enum {
    NSUpArrowFunctionKey = 0xF700,
    NSDownArrowFunctionKey = 0xF701,
    NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703,
};

- (void)insertText:(NSString *)text;
{
    OBPRECONDITION(_content);
    
    [self _setSolidCaret:0];
    
    // iPad simulator's Japanese input method likes to try to insert nil. I don't know why.
    if (!text)
        return;
    
    NSUInteger contentLength = [_content length];
    OBINVARIANT(contentLength >= 1); // We always have a trailing newline
    if (contentLength)
        contentLength --;
    
    NSRange replaceRange;
    if (!selection)
        replaceRange = NSMakeRange(contentLength, 0);
    else {
        NSUInteger st = ((OUEFTextPosition *)(selection.start)).index;
        NSUInteger en = ((OUEFTextPosition *)(selection.end)).index;
        
        if (en > contentLength) {
            OBASSERT_NOT_REACHED("Bad selection range");
            return;
        }
        if (st > contentLength) {
            OBASSERT_NOT_REACHED("Bad selection range");
            return;
        }
        if (en < st) {
            OBASSERT_NOT_REACHED("Bad selection range");
            return;
        }
        replaceRange = NSMakeRange(st, en - st);
    }

    DEBUG_TEXT(@"Inserting \"%@\" in range {%d, %d} (content length %u)", text, replaceRange.location, replaceRange.length, [_content length]);
    
    // When Simulate Hardware Keyboard is on, these get passed in instead of automatically transforming them into movement via our -positionFromPosition:inDirection:offset:.
    // Not publicizing these methods, but I guess we could for callers that want selection movement.
    if ([text length] == 1) {
        unichar ch = [text characterAtIndex:0];
        
        switch (ch) {
            case NSLeftArrowFunctionKey:
                [self _moveInDirection:UITextLayoutDirectionLeft];
                return;
            case NSRightArrowFunctionKey:
                [self _moveInDirection:UITextLayoutDirectionRight];
                return;
            case NSUpArrowFunctionKey:
                [self _moveInDirection:UITextLayoutDirectionUp];
                return;
            case NSDownArrowFunctionKey:
                [self _moveInDirection:UITextLayoutDirectionDown];
                return;
            case 0x20:    // space character
            {
                if ((_autoCorrectDoubleSpaceToPeriodAtSentenceEnd) && (contentLength && replaceRange.location > 0)) {
                    NSInteger insertLocation = replaceRange.location;
                    while (insertLocation--) {
                        char nextChar = [[_content string] characterAtIndex:insertLocation];
                        if (nextChar == 0x2e /* period */) {
                            // period has already been inserted at the end of this sentence
                            break;
                        } else if (nextChar == 0x20) {
                            // double space found - check that there is not alread a period
                            if ((insertLocation - 1) > 0) {
                                char prevChar = [[_content string] characterAtIndex:(insertLocation - 1)];
                                if (prevChar == 0x20) {
                                    continue;
                                } else if (prevChar == 0x2e) {
                                    // period is already there
                                    break;
                                } else {
                                    OUEFTextPosition *start = [[OUEFTextPosition alloc] initWithIndex:insertLocation];
                                    UITextPosition *end = [self positionFromPosition:start offset:1];
                                    UITextRange *replace = [self textRangeFromPosition:start toPosition:end];
                                    [self replaceRange:replace withText:[NSString stringWithFormat:@"%c", 0x2e, nil]];
                                    [start release];
                                    break;
                                }
                            }
                        } else {
                            break;
                        }
                    }
                }
            }
        }

#ifdef DEBUG
        if (ch > 127) {
            DEBUG_TEXT(@"  ch = 0x%x", ch);
        }
#endif
    }
    
    [self unmarkText];

    if (!beforeMutate(self, _cmd))
        return;
    
    NSAttributedString *insertThis = [[NSAttributedString alloc] initWithString:text attributes:[self typingAttributes]];
    [_content replaceCharactersInRange:replaceRange withAttributedString:insertThis];
    [insertThis release];
    afterMutate(self, _cmd);
    [self _setSelectionToIndex: ( replaceRange.location + [text length] )];
    notifyAfterMutate(self, _cmd);
    
    [self setNeedsDisplay];
}

- (void)deleteBackward;
{
    OBPRECONDITION(_content);
    
    [self _setSolidCaret:0];

    OUEFTextRange *seln = (OUEFTextRange *)[self selectedTextRange];
    if (!seln)
        return;
    
    OUEFTextPosition *seln_start = (OUEFTextPosition *)(seln.start);
    OUEFTextPosition *seln_end = (OUEFTextPosition *)(seln.end);
    
    NSUInteger st = seln_start.index;
    NSUInteger en = seln_end.index;
    
    if (st < en) {
        [self replaceRange:seln withText:@""];
    } else  if (st == 0) {
        return;
    } else {
        [self unmarkText];
        if (!beforeMutate(self, _cmd))
            return;
        
        NSRange cr = [[_content string] rangeOfComposedCharacterSequenceAtIndex:st-1];
        [_content deleteCharactersInRange:cr];
        afterMutate(self, _cmd);
        [self _setSelectionToIndex:cr.location];
        notifyAfterMutate(self, _cmd);
        [self setNeedsDisplay];
    }
}

#pragma mark -
#pragma mark UITextInputTraits protocol
@synthesize autoCorrectDoubleSpaceToPeriodAtSentenceEnd = _autoCorrectDoubleSpaceToPeriodAtSentenceEnd;

- (UIKeyboardAppearance)keyboardAppearance;                { return UIKeyboardAppearanceDefault; }
- (UIReturnKeyType)returnKeyType;                          { return UIReturnKeyDefault; } 

@synthesize keyboardType;

- (BOOL)enablesReturnKeyAutomatically;
{
    return NO;
}

- (BOOL)isSecureTextEntry
{
    return NO;
}

#pragma mark -
#pragma mark UITextInput protocol

- (NSString *)textInRange:(UITextRange *)range;
{
    DEBUG_TEXT(@"-- textInRange:%@", [range description]);

    if (!range || ![range isKindOfClass:[OUEFTextRange class]])
        return nil;
        
    NSUInteger st = ((OUEFTextPosition *)(range.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(range.end)).index;
    
    NSString *result;
    if (en <= st)
        result = @"";
    else
        result = [[_content string] substringWithRange:(NSRange){ st, en - st }];
    
    //DEBUG_TEXT(@"textInRange:%@ -> \"%@\"", [range description], result);
    
    return result;
}

#if 0 /* Not currently used */
// This method is actually not part of the UITextInput protocol, but it's here because it's parallel to -textInRange:
- (NSAttributedString *)attributedTextInRange:(UITextRange *)range;
{
    DEBUG_TEXT(@"-- attributedTextInRange:%@", [range description]);
    
    if (!range || ![range isKindOfClass:[OUEFTextRange class]])
        return nil;
    
    NSUInteger st = ((OUEFTextPosition *)(range.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(range.end)).index;
    
    NSAttributedString *result;
    if (en <= st)
        result = [[[NSAttributedString alloc] initWithString:@""] autorelease];
    else
        result = [_content attributedSubstringFromRange:(NSRange){ st, en - st }];
    
    //DEBUG_TEXT(@"textInRange:%@ -> \"%@\"", [range description], result);
    
    return result;
}
#endif

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text;
{
    DEBUG_TEXT(@"-- replaceRange:%@ withText:'%@'", [range description], text);
    
    OBPRECONDITION(_content);
    
    if (!range || ![range isKindOfClass:[OUEFTextRange class]])
        return;
    
    OUEFTextRange *tr = (OUEFTextRange *)range;
    
    NSUInteger st = ((OUEFTextPosition *)(tr.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(tr.end)).index;
    
    DEBUG_TEXT(@"replaceRange:%@ withText:\"%@\"", [range description], text);
    
    if (en < st) {
        OBASSERT_NOT_REACHED("Bad selection range");
        return;
    }
    
    [self _setSolidCaret:0];
    
    [self unmarkText];
    if (!beforeMutate(self, _cmd))
        return;
    
    NSUInteger adjustedContentLength = [_content length] - 1; // don't molest the trailing newline
    NSUInteger endex;
    if (st > adjustedContentLength)
        st = adjustedContentLength;
    NSAttributedString *newtext = [[NSAttributedString alloc] initWithString:text attributes:[_content attributesAtIndex:st effectiveRange:NULL]];
    if (en > st) {
        NSRange cr = [[_content string] rangeOfComposedCharacterSequencesForRange:(NSRange){ st, en - st }];
        if (cr.location + cr.length > adjustedContentLength)
            cr.length = ( adjustedContentLength - cr.location );
        [_content replaceCharactersInRange:cr withAttributedString:newtext];
        endex = cr.location + [newtext length];
    } else {
        [_content insertAttributedString:newtext atIndex:st];
        endex = st + [newtext length];
    }
    [newtext release];
    afterMutate(self, _cmd);
    [self _setSelectionToIndex:endex];
    notifyAfterMutate(self, _cmd);
    
    [self setNeedsDisplay];
}

- (UITextRange *)selectedTextRange
{
    DEBUG_TEXT(@"-- selectedTextRange --> %@", selection);
    
    return selection;
}

- (void)setSelectedTextRange:(UITextRange *)newRange
{
    DEBUG_TEXT(@"-- setSelectedTextRange:%@", newRange);
    OBASSERT(newRange == nil || [newRange isKindOfClass:[OUEFTextRange class]]);

    /* TODO: We assume that any selection change that's official enough come through this method should count as caret-solidifying activity. Probably should look for corner cases here. */
    [self _setSolidCaret:0];
    
    [self unmarkText];
    
    [self _setSelectedTextRange:(OUEFTextRange *)newRange notifyDelegate:YES];
}


/* If text can be selected, it can be marked. Marked text represents provisionally
 * inserted text that has yet to be confirmed by the user.  It requires unique visual
 * treatment in its display.  If there is any marked text, the selection, whether a
 * caret or an extended range, always resides witihin.
 *
 * Setting marked text either replaces the existing marked text or, if none is present,
 * inserts it from the current selection. */ 

- (UITextRange *)markedTextRange;                       // Nil if no marked text.
{
    DEBUG_TEXT(@"-- markedTextRange");

    if (!markedRange.length)
        return nil;
    
    DEBUG_TEXT(@"   (marked text %u+%u is \"%@\")", markedRange.location, markedRange.length, [[_content string] substringWithRange:markedRange]);
    
    return [[[OUEFTextRange alloc] initWithRange:markedRange generation:generation] autorelease];
}

@synthesize markedTextStyle;

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange;  // selectedRange is a range within the markedText
{
    NSRange replaceRange;
    
    NSUInteger adjustedContentLength = [_content length];
    if (adjustedContentLength > 0)
        adjustedContentLength --; // Hidden trailing newline

    if (markedRange.length == 0) {
        if (selection) {
            // Creating a marked range is effectively beginning an insertion operation. So if there is a selected range, we want to delete the text in that range and replace it with the inserted text.
            // (Normally, there will be an empty selection, which just tells us where to insert the marked text.)
            replaceRange = selection.range;
        } else {
            // If there's no selection, append to the end of the text.
            replaceRange.location = adjustedContentLength;
            replaceRange.length = 0;
        }
    } else {
        replaceRange = markedRange;
    }
    
    DEBUG_TEXT(@"Marked text: \"%@\" seln %u+%u replacing %u+%u",
               markedText,
               selectedRange.location, selectedRange.length,
               replaceRange.location, replaceRange.length);
    DEBUG_TEXT(@"  (Marked style: %@)", [markedTextStyle description]);

    if (!markedText)
        markedText = @""; // We get nil from the Japanese input manager on delete sometimes
    
    [self _setSolidCaret:0];
        
    if (!beforeMutate(self, _cmd))
        return;
    
    OBASSERT(NSMaxRange(replaceRange) <= adjustedContentLength);

    [_content replaceCharactersInRange:replaceRange withString:markedText];
    
    NSUInteger markedTextLength = [markedText length];
    
    NSRange newSeln;
    if (selectedRange.location > markedTextLength || selectedRange.location+selectedRange.length > markedTextLength) {
        // OBASSERT_NOT_REACHED("Selected range of marked text extends past end of string");
        // This actually happens regularly: we'll be called with markedText=nil and selectedRange=(NSNotFound,0).
        newSeln = (NSRange){ replaceRange.location + markedTextLength, 0 };
    } else {
        newSeln = (NSRange){ replaceRange.location + selectedRange.location, selectedRange.length };
    }
    
    afterMutate(self, _cmd);
    
    [self willChangeValueForKey:@"markedTextRange"];
    OUEFTextRange *newSelection = [[OUEFTextRange alloc] initWithRange:newSeln generation:generation];
    [self _setSelectedTextRange:newSelection notifyDelegate:NO];
    [newSelection release];
    markedRange = (NSRange){ replaceRange.location, markedTextLength };
    [self didChangeValueForKey:@"markedTextRange"];
    
    notifyAfterMutate(self, _cmd);
        
    [self setNeedsDisplay];
}

- (void)unmarkText;
{
    if (!markedRange.length)
        return;
    
    DEBUG_TEXT(@"Unmarking text");
    [self setNeedsDisplayInRect:markedTextDirtyRect];
    [self willChangeValueForKey:@"markedTextRange"];
    markedRange.location = 0;
    markedRange.length = 0;
    [self didChangeValueForKey:@"markedTextRange"];
}

/* The end and beginning of the the text document. */
- (UITextPosition *)beginningOfDocument
{
    OUEFTextPosition *p = [[[OUEFTextPosition alloc] initWithIndex:0] autorelease];
    p.generation = generation;
    return p;
}

- (UITextPosition *)endOfDocument;
{
    NSUInteger contentLength = [_content length];
    if (contentLength)
        contentLength --; // Keep the trailing newline hidden
    OUEFTextPosition *p = [[[OUEFTextPosition alloc] initWithIndex:contentLength] autorelease];
    p.generation = generation;
    return p;
}

/* Methods for creating ranges and positions. */
- (UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition;
{
    return [[[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)fromPosition
                                             end:(OUEFTextPosition *)toPosition] autorelease];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset;
{
    return [self positionFromPosition:position inDirection:UITextStorageDirectionForward offset:offset];
}

/* True if both or neither of its arguments is true */
#define XNOR(a, b) ((a)? (b) : !(b))

static NSUInteger _leftmostStringIndex(CTRunRef run)
{
    CTRunStatus flags = CTRunGetStatus(run);
#if 0
    if (flags & kCTRunStatusNonMonotonic) {
        /* TODO: Complicated case */
    }
#endif
    CFRange sr = CTRunGetStringRange(run);
    if (flags & kCTRunStatusRightToLeft)
        return ( sr.location + sr.length - 1 );
    else
        return sr.location;
}

static NSUInteger _rightmostStringIndex(CTRunRef run)
{
    CTRunStatus flags = CTRunGetStatus(run);
#if 0
    if (flags & kCTRunStatusNonMonotonic) {
        /* TODO: Complicated case */
    }
#endif
    CFRange sr = CTRunGetStringRange(run);
    if (flags & kCTRunStatusRightToLeft)
        return sr.location;
    else
        return ( sr.location + sr.length - 1 );
}

static NSUInteger moveVisuallyWithinLine(CTLineRef line, NSUInteger pos, NSInteger signedOffset)
{
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex runCount = CFArrayGetCount(runs);
    BOOL rtl;
    NSUInteger offset;
    
    if (signedOffset >= 0) {
        rtl = NO;
        offset = signedOffset;
    } else {
        rtl = YES;
        offset = - signedOffset;
    }
    
    while (offset) {
        CTRunRef run = NULL;
        CFIndex runIndex = searchRuns(runs, 0, runCount, pos, &run);
        if (!run) {
            /* Something broke. Maybe we ran off the beginning/end of the line. */
            return pos;
        }
        CFRange indexRange = CTRunGetStringRange(run);
                
        CTRunStatus flags = CTRunGetStatus(run);
        DEBUG_TEXT(@"moving %@ by %u; pos=%u; found run %d range=(%u%+d) flags=%02x",
              rtl?@"left":@"right", offset, pos, runIndex, indexRange.location, indexRange.length, flags);
#if 0
        if (flags & kCTRunStatusNonMonotonic) {
            /* TODO: Complicated case */
        }
#endif
        if (XNOR(flags & kCTRunStatusRightToLeft, rtl) /* if we're going in the same direction as this run */) {
            CFIndex lastIncludedIndex = indexRange.location + indexRange.length - 1;
            if (( pos + offset ) > (NSUInteger)lastIncludedIndex) {
                offset -= ( pos - lastIncludedIndex );
                pos = lastIncludedIndex;
                goto hopToNextRun;
            } else {
                pos += offset;
                offset = 0;
            }
        } else /* Run is left-to-right and we're going left, or it's right-to-left and we're going right */ {
            if ((pos - indexRange.location) < offset) {
                offset -= ( pos - indexRange.location );
                pos = indexRange.location;
                goto hopToNextRun;
            } else {
                pos -= offset;
                offset = 0;
            }
        }
        
        if(0) {
        hopToNextRun:
            OBASSERT(offset > 0);
            /* We need to jump to the "next" run in one direction or the other. We're assuming that runs are always ordered LTR, regardless of the string layout order, which appears to be experimentally true (but undocumented, of course) */
            
            if (rtl) {
                if (runIndex <= 0) {
                    /* Whoops. */
                    return pos;
                }
                /* we're trying to hop left past the beginning of a run */
                runIndex --;
                pos = _rightmostStringIndex(CFArrayGetValueAtIndex(runs, runIndex));
                offset --;
            } else {
                if (runIndex+1 >= runCount) {
                    /* Whoops. */
                    return pos;
                }
                /* we're trying to hop right past the end of a run */
                runIndex ++;
                pos = _leftmostStringIndex(CFArrayGetValueAtIndex(runs, runIndex));
                offset --;
            }
        }
    }
    
    return pos;
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset;
{
    NSUInteger inGeneration = ((OUEFTextPosition *)position).generation;
    if (inGeneration != generation) {
        DEBUG_TEXT(@"warning: using %@ from gen %u in gen %u", [position description], inGeneration, generation);
    }
    
    if (offset == 0)
        return position;
    
    NSUInteger contentLength = [_content length] - 1;
    NSUInteger pos = [(OUEFTextPosition *)position index];
    NSUInteger result;

    if (direction == UITextStorageDirectionForward || direction == UITextStorageDirectionBackward) {
        if (direction == UITextStorageDirectionBackward)
            offset = -offset;
        
        if (offset < 0 && (NSUInteger)(-offset) >= pos)
            result = 0;
        else
            result = pos + offset;
    } else if (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionRight) {
        if (direction == UITextLayoutDirectionLeft)
            offset = -offset;
        
        /* Find the line containing the position */
        CFArrayRef lines = CTFrameGetLines(drawnFrame);
        /* CFIndex lineCount = CFArrayGetCount(lines); */
        struct typographicPosition measure;
        getTypographicPosition(lines, pos, ( offset < 0 )? -1 : 1, &measure);
        
        if (!measure.line) {
            /* No line for this position? */
            return nil;
        }
        
        result = moveVisuallyWithinLine(measure.line, pos, offset);
    } else if (direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionDown) {
        /* I'm just assuming our CTLines are sorted in order of layout position. I don't know of any reason they wouldn't be. */
        if (direction == UITextLayoutDirectionUp)
            offset = -offset;
        
        /* Find the line containing the position */
        CFArrayRef lines = CTFrameGetLines(drawnFrame);
        CFIndex lineCount = CFArrayGetCount(lines);
        struct typographicPosition measure;
        getTypographicPosition(lines, pos, ( offset < 0 )? -1 : 1, &measure);
        
        if (!measure.line) {
            /* No line for this position? */
            return nil;
        }

        CFIndex newIndex = measure.lineIndex + offset; // note all these variables are signed
        
        /*
         If we've run off the edge, return nil.
         This is a little counterintuitive (and completely undocumented, of course), but it produces much better behavior in the vertical motion case. The input system maintains some saved state for multiple consecutive vertical movements (in order to produce the common x-position-remembering behavior of most text editors) and if we return a clamped position from here, it isn't quite smart enough to realize that further move-up commands aren't modifying the cursor position and don't need to be balanced by an equal number of move-down commands.
         */
        if (newIndex < 0 || newIndex >= lineCount)
            return nil;
        
        if (newIndex == measure.lineIndex)
            return position;
        
        /* Compute a position to look up in the new line. For the Y-coordinate, we want the same position *within* the line; for the X-coordinate, we want the same position within the layout space. CT lines are inherently horizontal (no Chinese typesetting here!), so the Y-position is always 0. */
        CGFloat xPosn = CTLineGetOffsetForStringIndex(measure.line, pos, NULL);
        CGPoint origins[1];
        CTFrameGetLineOrigins(drawnFrame, (CFRange){measure.lineIndex, 1}, origins);
        xPosn = xPosn + origins[0].x; // X-coordinate in layout space
        
        CTFrameGetLineOrigins(drawnFrame, (CFRange){newIndex, 1}, origins);
        xPosn = xPosn - origins[0].x; // X-coordinate in new line's local coordinates
        
        CFIndex newStringIndex = CTLineGetStringIndexForPosition(CFArrayGetValueAtIndex(lines, newIndex), (CGPoint){xPosn, 0});
        
        if (newStringIndex == kCFNotFound)
            return nil;
        
        if(newStringIndex < 0)
            newStringIndex = 0;
        result = newStringIndex;
    } else {
        NSLog(@"Unimplemented movement direction %@", nameof(direction, directions));
        return position;
    }
    
    
    // Don't let the user move past our fake newline
    if (result > contentLength)
        result = contentLength;
    
    OUEFTextPosition *resultPosition = [[[OUEFTextPosition alloc] initWithIndex:result] autorelease];
    resultPosition.generation = inGeneration;
    
    DEBUG_TEXT(@"positionFromPosition(%@, %@, %d) -> %@", [position description], nameof(direction, directions), (int)offset, resultPosition);

    return resultPosition;
}

/* Simple evaluation of positions */
- (NSComparisonResult)comparePosition:(UITextPosition *)position toPosition:(UITextPosition *)other;
{
    return [(OUEFTextPosition *)position compare:other];
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)toPosition;
{
    NSUInteger si = ((OUEFTextPosition *)from).index;
    NSUInteger di = ((OUEFTextPosition *)toPosition).index;
    
    return (NSInteger)di - (NSInteger)si;
}

@synthesize inputDelegate;

/* A tokenizer must be provided to inform the text input system about text units of varying granularity. */
- (id <UITextInputTokenizer>)tokenizer;
{
    if (!tokenizer)
        tokenizer = [[OUITextInputStringTokenizer alloc] initWithTextInput:self];
    return tokenizer;
}

/* Layout questions. */
- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)direction;
{
    /* Storage directions are trivial... */
    if (direction == UITextStorageDirectionForward)
        return range.end;
    if (direction == UITextStorageDirectionBackward)
        return range.start;
    
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
        
    NSRange stringRange = [(OUEFTextRange *)range range];
    CFRange lineRange = [self _lineRangeForStringRange:stringRange];
    
    if (lineRange.length < 1 || lineRange.location < 0)
        return nil;  // Unlikely but not impossible for there to be no lines for this range
    
    UITextPosition *result;
    CGPoint *origins = malloc(sizeof(*origins) * lineRange.length);
    CTFrameGetLineOrigins(drawnFrame, lineRange, origins);
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    
    if (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionRight) {
        
        CFIndex foundPosition = kCFNotFound;
        
        /* Iterate through all the lines, and all the runs in each line. */
        /* Not bothering to try to avoid iterating over runs if we can get what we need from the line as a whole, because lines don't generally have very many runs */
        for(CFIndex lineIndex = 0; lineIndex < lineRange.length; lineIndex ++) {
            CTLineRef thisLine = CFArrayGetValueAtIndex(lines, lineIndex + lineRange.location);
            CFArrayRef runs = CTLineGetGlyphRuns(thisLine);
            CFIndex runCount = CFArrayGetCount(runs);
            for (CFIndex runIndex = 0; runIndex < runCount; runIndex ++) {
                CTRunRef run = CFArrayGetValueAtIndex(runs, runIndex);
                CFRange runRange = CTRunGetStringRange(run);

                if (runRange.location < 0 || runRange.length < 1) {
                    // Empty or invalid run.
                    continue;
                }
                
                if ((NSUInteger)runRange.location >= (stringRange.location+stringRange.length) ||
                    (NSUInteger)(runRange.location+runRange.length) <= stringRange.location) {
                    // This run doesn't overlap the range of interest; skip it
                    continue;
                }
                
                CTRunStatus runFlags = CTRunGetStatus(run);
                
                // Within this run, which storage direction are we interested in?
                BOOL lookingForward = XNOR(runFlags & kCTRunStatusRightToLeft, direction == UITextLayoutDirectionLeft);
                
                // Look at the edge of the run
                CFIndex runEdge;
                if (lookingForward)
                    runEdge = runRange.location + runRange.length - 1;
                else
                    runEdge = runRange.location;
                
                // If the run's edge is not in our range, look at the edge of our range
                if ((NSUInteger)runEdge < stringRange.location ||
                    (NSUInteger)runEdge >= (stringRange.location + stringRange.length)) {
                    if (lookingForward)
                        runEdge = stringRange.location + stringRange.length - 1;
                    else
                        runEdge = stringRange.location;
                    
                    // If the range's edge isn't in the run, either, then they don't overlap
                    if (runEdge < runRange.location || runEdge >= (runRange.location + runRange.length))
                        continue;
                }
                
                CGFloat pos = CTLineGetOffsetForStringIndex(thisLine, runEdge, NULL);
                pos += origins[lineIndex].x;
                
                /* The offset that CTLine gives us is the location of the "starting" edge of the character (depending on the writing direction at that point). We really want the leftmost or rightmost edge, depending on our 'direction' argument. We could optionally move one character to the side, but then we get into trouble at run boundaries (it looks like the secondaryOffset might be intended to help with this, but secondaryOffset is basically uncodumented).  We could retrieve the glyph advance from the CTRun, if needed. For now, I'm just going to punt. */
                    
                if (foundPosition == kCFNotFound ||
                    XNOR(foundPosition < pos, direction == UITextLayoutDirectionRight)) {
                    foundPosition = runEdge;
                }
            }
        }
        
        if (foundPosition < 0 /* kCFNotFound is negative */)
            result = nil;
        else {
            if((NSUInteger)foundPosition == stringRange.location) {
                result = range.start;
            } else {
                OUEFTextPosition *resultPosition = [[OUEFTextPosition alloc] initWithIndex:foundPosition];
                resultPosition.generation = generation;
                result = [resultPosition autorelease];
            }
        }
    } else {
        /* TODO: Need to implement Up/Down, I suppose. Is it ever used? */
        NSLog(@"Unimplemented movement direction %@", nameof(direction, directions));
        result = nil;
    }

    free(origins);
    
    return result;
}

- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction;
{
    /* TODO: Implement this */
    btrace();
    abort();
}

/* Not part of the official UITextInput protocol, but useful */
- (OUEFTextRange *)rangeOfLineContainingPosition:(OUEFTextPosition *)posn;
{
    if (!posn)
        return nil;
    
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    
    CTLineRef containingLine = NULL;
    if (bsearchLines(lines, 0, CFArrayGetCount(lines), posn.index, &containingLine) < 0 || !containingLine)
        return nil;
    
    CFRange lineRange = CTLineGetStringRange(containingLine);
    
    if (lineRange.location < 0) /* kCFNotFound is negative */
        return nil;
    
    OUEFTextRange *result = [[OUEFTextRange alloc] initWithRange:(NSRange){ lineRange.location, lineRange.length } generation:generation];
    return [result autorelease];
}

/* Writing direction */
- (UITextWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction;
{
    /* TODO: Implement this */
    btrace();
    abort();    
}

- (void)setBaseWritingDirection:(UITextWritingDirection)writingDirection forRange:(UITextRange *)range;
{
    /* TODO: Implement this */
    btrace();
    abort();
}    

/* Geometry used to provide, for example, a correction rect. */
static BOOL firstRect(CGPoint p, CGFloat width, CGFloat trailingWS, CGFloat ascent, CGFloat descent, unsigned flags, void *ctxt)
{
    *(CGRect *)ctxt = (CGRect){
        { .x = p.x, .y = p.y },
        { .width = width, .height = ascent }
    };
    return NO;
}
- (CGRect)firstRectForRange:(UITextRange *)range;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    CGRect r = CGRectNull;
    NSRange rn = [(OUEFTextRange *)range range];
    rectanglesInRange(drawnFrame, rn, NO, firstRect, &r);
    
    if (CGRectIsNull(r)) {
        // Huh.
        DEBUG_TEXT(@"firstRectForRange %@ --> null rect", [range description]);
        return r;
    }
    
    // Translate it from layout to rendering coordinates
    r.origin.x += layoutOrigin.x;
    r.origin.y += layoutOrigin.y;
    
    // Convert it from rendering to UIView coordinates
    r = [self convertRectToRenderingSpace:r]; // Method's name is misleading

    DEBUG_TEXT(@"firstRectForRange %@ --> %@", [range description], NSStringFromCGRect(r));
    
    return r;
}

/* This returns the rectangle of the insertion caret, in our bounds coordinates */
- (CGRect)caretRectForPosition:(UITextPosition *)position;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];

    // Get the caret rectangle in rendering coordinates
    CGRect textRect = [self _caretRectForPosition:(OUEFTextPosition *)position affinity:1 bloomScale:0.0];
    // TODO: What if the rect is null here?
    
    // Convert it to UIView coordinates.
    CGRect viewRect = [self convertRectToRenderingSpace:textRect]; // Method's name is misleading

    DEBUG_TEXT(@"caretRectForPosition %@ --> %@", [position description], NSStringFromCGRect(viewRect));
    
    return viewRect;
}

/* Hit testing. */
- (UITextPosition *)closestPositionToPoint:(CGPoint)point;
{
    return [self closestPositionToPoint:point withinRange:nil];
}

CGPoint closestPointInLine(CTLineRef line, CGPoint lineOrigin, CGPoint test, NSRange stringRange, NSUInteger *what)
{
    CGFloat ascent = NAN;
    CGFloat descent = NAN;
    CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    
    CGFloat x = test.x - lineOrigin.x;
    CGFloat y = test.y - lineOrigin.y;
    
    // Clamp the y-coordinate to the line's typographic bounds
    if (y < -descent)
        y = -descent;
    else if(y > ascent)
        y = ascent;
    
    CFRange lineStringRange = CTLineGetStringRange(line);
    
    // Check for past the edges... TODO: bidi booyah
    if (x <= 0 && in_range(stringRange, lineStringRange.location)) {
        *what = lineStringRange.location;
        return (CGPoint){ lineOrigin.x, lineOrigin.y + y };
    }
    if (x >= lineWidth && in_range(stringRange, lineStringRange.location + lineStringRange.length)) {
        *what = lineStringRange.location + lineStringRange.length;
        return (CGPoint){ lineOrigin.x + lineWidth, lineOrigin.y + y };
    }
    
    CFIndex lineStringIndex = CTLineGetStringIndexForPosition(line, (CGPoint){ x, y });
    NSUInteger hitIndex;

    if (lineStringIndex < 0 || ((NSUInteger)lineStringIndex < stringRange.location)) {
        lineStringIndex = stringRange.location;
        hitIndex = stringRange.location;
        x = CTLineGetOffsetForStringIndex(line, lineStringIndex, NULL);
    } else if (((NSUInteger)lineStringIndex - stringRange.location) > stringRange.length) {
        lineStringIndex = stringRange.location + stringRange.length;
        hitIndex = stringRange.location + stringRange.length;
        x = CTLineGetOffsetForStringIndex(line, lineStringIndex, NULL);
    } else {
        hitIndex = lineStringIndex;
    }

    *what = hitIndex;
    return (CGPoint){
        .x = lineOrigin.x + x,
        .y = lineOrigin.y + y
    };
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)viewPoint withinRange:(UITextRange *)range;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    NSRange r;
    CFRange lineRange;
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    CFIndex lineCount = CFArrayGetCount(lines);
    NSUInteger adjustedContentLength = [_content length] - 1;
    
    if (range) {
        r = [(OUEFTextRange *)range range];
        lineRange = [self _lineRangeForStringRange:r];
    } else {
        r.location = 0;
        r.length = adjustedContentLength;
        lineRange.location = 0;
        lineRange.length = lineCount;
    }
    
    if (lineRange.length == 0)
        return nil;

    // Input is in UIView space; we need text layout coordinates.
    CGPoint point = [self convertPointFromRenderingSpace:viewPoint]; // method's name is misleading; this takes a point expressed in view (bounds) coordinates and returns that point's coordinates in the rendering coordinate system
    // text layout coordinates are the same as rendering coordinates except for a translation
    point.x -= layoutOrigin.x;
    point.y -= layoutOrigin.y;    
    
    CGPoint *origins = malloc(sizeof(*origins) * lineRange.length);
    CTFrameGetLineOrigins(drawnFrame, lineRange, origins);

    // Find the pair of lines whose baselines bracket the point
    CFIndex subIndex = 0;
    while (subIndex < lineRange.length && origins[subIndex].y > point.y)
        subIndex ++;
    
    DEBUG_TEXT(@"For p=%.1f,%.1f: line range is %u+%u, subIndex = %u",
               point.x, point.y, lineRange.location, lineRange.length, subIndex);
    
    NSUInteger result;

    if (subIndex == 0) {
        closestPointInLine(CFArrayGetValueAtIndex(lines, lineRange.location), origins[0], point, r, &result);
    } else if (subIndex >= lineRange.length) {
        closestPointInLine(CFArrayGetValueAtIndex(lines, lineRange.location + subIndex - 1), origins[subIndex - 1], point, r, &result);
    } else {
        NSUInteger i1, i2;
        CGPoint p1, p2;
        
        p1 = closestPointInLine(CFArrayGetValueAtIndex(lines, lineRange.location + subIndex), origins[subIndex], point, r, &i1);
        p2 = closestPointInLine(CFArrayGetValueAtIndex(lines, lineRange.location + subIndex - 1), origins[subIndex - 1], point, r, &i2);
        
        if (dist_sqr(p1, point) < dist_sqr(p2, point))
            result = i1;
        else
            result = i2;
    }

    free(origins);
    OUEFTextPosition *p = [[[OUEFTextPosition alloc] initWithIndex:result] autorelease];
    p.generation = generation;
    return p;
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point;
{
    /* TODO: This doesn't ever seem to be called; how to test? */
    
    OUEFTextPosition *pos = (OUEFTextPosition *)[self closestPositionToPoint:point];
    
    if (!pos)
        return nil;
    
    NSRange r = [[_content string] rangeOfComposedCharacterSequenceAtIndex:pos.index];
    
    if (r.location == NSNotFound)
        return nil;

    return [[[OUEFTextRange alloc] initWithRange:r generation:generation] autorelease];
}

#pragma mark UITextInput optional methods

- (NSDictionary *)textStylingAtPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction;
{
    OUEFTextPosition *pos = (OUEFTextPosition *)position;
    NSUInteger index = pos.index;
    
    NSDictionary *ctStyles;
    if (direction == UITextStorageDirectionBackward && index > 0)
        ctStyles = [_content attributesAtIndex:index-1 effectiveRange:NULL];
    else
        ctStyles = [_content attributesAtIndex:index effectiveRange:NULL];
    
    /* TODO: Return typingAttributes, if position is the same as the insertion point? */

    NSMutableDictionary *uiStyles = [ctStyles mutableCopy];
    [uiStyles autorelease];
    
    CTFontRef ctFont = (CTFontRef)[ctStyles objectForKey:(id)kCTFontAttributeName];
    if (ctFont) {
        /* As far as I can tell, the name that UIFont wants is the PostScript name of the font. (It's undocumented, of course. RADAR 7881781 / 7241008) */
        CFStringRef fontName = CTFontCopyPostScriptName(ctFont);
        UIFont *uif = [UIFont fontWithName:(id)fontName size:CTFontGetSize(ctFont)];
        CFRelease(fontName);
        [uiStyles setObject:uif forKey:UITextInputTextFontKey];
    }
    
    CGColorRef cgColor = (CGColorRef)[ctStyles objectForKey:(id)kCTForegroundColorAttributeName];
    if (cgColor)
        [uiStyles setObject:[UIColor colorWithCGColor:cgColor] forKey:UITextInputTextColorKey];
    
    if (self.backgroundColor)
        [uiStyles setObject:self.backgroundColor forKey:UITextInputTextBackgroundColorKey];
    
    return uiStyles;
}

//- (UITextPosition *)positionWithinRange:(UITextRange *)range atCharacterOffset:(NSInteger)offset;
//- (NSInteger)characterOffsetOfPosition:(UITextPosition *)position withinRange:(UITextRange *)range;

- (UIView *)textInputView
{
    DEBUG_TEXT(@"-textInputView called");
    return self;
}

//@property (nonatomic) UITextStorageDirection selectionAffinity;

#pragma mark -
#pragma mark Private

- (CFRange)_lineRangeForStringRange:(NSRange)queryRange;
{
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    CFIndex lineCount = CFArrayGetCount(lines);
    
    CFIndex queryEnd = queryRange.location + queryRange.length;
    
    CTLineRef firstMatchingLine = NULL;
    CFIndex firstResultLine = bsearchLines(lines, 0, lineCount, queryRange.location, &firstMatchingLine);
    if (firstResultLine < 0)
        return (CFRange){ 0, 0 };
    if (firstResultLine >= lineCount)
        return (CFRange){ lineCount, 0 };
    
    CFRange lineStringRange = CTLineGetStringRange(firstMatchingLine);
    if ((lineStringRange.location + lineStringRange.length) >= queryEnd)
        return (CFRange){ firstResultLine, 1 };
    
    CFIndex lastResultLine = bsearchLines(lines, firstResultLine+1, lineCount, queryEnd, NULL);
    if (lastResultLine < firstResultLine)
        return (CFRange){ firstResultLine, 0 };
    if (lastResultLine >= lineCount)
        return (CFRange){ firstResultLine, lineCount - firstResultLine };
    return (CFRange){ firstResultLine, lastResultLine - firstResultLine + 1 };
}


/* This returns the rectangle of the insertion caret, in our rendering coordinates */
/* The returned rectangle may be CGRectNull */
- (CGRect)_caretRectForPosition:(OUEFTextPosition *)position affinity:(int)affinity bloomScale:(double)bloomScale;
{
    OBPRECONDITION(drawnFrame && !flags.textNeedsUpdate);
    
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    
    struct typographicPosition measures;
    
    NSUInteger positionIndex = position.index;
    if (positionIndex >= [_content length])
        positionIndex = [_content length] - 1;
    getTypographicPosition(lines, positionIndex, affinity, &measures);
    if (!measures.line) {
        // It's possible for getTypographicPosition() to fail, if the specified position isn't in any line.
        // The most likely case here is that we've been given a finite textLayoutSize and the caret's moved outside of the laid-out range.
        return CGRectNull;
        // TODO: Make sure all callers behave well if they get CGRectNull!
    }
    
    CGFloat secondaryOffset = nanf(NULL);
    CGFloat characterOffset = CTLineGetOffsetForStringIndex(measures.line, measures.adjustedIndex, &secondaryOffset);
    
    CGFloat ascent = nanf(NULL);
    CGFloat descent = nanf(NULL);
    CTLineGetTypographicBounds(measures.line, &ascent, &descent, NULL);
    
    CGPoint lineOrigin[1];
    CTFrameGetLineOrigins(drawnFrame, (CFRange){ .location = measures.lineIndex, .length = 1 }, lineOrigin);
    
    // Build the caret rect in text layout space
    CGRect textRect;
    textRect.origin.x = lineOrigin[0].x + characterOffset;
    textRect.origin.y = lineOrigin[0].y - descent;
    textRect.size.width = MAX(1.0, secondaryOffset - characterOffset);
    textRect.size.height = ascent + descent;
    
    // Translate to rendering coordinates
    textRect.origin.x += layoutOrigin.x;
    textRect.origin.y += layoutOrigin.y;
    
    // Add an extra couple of pixels of size for visibility
    // The bloomScale parameter tells us how to relate our coordinate system to device pixels
    // bloomScale=0 --> don't bloom
    // bloomScale>0 --> scale factor
    // we further limit the range of bloomScale we accept just for sanity's sake
    if (bloomScale > 1e-2)
        return CGRectInset(textRect, -1 / bloomScale, -1 / bloomScale);
    else
        return textRect;
}

- (void)_setSelectionToIndex:(NSUInteger)ix
{
    OUEFTextRange *newSelection = [[OUEFTextRange alloc] initWithRange:(NSRange){ ix, 0 } generation:generation];
    [self _setSelectedTextRange:newSelection notifyDelegate:NO];
    [newSelection release];
}

/* Text may have a selection, either zero-length (a caret) or ranged.  Editing operations are
 * always performed on the text from this selection.  nil corresponds to no selection. */
- (void)_setSelectedTextRange:(OUEFTextRange *)newRange notifyDelegate:(BOOL)shouldNotify;
{
    if (newRange == selection)
        return;
    
    if (newRange && selection && [newRange isEqual:selection])
        return;
    
    /* TODO: If the old and new selections are both ranges, and only differ by a few characters at one end, we can potentially save a lot of redraw by computing the difference and redrawing only the extension/contraction */
    
    if (!CGRectIsEmpty(selectionDirtyRect)) {
        [self setNeedsDisplayInRect:selectionDirtyRect];
        selectionDirtyRect = CGRectNull;
    }
    
    if (newRange && (![newRange isEmpty] || flags.solidCaret))
        [self _setNeedsDisplayForRange:newRange];
    
    if (shouldNotify)
        [inputDelegate selectionWillChange:self];
    [selection release];
    selection = [newRange retain];
    if (typingAttributes) {
        [typingAttributes release];
        typingAttributes = nil;
    }
    if (shouldNotify)
        [inputDelegate selectionDidChange:self];
    
    [self setNeedsLayout];
}

/* This determines whether our caret is solid (and drawn by us in -drawScaledContent:) or blinking (and drawn by our subview OUITextSelectionOverlay). */
/* Calling this method even with a 0 delta always resets the activity timer */
- (void)_setSolidCaret:(int)delta;
{
    /* The _caretSolidity variable keeps track of how we're displaying the caret currently.
        0, _solidityTimer==nil -> Caret is not solid; we don't draw it, but we ask our overlay view to draw it (and blink).
        0, _solidityTimer!=nil -> Caret is solid because of recent activity. Once the timer fires, it'll become less solid.
        >0                     -> Caret is locked into solid mode during an extended operation such as drag-selection.
    */
    
    _caretSolidity += delta;
    
    // NSLog(@"Caret solidity %+d  -->  %d", delta, _caretSolidity);
    
    if (_caretSolidity == 0) {
        /* Make sure the expiration timer is scheduled far enough out */
        NSDate *solidUntil = [NSDate dateWithTimeIntervalSinceNow:CARET_ACTIVITY_SOLID_INTERVAL];
        
        if (!_solidityTimer) {
            _solidityTimer = [[NSTimer alloc] initWithFireDate:solidUntil interval:0 target:self selector:@selector(_inactiveCaret:) userInfo:nil repeats:NO];
            [[NSRunLoop currentRunLoop] addTimer:_solidityTimer forMode:NSRunLoopCommonModes];
        } else if ([[_solidityTimer fireDate] compare:solidUntil] == NSOrderedAscending)
            [_solidityTimer setFireDate:solidUntil];
    }
    
    if (!flags.solidCaret) {
        flags.solidCaret = 1;
        [self _setNeedsDisplayForRange:selection];
        [self setNeedsLayout];
    }
}

- (void)_inactiveCaret:(NSTimer *)t
{
    OBINVARIANT(t == _solidityTimer);
    if (t != _solidityTimer)
        return;
    
    // The caret should always be solid when the timer fires
    OBPRECONDITION(flags.solidCaret);
    
    [_solidityTimer autorelease];
    _solidityTimer = nil;
    
    // NSLog(@"Solidity timer expired; _caretSolidity = %d", _caretSolidity);
    
    if (_caretSolidity > 0) {
        // Timer expired, but we're solid for some other reason.
        return;
    }
    
    flags.solidCaret = 0;
    
    // We'll need to redraw the text under the solid caret
    [self setNeedsDisplayInRect:selectionDirtyRect];
    
    // And re-show and re-position the non-slid caret overlay view
    [self setNeedsLayout];
}

/* This is called by the tap recognizer when we don't have focus */
- (void)_idleTap;
{
    if (![self isFirstResponder] && [self canBecomeFirstResponder])
        [self becomeFirstResponder];
}

- (UITextRange *)selectionRangeForPoint:(CGPoint)p wordSelection:(BOOL)selectWords;
{
    OUEFTextPosition *pp = (OUEFTextPosition *)[self closestPositionToPoint:p];
    if (!pp)
        return nil;
    
    UITextRange *textRange = nil;
    id <UITextInputTokenizer> tok = [self tokenizer];

    OUEFTextPosition *earlier = nil;
    OUEFTextPosition *later = nil;
    
    if (tapSelectionGranularity != UITextGranularityCharacter) {
        // UITextView selects beginning or end of word on single tap.
        if (![tok isPosition:pp atBoundary:tapSelectionGranularity inDirection:UITextStorageDirectionForward] &&
            ![tok isPosition:pp atBoundary:tapSelectionGranularity inDirection:UITextStorageDirectionBackward]) {
            // Move pp to the nearest word boundary. We can't simply use -rangeEnclosingPosition: because we want to move to a word boundary even if the tap was outside of any words.
            // We also need to act correctly if tapped in a non-word area at the beginning or end of the text.
            earlier = (OUEFTextPosition *)[tok positionFromPosition:pp toBoundary:tapSelectionGranularity inDirection:UITextStorageDirectionBackward];
            later = (OUEFTextPosition *)[tok positionFromPosition:pp toBoundary:tapSelectionGranularity inDirection:UITextStorageDirectionForward];
            if (earlier && later) {
                if ([earlier index] > [later index]) {  // not sure why, but earlier seems to always be later than later
                    id temp = earlier;
                    earlier = later;
                    later = temp;
                }
                if (abs([self offsetFromPosition:pp toPosition:earlier]) < abs([self offsetFromPosition:pp toPosition:later]))
                    pp = earlier;
                else
                    pp = later;
            } else if (earlier)
                pp = earlier;
            else if (later)
                pp = later;
        }
    }

    if (selectWords && earlier && later) {
        textRange = [[[OUEFTextRange alloc] initWithStart:earlier end:later] autorelease];
    } else {
        textRange = [[[OUEFTextRange alloc] initWithStart:pp end:pp] autorelease];
    }
        
    return textRange;
}

/* Both the single-tap and double-tap recognizers call this */
- (void)_activeTap:(UITapGestureRecognizer *)r;
{
    DEBUG_TEXT(@" -> %@", r);
    CGPoint p = [r locationInView:self];
    UITextRange *newSelection = [self selectionRangeForPoint:p wordSelection:(r.numberOfTapsRequired > 1)];
                                 
    if (newSelection) {        
        if (r.numberOfTapsRequired > 1) {
            [self setSelectedTextRange:newSelection];
        } else {
            if ([newSelection isEqual:selection]) {
                // Apple's text editor behaves this way: if you tap-to-select on the same point twice (as opposed to a double-tap, which is a different gesture), then it shows the context menu...
                flags.showingEditMenu = 1;
                [self setNeedsLayout];
            } else {
                // ...but normally, adjusting the insertion point, like typing, will dismiss the context menu.
                flags.showingEditMenu = 0;
                [self setSelectedTextRange:newSelection];
            }
        }
    }
    
    // Reset the caret solidity timer even if we don't otherwise react to this tap, to indicate we did at least receive it
    [self _setSolidCaret:0];
}

/* Press-and-hold calls this */
- (void)_inspectTap:(UILongPressGestureRecognizer *)r;
{    
    CGPoint touchPoint = [r locationInView:self];
    OUEFTextPosition *pp = (OUEFTextPosition *)[self closestPositionToPoint:touchPoint];
    
    //NSLog(@"inspect with state %d at %@ with required taps %d, number of touches %d", r.state, pp, [r numberOfTapsRequired], [r numberOfTouches]);
    
    UIGestureRecognizerState state = r.state;
    
    if (state == UIGestureRecognizerStateBegan) {
        if (!_loupe) {
            _loupe = [[OUILoupeOverlay alloc] initWithFrame:[self frame]];
            [_loupe setSubjectView:self];
            [[[[self window] subviews] lastObject] addSubview:_loupe];
        }
        
        [self _setSolidCaret:1];
    }
    
    // We want to update the loupe's touch point before the mode, so that when it's brought on screen it doesn't animate distractingly out from some other location.
    _loupe.touchPoint = touchPoint;
    
    if (state == UIGestureRecognizerStateChanged) {
        UITextRange *newSelection = nil;
        
        /* This by-word selection is only a rough approximation to the by-word selection that UITextView does */
        if ([r numberOfTapsRequired] > 1)
            newSelection = [[self tokenizer] rangeEnclosingPosition:pp withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
        
        if (newSelection) {
            [self setSelectedTextRange:newSelection];
        } else {
            newSelection = [[OUEFTextRange alloc] initWithStart:pp end:pp];
            [self setSelectedTextRange:newSelection];
            [newSelection release];
        }
    }
    
    /* UITextView has two selection inspecting/altering modes: caret and range. If you have a caret, you get a round selection inspection that just alters the inspection point. If you have a range, then the end of the range that your tap is closest to is altered and a rectangular selection inspector is shown. */
    if (selection) {
        if ([selection isEmpty])
            _loupe.mode = OUILoupeOverlayCircle;
        else 
            _loupe.mode = OUILoupeOverlayRectangle;
    } else
        _loupe.mode = OUILoupeOverlayNone;
    
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        _loupe.mode = OUILoupeOverlayNone;
        flags.showingEditMenu = 1;  // Hint that the edit menu would be appropriate once the loupe disappears.
        [self _setSolidCaret:-1];
        return;
    }
}

/* Used by the addRectsToPath() callback */
struct rectpathwalker {
    CGContextRef ctxt;            // context to append rects to
    CGPoint layoutOrigin;         // translation between ctxt's and text's coordinate systems
    CGFloat leftEdge, rightEdge;  // left & right text edges (in ctxt's coordinate system)
    CGRect bounds;                // Accumulated bounding box of rectangles drawn
    struct rectpathwalkerLineBottom {
        CGFloat descender, left, right;
    } currentLine, previousLine;
    BOOL includeInterline;        // Whether to extend lines vertically to fill gaps
};

/* Convenience routine for initializing the fields of rectpathwalker */
static void getMargins(OUIEditableFrame *self, struct rectpathwalker *r)
{
    CGRect bounds = [self convertRectFromRenderingSpace:[self bounds]];  // Note -convertRectFromRenderingSpace: is misleadingly named
    r->layoutOrigin = self->layoutOrigin;
    r->leftEdge = bounds.origin.x + self->textInset.left;
    r->rightEdge = bounds.origin.x + bounds.size.width - ( self->textInset.left + self->textInset.right );
    r->bounds = CGRectNull;
    
    r->currentLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
    r->previousLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
}

static BOOL addRectsToPath(CGPoint p, CGFloat width, CGFloat trailingWS, CGFloat ascent, CGFloat descent, unsigned flags, void *ctxt)
{
    struct rectpathwalker *r = ctxt;
    
#if 0
    {
        NSMutableString *b = [NSMutableString stringWithFormat:@"p=(%.1f,%.1f) x+w=%.1f flags=", p.x, p.y, p.x+width];
        if (flags & rectwalker_FirstLine) [b appendString:@"F"];
        if (flags & rectwalker_FirstRectInLine) [b appendString:@"f"];
        if (flags & rectwalker_LeftIsRangeBoundary) [b appendString:@"L"];
        if (flags & rectwalker_LeftIsLineWrap) [b appendString:@"l"];
        if (flags & rectwalker_RightIsLineWrap) [b appendString:@"r"];
        if (flags & rectwalker_RightIsRangeBoundary) [b appendString:@"R"];
        NSLog(@"%@", b);
    }
#endif
    
    /*
     layoutOrigin is the location (in our rendering coordinates) of the origin of the layout space.
     Layout space has Y increasing upwards; view space has Y increasing downwards.
     */
    
    CGRect highlightRect;
    
    highlightRect.origin.x = r->layoutOrigin.x + p.x;
    highlightRect.origin.y = r->layoutOrigin.y + p.y - descent;
    highlightRect.size.height = ascent + descent;
    
    if (flags & (rectwalker_LeftIsLineWrap|rectwalker_RightIsLineWrap)) {
        /* In general, if we're drawing something that wraps around the left or right side of the text, we want to extend the notional rectangle out to the corresponding margin */
        if ((flags & rectwalker_LeftIsLineWrap) && (r->leftEdge < highlightRect.origin.x))
            highlightRect.origin.x = r->leftEdge;
        
        CGFloat rightx = r->layoutOrigin.x + p.x + width;
        CGFloat adjustedRightx = rightx;
        if ((flags & rectwalker_RightIsLineWrap) && (r->rightEdge > rightx))
            adjustedRightx = r->rightEdge;
        
        /* Even though trailing whitespace can extend into the right margin when text is right-justified, it's distracting to see the little ragged edges of those spaces in a multiline selection. So we trim them off here. */
        if (rightx > r->rightEdge && trailingWS > 0)
            adjustedRightx = MAX(r->rightEdge, rightx - trailingWS);
        
        highlightRect.size.width = adjustedRightx - highlightRect.origin.x;
    } else {
        highlightRect.size.width = width;
    }
    
    if (r->includeInterline) {
        if (flags & rectwalker_FirstRectInLine) {
            /* If we're the first rectangle in the line, set up our record of this line's highlights' extent, and possibly copy the previously calculated record to previousLine. */
            if (!(flags & rectwalker_FirstLine)) {
                r->previousLine = r->currentLine;
            }
            r->currentLine = (struct rectpathwalkerLineBottom){
                .descender = highlightRect.origin.y,
                .left = highlightRect.origin.x,
                .right = CGRectGetMaxX(highlightRect)
            };
        } else {
            /* If we're the Nth rectangle on this line, just extend the value to encompass our rectangle. */
            if (r->currentLine.descender > highlightRect.origin.y)
                r->currentLine.descender = highlightRect.origin.y;
            if (r->currentLine.left < highlightRect.origin.x)
                r->currentLine.left = highlightRect.origin.x;
            if (r->currentLine.right > CGRectGetMaxX(highlightRect))
                r->currentLine.right = CGRectGetMaxX(highlightRect);
        }
        
        /* If we have a previous line, and its horizontal extent overlaps our own, check to see whether we should extend the top of our rectangle to meet it */
        if (!(flags & rectwalker_FirstLine) &&
            r->previousLine.right > highlightRect.origin.x &&
            r->previousLine.left < CGRectGetMaxX(highlightRect)) {
            CGFloat extendedHeight = r->previousLine.descender - highlightRect.origin.y;
            highlightRect.size.height = MAX(highlightRect.size.height, extendedHeight);
        }
    }
    
    r->bounds = CGRectUnion(r->bounds, highlightRect);
    
    if (r->ctxt)
        CGContextAddRect(r->ctxt, highlightRect);
    
    // NSLog(@"Adding rect(me) -> %@ (raw %@)", NSStringFromCGRect(highlightRect), NSStringFromCGPoint(p));
    
    return YES;
}

- (void)_drawSelectionInContext:(CGContextRef)ctx
{
    if (!drawnFrame || flags.textNeedsUpdate)
        return;
    
    if (!selection) {
        // No selection no draw
        return;
    }
    
    NSRange selectionRange = [selection range];
    CFRange lineRange = [self _lineRangeForStringRange:selectionRange];
    
    //DEBUG_TEXT(@"Selection %u+%u -> lines %u+%u", selectionRange.location, selectionRange.length, lineRange.location, lineRange.length);
    
    if (lineRange.length < 1) {
        // ?? Shouldn't happen, but if it does, I can't think of a reasonable thing to draw. So, punt.
    } else {
        struct rectpathwalker ctxt;
        ctxt.ctxt = ctx;
        ctxt.includeInterline = YES;
        getMargins(self, &ctxt);
        
        OBASSERT(_rangeSelectionColor);
        [_rangeSelectionColor setFill];
        CGContextBeginPath(ctx);
        
        rectanglesInRange(drawnFrame, selectionRange, NO, addRectsToPath, &ctxt);
        
        // Filling the rects as a single path avoids overlapping alpha compositing on the edges.
        CGContextFillPath(ctx);
        
        // Record the rect we dirtied so we can redraw when the selection changes
        selectionDirtyRect = [self convertRectToRenderingSpace:ctxt.bounds]; // note this method does the opposite of what its name implies
    }
}

static BOOL includeRectsInBound(CGPoint p, CGFloat width, CGFloat trailingWS, CGFloat ascent, CGFloat descent, unsigned flags, void *ctxt)
{
    CGRect *r = ctxt;
    
    if (trailingWS < width)
        width -= trailingWS;
    
    CGRect highlightRect = (CGRect){
        .origin = {
            .x = p.x,
            .y = p.y - descent
        },
        .size = { width, ascent + descent }
    };
    
    /* NB CGRectUnion() is documented to handle null rectangles */
    *r = CGRectUnion(*r, highlightRect);
    
    return YES;
}

/* This is used to find the bounding box of our current selection when we want to point some UI element at it (either the context menu or the popover inspector) */
/* The rectangle is returned in view-bounds coordinates, and may be CGRectNull */
- (CGRect)_boundsOfRange:(OUEFTextRange *)range;
{
    CGRect bound;
    
    if ([range isEmpty]) {
        bound = [self _caretRectForPosition:(OUEFTextPosition *)(range.start) affinity:0 bloomScale:0];

        if (CGRectIsNull(bound))
            return bound;
    } else {
        bound = CGRectNull;
        
        rectanglesInRange(drawnFrame, [range range], NO, includeRectsInBound, &bound);
        
        if (CGRectIsNull(bound))
            return bound;
            
        /* Shift from text coordinates to rendering coordinates */
        bound.origin.x += layoutOrigin.x;
        bound.origin.y += layoutOrigin.y;
    }
    
    /* Shift from rendering coordinates to view/bounds coordinates; note that the method is confusingly named */
    return [self convertRectToRenderingSpace:bound];
}

/* We have some decorations that are drawn over the text instead of under it */
- (void)_drawDecorations:(CGContextRef)ctx
{
    /* Draw a thin box around the marked range. We may also want to give it a slightly different background color? */
    if (markedRange.length) {
        struct rectpathwalker ctxt;
        ctxt.ctxt = ctx;
        ctxt.includeInterline = NO;
        getMargins(self, &ctxt);
        
        OBASSERT(_rangeSelectionColor);
        [[UIColor blackColor] setStroke];
        CGContextSetLineWidth(ctx, 0.5);
        CGContextBeginPath(ctx);
        
        rectanglesInRange(drawnFrame, markedRange, NO, addRectsToPath, &ctxt);
        
        CGContextStrokePath(ctx);
        markedTextDirtyRect = ctxt.bounds;
    }
    
    /* If we're not using a separate view to draw our caret, draw it here */
    if (flags.solidCaret) {
        if (selection && [selection isEmpty]) {
            // If we're being drawn zoomed, we might not need as much enlargement of the caret in order for it to be visible
            CGFloat nominalScale = self.scale;
            double actualScale = sqrt(fabs(OQAffineTransformGetDilation(CGContextGetCTM(ctx))));

            CGRect caretRect = [self _caretRectForPosition:(OUEFTextPosition *)(selection.start) affinity:1 bloomScale:MAX(nominalScale, actualScale)];
            
            if (!CGRectIsEmpty(caretRect)) {
                [_insertionPointSelectionColor setFill];
                CGContextFillRect(ctx, caretRect);
                selectionDirtyRect = [self convertRectToRenderingSpace:caretRect]; // note this method does the opposite of what its name implies
            }
        }
    }
}

- (void)_setNeedsDisplayForRange:(OUEFTextRange *)range;
{
    if (!range)
        return;
    
    if (flags.textNeedsUpdate || !drawnFrame) {
        // Can't compute the affected range without valid layout information.
        // We can't do partial layout yet, so we're going to do a full redisplay soon anyway, which should take care of this range as well.
        return;
    }
    
    CGRect dirtyRect;
    
    if ([range isEmpty]) {
        // The caret rectangle.
        // NB this must match the corresponding calculation in _drawDecorations:, but it only needs to match in the normal case where we're drawing into our own rectangle (as opposed to the loupe case which _drawDecorations: also needs to handle)
        dirtyRect = [self _caretRectForPosition:(OUEFTextPosition *)(range.start) affinity:1 bloomScale:self.scale];
    } else {
        /* We don't want the same behavior as _boundsOfRange: here, unfortunately: that method intentionally doesn't extend the rect out to the margins when a line wraps, because the extra area doesn't have any actual text in it for the UI element to point to. On the other hand, _setNeedsDisplayForRange: is usually called to invalidate a rectangle so that the selection can redraw, and we need to extend out in the same way that the selection-drawing code does. */
        struct rectpathwalker ctxt;
        ctxt.ctxt = NULL;  // addRectsToPath() will happily ignore a NULL CGContextRef for us
        ctxt.includeInterline = YES; // shouldn't actually have any effect
        getMargins(self, &ctxt);
        
        rectanglesInRange(drawnFrame, [range range], YES /* quick and sloppy */, addRectsToPath, &ctxt);
        
        dirtyRect = ctxt.bounds;
    }
    
    if (CGRectIsEmpty(dirtyRect)) {
        // If there's no rectangle for this range, I guess we don't need to redraw anything.
        return;
    }
    
    [self setNeedsDisplayInRect:CGRectIntegral([self convertRectToRenderingSpace:dirtyRect])];
    // (note that -convertRectToRenderingSpace: does the opposite of what its name suggests)
}

- (void)_updateLayout:(BOOL)computeDrawnFrame
{
    OBPRECONDITION(_content);
    
    if (!framesetter || flags.textNeedsUpdate) {
        if (drawnFrame) {
            CFRelease(drawnFrame);
            drawnFrame = NULL;
        }
        if (framesetter) {
            CFRelease(framesetter);
            framesetter = NULL;
        }
        
        [immutableContent release];
        
        immutableContent = OUICreateTransformedAttributedString(_content, _linkTextAttributes);
        if (immutableContent) {
            flags.immutableContentHasAttributeTransforms = YES;
        } else {
            // Didn't need transformation
            immutableContent = [_content copy];
            flags.immutableContentHasAttributeTransforms = NO;
        }
        
        framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)immutableContent);
        
        flags.textNeedsUpdate = NO;
    }
    
    while (computeDrawnFrame && !drawnFrame) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGRect bounds = self.bounds;

        // Default to filling our bounds width and growing "infinitely" high.
        CGSize frameSize = bounds.size;
        const CGFloat kUnlimitedSize = 10000;
        
        if (CGSizeEqualToSize(layoutSize, CGSizeZero)) {
            frameSize.height = kUnlimitedSize;
        } else {
            // Owner would like us to constrain along width or height.
            if (layoutSize.width > 0)
                frameSize.width = layoutSize.width;
            if (layoutSize.height > 0)
                frameSize.height = layoutSize.height;
        }
        
        // CTFramesetterCreateFrame() will return NULL if the given path's area is zero. On the initial set up of a field editor, though, you might know the width you want but not the height. So, you have to give a width one way or the other, but if you haven't given a height, we'll give a minimum.
        if (frameSize.width == 0) {
            OBASSERT_NOT_REACHED("Using unlimited layout width since none was specified"); // Need to specify one implicitly via the view frame or textLayoutSize property. 
            frameSize.width = kUnlimitedSize;
        }
        if (frameSize.height == 0) {
            OBASSERT_NOT_REACHED("Using unlimited layout height since none was specified"); // Need to specify one implicitly via the view frame or textLayoutSize property. 
            frameSize.height = kUnlimitedSize;
        }
        
        // Adjust from UIView coordinates to CoreGraphics rendering coordinates.
        CGFloat scale = self.scale;
        CGFloat invScale = 1.0/scale;
        frameSize.width *= invScale;
        frameSize.height *= invScale;
        
        DEBUG_TEXT(@"  Laying out with bounds %@, CG size %@", NSStringFromCGRect(bounds), NSStringFromCGSize(frameSize));
        
        CGPathAddRect(path, NULL, CGRectMake(0, 0, frameSize.width, frameSize.height));
        
        drawnFrame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, NULL);
        
        CFRelease(path);
        
        // Calculate the used size (ignoring the text inset, if any).
        CGRect typographicFrame = OUITextLayoutMeasureFrame(drawnFrame, YES);
        _usedSize = typographicFrame.size;
        
        layoutOrigin = OUITextLayoutOrigin(typographicFrame, textInset, bounds, scale);
        
        if (flags.delegateRespondsToLayoutChanged)
            [delegate textViewLayoutChanged:self];
    }
    
    [self setNeedsLayout];
}

- (void)_moveInDirection:(UITextLayoutDirection)direction
{
    UITextRange *selectionRange = self.selectedTextRange;
    UITextPosition *positionToSelect;
    
    if (selectionRange.isEmpty) {
        positionToSelect = [self positionFromPosition:selectionRange.start inDirection:direction offset:1];
    } else {
        // Select the beginning or end of the range
        // TODO: Appropriately map right/left to start/end based on text direction
        switch (direction) {
            case UITextStorageDirectionForward:
            case UITextLayoutDirectionRight:
            case UITextLayoutDirectionDown:
            default:
                positionToSelect = selectionRange.end;
                break;
            case UITextStorageDirectionBackward:
            case UITextLayoutDirectionLeft:
            case UITextLayoutDirectionUp:
                // TODO: Also handle UITextLayoutDirectionTop, UITextLayoutDirectionStrange, UITextLayoutDirectionCharmed
                positionToSelect = selectionRange.start;
                break;
        }
    }
    
    /* If there is no position in that direction (e.g., we've gone off the top or bottom of the text) then do nothing. */
    if (!positionToSelect)
        return;
    
    UITextRange *rangeToSelect = [self textRangeFromPosition:positionToSelect toPosition:positionToSelect];
    [self unmarkText];
    [self _setSelectedTextRange:(OUEFTextRange *)rangeToSelect notifyDelegate:YES];
}

#pragma mark Context menu methods
- (NSSet *)inspectableTextSpans;
{
    if (!selection)
        return nil;
    
    NSMutableSet *runs = [NSMutableSet set];

    NSRange range = [selection range];
    while(range.length > 0) {
        NSRange effective;
        /* NSDictionary *d = */ [_content attributesAtIndex:range.location longestEffectiveRange:&effective inRange:range];
        OUEFTextSpan *run = [[OUEFTextSpan alloc] initWithRange:effective generation:generation editor:self];
        [runs addObject:run];
        [run release];
        
        NSUInteger loc = effective.location + effective.length;
        if (loc >= range.location + range.length)
            break;
        else {
            range.length = range.location + range.length - loc;
            range.location = loc;
        }
    }
    
    return runs;
}

- (void)inspectSelectedText:(id)sender
{
    NSSet *runs = [self inspectableTextSpans];
    if (!runs)
        return;
    
    CGRect selectionRect = [self _boundsOfRange:selection];
    if (CGRectIsEmpty(selectionRect))
        return;
        
    DEBUG_TEXT(@"Inspecting: %@ rect: %@", [runs description], NSStringFromCGRect(selectionRect));
    
    if (!_textInspector) {
        _textInspector = [[OUIInspector alloc] init];
        _textInspector.delegate = self;
    }
    
    [_textInspector inspectObjects:runs fromRect:selectionRect inView:self permittedArrowDirections:UIPopoverArrowDirectionAny];
}

#pragma mark OUIInspectorDelegate

- (NSString *)inspectorTitle:(OUIInspector *)inspector;
{
    return NSLocalizedStringFromTableInBundle(@"Text Style", @"Inspectors", OMNI_BUNDLE, @"Inspector title");
}

- (NSArray *)inspectorSlices:(OUIInspector *)inspector;
{
    NSMutableArray *slices = [NSMutableArray array];
    [slices addObject:[[[OUIColorInspectorSlice alloc] init] autorelease]];
    [slices addObject:[[[OUIFontInspectorSlice alloc] init] autorelease]];
    [slices addObject:[[[OUIParagraphStyleInspectorSlice alloc] init] autorelease]];

    return slices;
}

- (void)inspectorDidDismiss:(OUIInspector *)inspector;
{
    [self becomeFirstResponder];
}


@end

