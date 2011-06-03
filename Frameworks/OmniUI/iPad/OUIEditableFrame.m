// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEditableFrame.h>

#import <Foundation/NSAttributedString.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <OmniAppKit/OATextStorage.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFCharacterSet.h>
#import <OmniFoundation/OFNull.h>
#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIColorInspectorSlice.h>
#import <OmniUI/OUIDirectTapGestureRecognizer.h>
#import <OmniUI/OUIFontAttributesInspectorSlice.h>
#import <OmniUI/OUIFontInspectorSlice.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/OUITextColorAttributeInspectorSlice.h>
#import <OmniUI/OUITextLayout.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUITextExampleInspectorSlice.h>
#import <QuartzCore/QuartzCore.h>

#import <execinfo.h>
#import <stdlib.h>

#import "OUIParagraphStyleInspectorSlice.h"
#import "OUITextThumb.h"
#import "OUEFTextPosition.h"
#import "OUEFTextRange.h"
#import "OUITextInputStringTokenizer.h"
#import "OUITextCursorOverlay.h"
#import "OUILoupeOverlay.h"
#import "OUEFTextSpan.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_TEXT(format, ...) NSLog(@"TEXT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_TEXT(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_EDITING(format, ...) NSLog(@"TEXT EDIT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_EDITING(format, ...)
#endif

/* TODO: If low memory and not first responder, clear out actionRecognizers[] */

#define CARET_ACTIVITY_SOLID_INTERVAL 0.75

#define OUIRound(x) roundf(x)
#define OUIFloor(x) floorf(x)

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

// Radar 9138543: Make UITextLayoutDirection compatible with new clang-2 warning
// clang-2 (at r127704) warns when casting enum types, but UITextLayoutDirection is an extension of UITextStorageDirection which fails to redeclare the forward/backward members. Rather than scatter casts all over, define some constants here.
#define OUITextLayoutDirectionForward ((UITextLayoutDirection)UITextStorageDirectionForward)
#define OUITextLayoutDirectionBackward ((UITextLayoutDirection)UITextStorageDirectionBackward)


@interface OUIEditableFrame (/*Private*/)
- (NSUInteger)_characterIndexOfPoint:(CGPoint)tapPoint inLine:(CTLineRef)line lineOrigin:(CGPoint)lineOrigin stringRange:(NSRange)stringRange lookingForTappedGlyph:(BOOL)lookingForTappedGlyph outWasBeyondLineBounds:(BOOL *)outWasBeyondLineBounds;
- (OUEFTextPosition *)_closestPositionToPoint:(CGPoint)viewPoint withinRange:(UITextRange *)range lookingForTappedGlyph:(BOOL)lookingForTappedGlyph wasBeyondLineBounds:(BOOL *)outWasBeyondLineBounds;
- (CFRange)_lineRangeForStringRange:(NSRange)queryRange;
- (CGRect)_caretRectForPosition:(OUEFTextPosition *)position affinity:(int)affinity bloomScale:(double)s;
- (void)_setNeedsDisplayForRange:(OUEFTextRange *)range;
- (void)_setSolidCaret:(int)delta;
- (void)_setSelectionToIndex:(NSUInteger)ix;
- (void)_setSelectedTextRange:(OUEFTextRange *)newRange notifyDelegate:(BOOL)shouldNotify;
- (void)_idleTap;
- (void)_activeTap:(UITapGestureRecognizer *)r;
- (void)_inspectTap:(UILongPressGestureRecognizer *)r;
- (void)_drawDecorationsBelowText:(CGContextRef)ctx;
- (void)_drawDecorationsAboveText:(CGContextRef)ctx;
- (void)_didChangeContent;
- (void)_updateLayout:(BOOL)computeDrawnFrame;
- (void)_moveInDirection:(UITextLayoutDirection)direction;
- (UIView *)_topmostView;
- (NSAttributedString *)_attributedTextInRange:(UITextRange *)range;
@end

@implementation OUIEditableFrame

+ (Class)textStorageClass;
{
    return [OATextStorage class];
}

static id do_init(OUIEditableFrame *self)
{
    self.contentMode = UIViewContentModeRedraw;
    self.clearsContextBeforeDrawing = YES;

    /* Need to have *some* fallback font. This more or less matches what UITextView does. */
    if (!self->defaultFont)
        self->defaultFont = CFRetain(OUIGlobalDefaultFont());
    
    self->_autocorrectionType = UITextAutocorrectionTypeDefault;
    self->_autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self->_keyboardType = UIKeyboardTypeDefault;

    self->generation = 1;
    self->markedRange = NSMakeRange(NSNotFound, 0);
    self->layoutSize.width = 0;
    self->layoutSize.height = 0;
    self->flags.textNeedsUpdate = 1;
    self->flags.delegateRespondsToLayoutChanged = 0;
    self->flags.showSelectionThumbs = 1;
    self->flags.showsInspector = 0;
    self->selectionDirtyRect = CGRectNull;
    self->markedTextDirtyRect = CGRectNull;
    
    // Avoid ugly stretchy text
    self.contentMode = UIViewContentModeTopLeft;

    self->_linkTextAttributes = [[OUITextLayout defaultLinkTextAttributes] copy];
    
    self->tapSelectionGranularity = UITextGranularityWord;
    
    self.markedRangeBorderColor = [UIColor colorWithRed:213.0/255.0 green:225.0/255.0 blue:237.0/255.0 alpha:1];
    self->_markedRangeBorderThickness = 1.0;
    self.markedRangeBackgroundColor = [UIColor colorWithRed:236.0/255.0 green:240.0/255.0 blue:248.0/255.0 alpha:1];

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

/* Returns true if CFIndex i is within CFRange r. */
static inline BOOL in_cfrange(CFRange r, CFIndex i)
{
    return (i >= r.location && ( i - r.location ) < r.length);
}

/* Returns true if the two ranges overlap. */
static BOOL cfRangeOverlapsCFRange(CFRange r1, CFRange r2)
{
    if (r1.location < r2.location) {
        return ( r2.location - r1.location ) < r1.length;
    } else if (r1.location > r2.location) {
        return ( r1.location - r2.location ) < r2.length;
    } else {
        /* Same start location */
        return r1.length > 0 && r2.length > 0;
    }
}

static BOOL cfRangeContainedByCFRange(CFRange r1, CFRange r2)
{
    if (r1.location < r2.location)
        return NO;
    
    if (( r1.location + r1.length ) > ( r2.location + r2.length ))
        return NO;
    
    return YES;
}

/* We're assuming that a composed character sequence corresponds to one grapheme cluster.
 * This isn't strictly true (see UNICODE Standard Annex #29 for more than you want to know about grapheme segmentation).
 * Fortunately(?), Apple's composed character sequence methods are documented to actually return grapheme-cluster boundaries rather than composed character sequence boundaries.
 */
#define CFStringGetRangeOfGraphemeClusterAtIndex(s, i) CFStringGetRangeOfComposedCharactersAtIndex(s, i)

/* Returns the square of the distance between two points; useful if you only need it for comparison with other distances */
static inline CGFloat dist_sqr(CGPoint a, CGPoint b)
{
    CGFloat dx = (a.x - b.x);
    CGFloat dy = (a.y - b.y);
    return dx*dx + dy*dy;
}

/* Aligns an extent (one dimension of a rectangle) so that its edges lie on half-integer coordinates, under the 1-dimensional affine transform given by translate and scale. This attempts to keep the rectangle's size roughly the same, unlike CGRectIntegral() (but like -[NSView centerScanRect:]). */
static void alignExtentToPixelCenters(CGFloat translate, CGFloat scale, CGFloat *origin, CGFloat *size)
{
    CGFloat xsize = *size * scale;
    CGFloat xorigin = ( *origin * scale ) + translate;
    CGFloat rxsize = OUIRound(xsize);
    CGFloat adjustment = xsize - rxsize;
    CGFloat rxorigin = xorigin;
    
    if (fabs(adjustment) > 1e-3) {
        *size = ( rxsize / scale );
        rxorigin += adjustment * 0.5;
    }
    
    rxorigin = OUIFloor(rxorigin) + 0.5;
    if (fabs(rxorigin - xorigin) > 1e-3) {
        *origin = ( rxorigin - translate ) / scale;
    }
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
/* Note: Probably a pre-composed character whose base or combining mark must be rendered from a fallback font will result in two runs generated from a single string index */
static CFIndex searchRuns(CFArrayRef runs, CFIndex l, CFIndex h, CFRange queryRange, CTRunRef *foundRun)
{
    while (l < h) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, l);
        CFRange runRange = CTRunGetStringRange(run);
        
        if (cfRangeOverlapsCFRange(runRange, queryRange)) {
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
    if (!frame)
        return;
    CFArrayRef lines = CTFrameGetLines(frame);
    if (!lines)
        return;
    CFIndex lineCount = CFArrayGetCount(lines);
    
    CFIndex firstLine = bsearchLines(lines, 0, lineCount, r.location, NULL);
    if (firstLine < 0 || firstLine >= lineCount)
        return;
    
    /* Walk through all the lines containing a part of the range */
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
            /* The range started before this line */
            left = 0;
            spanRange.location = (NSUInteger)lineRange.location;
            flags |= rectwalker_LeftIsLineWrap;
        } else {
            /* The range starts after this line does --- presumably it starts during this line */
            left = CTLineGetOffsetForStringIndex(line, r.location, NULL);
            spanRange.location = r.location;
            flags |= rectwalker_LeftIsRangeBoundary;
        }
        
        BOOL lastLine;
        
        if (in_range(r, lineRange.location + lineRange.length)) {
            /* The end of this line (or rather, the first location past this line) is still within the range, so this isn't the last line */
            right = lineWidth;
            spanRange.length = ( lineRange.location + lineRange.length ) - spanRange.location;
            if ((lineIndex+1) < lineCount)
                lastLine = NO;
            else
                lastLine = YES;
            flags |= rectwalker_RightIsLineWrap;
        } else {
            /* This is the last line that we'll be enumerating */
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

typedef enum {
    OUIEditableFrameMutationOptionNotifyInputDelegate = (1 << 0),
    OUIEditableFrameMutationOptionNotifyNotEditingTextStorage = (1 << 1), // Set if *we* aren't causing the edit or wanting to notify the text storage of the edit.
    OUIEditableFrameMutationOptionAttributesOnly = (1 << 2),
} OUIEditableFrameMutationOptions;

/* The pattern of housekeeping we need to do around every change to our content. Call beforeMutate() before changing _content, afterMutate() after changing the content, and notifyAfterMutate() some time after that before returning from the method. */
static BOOL beforeMutate(OUIEditableFrame *self, SEL _cmd, OUIEditableFrameMutationOptions options)
{
    NSUInteger wasGeneration = self->generation;
    
    // We generally don't want to show the context menu while the user is typing.
    self.showingEditMenu = NO;
    
    if ((options & OUIEditableFrameMutationOptionAttributesOnly) == 0) {
        // If the inspector is visible and this isn't just an attribute change, hide it immediately (iWork does) instead of trying to keep the typing attributes up to date or whatnot (for one thing, we don't want the insertion pointer going behind the inspector). One risk here is if the inspector has some sort of deferred edit (like editing the font size via the keyboard). We'll assert that we are the first responder (so the there should be no editing text field on the inspector). There's still the possibility of some crazy inspector slice committing changes when it loses first responder, so we might want to have a reentrancy check on these mutation hooks...
        if ([self->_textInspector isVisible]) {
            OBASSERT([self isFirstResponder]);
            [self->_textInspector dismissAnimated:NO];
        }
    }
    
    if (options & OUIEditableFrameMutationOptionNotifyInputDelegate) {
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
    }
    
    [self->immutableContent release];
    self->immutableContent = nil;
    
    if ((options & OUIEditableFrameMutationOptionNotifyNotEditingTextStorage) == 0)
        [self->_content beginEditing];
    
    return YES;
}

static inline void afterMutate(OUIEditableFrame *self, SEL _cmd, OUIEditableFrameMutationOptions options)
{
    [self _didChangeContent];
    
    if ((options & OUIEditableFrameMutationOptionNotifyNotEditingTextStorage) == 0)
        [self->_content endEditing];
}

static void notifyAfterMutate(OUIEditableFrame *self, SEL _cmd, OUIEditableFrameMutationOptions options)
{
    if (options & OUIEditableFrameMutationOptionNotifyInputDelegate) {
        DEBUG_TEXT(@">>> textDidChange (%@)", NSStringFromSelector(_cmd));
        [self->inputDelegate textDidChange:self];
        DEBUG_TEXT(@"<<< textDidChange (%@)", NSStringFromSelector(_cmd));
    }
    if (self->flags.delegateRespondsToContentsChanged) {
        DEBUG_TEXT(@">>> textViewContentsChanged (%@)", NSStringFromSelector(_cmd));
        [self->delegate textViewContentsChanged:self];
        DEBUG_TEXT(@"<<< textViewContentsChanged (%@)", NSStringFromSelector(_cmd));
    }
}

static void afterContentReplaced(OUIEditableFrame *self)
{
    [self unmarkText];
    
    OUEFTextRange *newSelection = [[OUEFTextRange alloc] initWithRange:(NSRange){ [self->_content length], 0 } generation:self->generation];
    [self _setSelectedTextRange:newSelection notifyDelegate:YES];
    [newSelection release];
    
    [self->inputDelegate textDidChange:self];
    
    /* GraphSketcher's TextEditor class doesn't expect us to call it back here. Not sure which way is better. 
     if (flags.delegateRespondsToContentsChanged)
     [delegate textViewContentsChanged:self];
     */
    
    [self setNeedsDisplay];
}

static BOOL _rangeIsInsertionPoint(OUIEditableFrame *self, UITextRange *r)
{
    OBPRECONDITION([r isKindOfClass:[OUEFTextRange class]]);
    
    if (r == self->selection)
        return YES;
    
    return [r isEmpty] && [(OUEFTextRange *)r isEqualToRange:self->selection];
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
    
    OBASSERT(!_content || _content.delegate == self);
    _content.delegate = nil;
    [_content release];
    
    [_backgroundSpanFilter release];
    
    [selection release];
    [_typingAttributes release];
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
    
    [_markedRangeBorderColor release];
    [_markedRangeBackgroundColor release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Conversion between CoreGraphics text and UIKIt coodinates

/*
 We have a bunch of coordinate systems:
 
 The "view" coordinate system is the UIView frame/bounds coordinates. Its Y-coordinate always increases downwards ("flipped") and its units are the same size as the rasterization pixels (device pixels or layer pixels or whatever).
 
 The "text" or "rendering" coordinate system is the interior scaled, (de-)flipped, and possibly translated system for CoreGraphics calls to draw stuff.
 
 The "layout" coordinate system is translated from the rendering coordinate system because CTFramesetter is particular about where it puts its text.
 The layoutOrigin ivar holds the coordinates, in the rendering coordinate system, of the layout coordinate system's origin.
 
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

- (OATextStorage *)textStorage;
{
    if (!_content) {
        Class textStorageClass = [[self class] textStorageClass];
        if (!textStorageClass)
            return nil; // returning Nil disables implicit text storage creation. Some owner will need to give us one.
        
        OBASSERT(OBClassIsSubclassOfClass(textStorageClass, [OATextStorage class]));
        
        _content = [[textStorageClass alloc] init];
        _content.delegate = self;
    }
    
    return _content;
}

- (void)setTextStorage:(OATextStorage *)textStorage;
{
    if (_content == textStorage)
        return;
    
    OUIEditableFrameMutationOptions options = OUIEditableFrameMutationOptionNotifyInputDelegate|OUIEditableFrameMutationOptionNotifyNotEditingTextStorage;
    if (!beforeMutate(self, _cmd, options))
        return;
    
    OBASSERT(!_content || _content.delegate == self);
    _content.delegate = nil;
    [_content release];
    
    OBASSERT(textStorage.delegate == nil);
    _content = [textStorage retain];
    _content.delegate = self;
    
    afterMutate(self, _cmd, options);
    afterContentReplaced(self);
}

@synthesize textColor;
@synthesize tapSelectionGranularity;
@synthesize selectionColor = _insertionPointSelectionColor;
- (void)setSelectionColor:(UIColor *)color;
{
    if (OFISEQUAL(_insertionPointSelectionColor, color))
        return;
    
    [_insertionPointSelectionColor release];
    _insertionPointSelectionColor = [color retain];
    
    
#if 1
    /* iOS doesn't have colorspace support to speak of. Let's just hope that the color components we get are RGBA or something close enough that this works. */
    CGColorRef c = [color CGColor];
    const CGFloat *components = CGColorGetComponents(c);
    int componentCount = CGColorGetNumberOfComponents(c);
    CGFloat newComponents[5];
    CGFloat blend = 0.25 * components[componentCount-1];
    for (int componentIndex = 0; componentIndex < componentCount-1; componentIndex ++) {
        newComponents[componentIndex] = ( blend * components[componentIndex] ) + ( 1 - blend );
    }
    newComponents[componentCount-1] = 1;
    CGColorRef newColor = CGColorCreate(CGColorGetColorSpace(c), newComponents);
    
    [_rangeSelectionColor release];
    _rangeSelectionColor = [[UIColor colorWithCGColor:newColor] retain];
    CFRelease(newColor);
#else
    [_rangeSelectionColor release];
    _rangeSelectionColor = [[_insertionPointSelectionColor colorWithAlphaComponent:0.25] retain];
#endif
    
    if (selection)
        [self setNeedsDisplay];
}

@synthesize markedRangeBorderColor = _markedRangeBorderColor;
@synthesize markedRangeBackgroundColor = _markedRangeBackgroundColor;
@synthesize markedRangeBorderThickness = _markedRangeBorderThickness;

@synthesize textInset = _minimumTextInset;
- (void)setTextInset:(UIEdgeInsets)newInset;
{
    if (UIEdgeInsetsEqualToEdgeInsets(newInset, _minimumTextInset))
        return;
    
    _minimumTextInset = newInset;
    
    // We could avoid this if we are in unlimited layout mode rather than having a specific layout size or an implicit size of our frame. But likely it'll be set once before we have any text anyway.
    [self setNeedsLayout];
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
        textSize.width += _currentTextInset.left + _currentTextInset.right;
        textSize.height += _currentTextInset.top + _currentTextInset.bottom;
        
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

- (BOOL)shouldTryToCenterFirstLine;
{
    return flags.shouldTryToCenterFirstLine;
}

- (void)setShouldTryToCenterFirstLine:(BOOL)newValue;
{
    if (flags.shouldTryToCenterFirstLine == newValue)
        return;

    flags.shouldTryToCenterFirstLine = newValue;
    [self setNeedsLayout];
}

@synthesize firstLineCenterTarget = _firstLineCenterTarget;

- (void)setFirstLineCenterTarget:(CGFloat)newTarget;
{
    if (_firstLineCenterTarget == newTarget)
        return;

    _firstLineCenterTarget = newTarget;
    [self setNeedsLayout];
}

- (BOOL)endEditing;
{
    DEBUG_EDITING(@"-endEditing called");

    if (!flags.isEditing) {
        OBASSERT(![self isFirstResponder]);
        DEBUG_EDITING(@"Wasn't editing");
        return YES;
    }
    
    if ([self isFirstResponder]) {
        // Calling super to avoid our checks that would avoid ending editing ('should' delegate, etc).
        if (![super resignFirstResponder]) {
            DEBUG_EDITING(@"Unable to resign first responder");
            return NO;
        } else {
            DEBUG_EDITING(@"Resigned first responder");
        }
    }

    if ([delegate respondsToSelector:@selector(textViewWillEndEditing:)])
        [delegate textViewWillEndEditing:self];
    
    flags.isEditing = NO;
        
    // If user taps the close button on the simulated keyboard, for example.
    if ([_textInspector isVisible])
        [_textInspector dismissAnimated:YES];
    
    focusRecognizer.enabled = YES;
    for(int i = 0; i < EF_NUM_ACTION_RECOGNIZERS; i++) {
        UIGestureRecognizer *recognizer = actionRecognizers[i];
        if (recognizer)
            recognizer.enabled = NO;
    }
    
    if (startThumb) {
        [startThumb removeFromSuperview];
        startThumb.editor = nil;
        [startThumb release];
        startThumb = nil;
    }
    if (endThumb) {
        [endThumb removeFromSuperview];
        endThumb.editor = nil;
        [endThumb release];
        endThumb = nil;
    }
    if (_loupe) {
        [_loupe removeFromSuperview];
        [_loupe setSubjectView:nil];
        [_loupe release];
        _loupe = nil;
    }
    
    [self setNeedsLayout];
    
    if (selection)
        [self setNeedsDisplay];

    if (delegate && [delegate respondsToSelector:@selector(textViewDidEndEditing:)])
        [delegate textViewDidEndEditing:self];
    
    return YES;
}

- (void)setDelegate:(id <OUIEditableFrameDelegate>)newDelegate
{
    delegate = newDelegate;
    
    // Cache some responds-to information.
    // Don't bother caching everything, just the methods we call frequently during use.
    
    flags.delegateRespondsToLayoutChanged = [newDelegate respondsToSelector:@selector(textViewLayoutChanged:)];
    flags.delegateRespondsToContentsChanged = [newDelegate respondsToSelector:@selector(textViewContentsChanged:)];
    flags.delegateRespondsToCanShowContextMenu = [newDelegate respondsToSelector:@selector(textViewCanShowContextMenu:)];
    flags.delegateRespondsToShouldInsertText = [newDelegate respondsToSelector:@selector(textView:shouldInsertText:)];
    flags.delegateRespondsToShouldDeleteBackwardsFromIndex = [newDelegate respondsToSelector:@selector(textView:shouldDeleteBackwardsFromIndex:)];
    flags.delegateRespondsToSelectionChanged = [newDelegate respondsToSelector:@selector(textViewSelectionChanged:)];
}

@synthesize delegate;

@synthesize backgroundSpanFilter = _backgroundSpanFilter;
- (void)setBackgroundSpanFilter:(OUITextLayoutSpanBackgroundFilter)backgroundSpanFilter;
{
    if (_backgroundSpanFilter == backgroundSpanFilter)
        return;
    [_backgroundSpanFilter release];
    _backgroundSpanFilter = [backgroundSpanFilter copy];
    
    [self setNeedsDisplay];
}

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

- (BOOL)showingEditMenu;
{
    return flags.showingEditMenu != 0;
}

- (void)setShowingEditMenu:(BOOL)newValue;
{
    if (flags.showingEditMenu == newValue)
        return;
    if (newValue) {
        DEBUG_TEXT(@"Showing context menu (%@)", NSStringFromSelector(_cmd));
    } else {
        DEBUG_TEXT(@"Dismissing context menu (%@)", NSStringFromSelector(_cmd));
    }

    flags.showingEditMenu = newValue;
    [self setNeedsLayout];
}
    
- (void)setupCustomMenuItemsForMenuController:(UIMenuController *)menuController;
{
    UIMenuItem *items[2];
        
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
        [[self _topmostView] addSubview:_loupe];
    }
    
    [self _setSolidCaret:1];
}

- (void)thumbMoved:(OUITextThumb *)thumb targetPosition:(CGPoint)pt;
{
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
    
    CGRect loupeCaret = [self caretRectForPosition:pp];
    double lscale = 22.0 / MAX(loupeCaret.size.height, 2.0);
    CGPoint touch;
    touch.x = loupeCaret.origin.x;
    touch.y = loupeCaret.origin.y + 0.5 * loupeCaret.size.height;
    _loupe.touchPoint = touch;
    _loupe.scale = lscale;
    _loupe.mode = OUILoupeOverlayRectangle;
    
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

- (NSDictionary *)attributesInRange:(UITextRange *)r;
{
    OBPRECONDITION([r isKindOfClass:[OUEFTextRange class]]);
    
    // Inspectors want the attributes of the beginning of the first range of selected text.
    // I'm passing in the whole range right now since it isn't clear yet how we should behave in the face of embedded bi-di text; should we always do the first position by character order, or the first character by visual rendering order. Doing the easy thing for now.
    
    if (_rangeIsInsertionPoint(self, r))
        return [self typingAttributes];

    NSUInteger pos = ((OUEFTextPosition *)(r.start)).index;
    return [_content attributesAtIndex:pos effectiveRange:NULL];
}

- (id <NSObject>)attribute:(NSString *)attr inRange:(UITextRange *)r;
{
    if (_rangeIsInsertionPoint(self, r))
        return [[self typingAttributes] objectForKey:attr];
    
    NSUInteger pos = ((OUEFTextPosition *)(r.start)).index;
    return [_content attribute:attr atIndex:pos effectiveRange:NULL];
}

- (void)setValue:(id)value forAttribute:(NSString *)attr inRange:(UITextRange *)r;
{
    OBPRECONDITION([r isKindOfClass:[OUEFTextRange class]]);
    
    DEBUG_TEXT(@"Setting %@ to %@ in %@", attr, value, r);
    
    if (_rangeIsInsertionPoint(self, r)) {
        NSMutableDictionary *attributes = [self.typingAttributes mutableCopy];
        if (value)
            [attributes setObject:value forKey:attr];
        else
            [attributes removeObjectForKey:value];
        self.typingAttributes = attributes;
        [attributes release];
        return;
    }

    NSUInteger st = ((OUEFTextPosition *)(r.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(r.end)).index;
    
    if (en < st) {
        OBASSERT_NOT_REACHED("Bad selection range");
        return;
    }
    
    [self _setSolidCaret:0];
    
    OUIEditableFrameMutationOptions options = OUIEditableFrameMutationOptionNotifyInputDelegate|OUIEditableFrameMutationOptionAttributesOnly;
    
    if (!beforeMutate(self, _cmd, options))
        return;
    
    NSUInteger contentLength = [_content length];
    if (en > contentLength) {
        OBASSERT_NOT_REACHED("Bad range specified");
        en = contentLength; // but let's not crash
    }
    if (st > en)
        st = en;
    NSRange cr = [[_content string] rangeOfComposedCharacterSequencesForRange:(NSRange){ st, en - st }];
    if (cr.location + cr.length > contentLength) {
        OBASSERT_NOT_REACHED("Bad range specified");
        cr.length = ( contentLength - cr.location ); // but let's not crash
    }
    if (value)
        [_content addAttribute:attr value:value range:cr];
    else
        [_content removeAttribute:attr range:cr];
    afterMutate(self, _cmd, options);
    notifyAfterMutate(self, _cmd, options);
    
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
    
    /* The overall order of drawing is:
       
       The view background (possibly none/transparent)
       
       In -_drawDecorationsBelowText:
          Text background
          Text range-selection highlight
          Marked text range highlight background

       In OUITextLayoutDrawFrame():
          The text proper, drawn by CoreText
          Any text with an offset baseline, drawn by us
          Any attachment cells

       In -_drawDecorationsAboveText:
          Marked text range highlight border
          The selection caret (if empty selection) or begin/end carets (if range selection)
    */
          
    
    UIColor *backgroundColor = self.backgroundColor;
    if (backgroundColor) {
        [backgroundColor setFill];
        CGContextFillRect(ctx, [self convertRectFromRenderingSpace:rect]);
    }
    
    [self _drawDecorationsBelowText:ctx];
    OUITextLayoutDrawFrame(ctx, drawnFrame, self.bounds, layoutOrigin);
    [self _drawDecorationsAboveText:ctx];
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

    BOOL amFirstResponder = [self isFirstResponder];
    
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    
    /* Show or hide the selection thumbs */
    if (selection && ![selection isEmpty] && flags.showSelectionThumbs && amFirstResponder && drawnFrame) {
        /* We don't want to animate thumb appearance/disappearance --- it's distracting */
        BOOL wereAnimationsEnabled = [UIView areAnimationsEnabled];
        [UIView setAnimationsEnabled:NO];
        
        CGRect caretRect;
        
        if (!startThumb) {
            startThumb = [[OUITextThumb alloc] init];
            startThumb.isEndThumb = NO;
            startThumb.editor = self;
            [[self _topmostView] addSubview:startThumb];
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
            endThumb.editor = self;
            [[self _topmostView] addSubview:endThumb];
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
        
        [UIView setAnimationsEnabled:wereAnimationsEnabled];
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
    if (drawnFrame && selection && [selection isEmpty] && !flags.solidCaret && amFirstResponder) {
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
    
    /* Suppress the selection context menu if there is no selection or the loupe or text inspector are visible. */
    BOOL suppressContextMenu = selection == nil ||
        (_loupe != nil && _loupe.mode != OUILoupeOverlayNone) ||
        (_textInspector != nil && _textInspector.isVisible) ||
        !drawnFrame ||
        (flags.delegateRespondsToCanShowContextMenu && ![delegate textViewCanShowContextMenu:self]);
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
        CGRect selectionRectangle = [self boundsOfRange:selection];
        
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
    //    viewSize.width = OUICeil(OUICeil(size.width) * scale);
    //    viewSize.height = OUICeil(OUICeil(size.height) * scale);
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
        self.selectionColor = [UIColor colorWithHue:210.0/360.0 saturation:1 brightness:0.90 alpha:0.75];
    
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

    if (_cursorOverlay != nil || _selectionContextMenu != nil || startThumb != nil || endThumb != nil)
        [self setNeedsLayout]; // Make sure we reposition our overlay views (even if our frame didn't change relative to our superview, it may have changed relative to their superview)
    
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

//- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;
//{
//    // We want our thumbs to receive touches even when they extend a bit outside our area.
//    
//    return [startThumb pointInside:point withEvent:event] || [endThumb pointInside:point withEvent:event] || [super pointInside:point withEvent:event];
//}

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
        
        //NSLog(@"start dist: %f, end dist: %f", dStart, dEnd);
        
        if (dStart < dEnd)
            return hitStartThumb;
        else
            return hitEndThumb;
    } else if (hitStartThumb)
        return hitStartThumb;
    else if (hitEndThumb)
        return hitEndThumb;
    
    // We also want our autocomplete view to receive touches even when it's outside our view
    for (UIView *subview in [self subviews]) {
        if (subview == startThumb || subview == endThumb)
            continue; // We just tested these

        CGPoint pointInSubview = [self convertPoint:point toView:subview];
        UIView *hitView = [subview hitTest:pointInSubview withEvent:event];
        if (hitView) {
#ifdef DEBUG_kc
            NSLog(@"-[%@ %@]: point=%@, event=%@, returning %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), NSStringFromCGPoint(point), event, [hitView shortDescription]);
#endif
            return hitView;
        }
    }

    // But by default, use our superclass's behavior
    return [super hitTest:point withEvent:event];
}

//- (void)_thumbDrag:(UIPanGestureRecognizer *)gestureRecognizer;
//{
//    UIGestureRecognizerState st = gestureRecognizer.state;
//    CGPoint delta = [gestureRecognizer translationInView:self];
//    
//    // UIPanGestureRecognizer seems to be kind of sloppy about its initial offset. Not sure if this'll be a problem in practice but it's noticeable in the simulator. Might need to do our own translation calculations.
//    // NSLog(@"pan: %@, delta=%@", gestureRecognizer, NSStringFromCGPoint(delta));
//    
//    if (st == UIGestureRecognizerStateBegan) {
//        /* The point below is the center of the caret rectangle we draw. We want to use that rather than the baseline point or the thumb point to allow the maximum finger slop before the text view selects a different line. */
//        touchdownPoint = [self convertPoint:(CGPoint){0, - ascent/2} toView:self];
//        [self thumbBegan:self];
//    }
//    
//    /* UIPanGestureRecognizer will return a delta of { -NAN, -NAN } sometimes (if it would be outside the parent view's bounds maybe?). */
//    if ((isfinite(delta.x) && isfinite(delta.y)) &&
//        (st != UIGestureRecognizerStateBegan || !(delta.x == 0 && delta.y == 0))) {
//        [self thumbMoved:self targetPosition:(CGPoint){ touchdownPoint.x + delta.x, touchdownPoint.y + delta.y }];
//    }
//    
//    if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled) {
//        [self thumbEnded:self normally:(st == UIGestureRecognizerStateEnded? YES:NO)];
//        touchdownPoint = (CGPoint){ NAN, NAN };
//    }
//}


#pragma mark -
#pragma mark UIResponder subclass

- (BOOL)becomeFirstResponder
{
    DEBUG_EDITING(@">> become first responder");
    BOOL didBecomeFirstResponder = [super becomeFirstResponder];
    
    if (didBecomeFirstResponder && !actionRecognizers[0]) {
        unsigned int recognizerIndex = 0;
        UITapGestureRecognizer *singleTap = [[OUIDirectTapGestureRecognizer alloc] initWithTarget:self action:@selector(_activeTap:)];
        actionRecognizers[recognizerIndex++] = singleTap;
        [self addGestureRecognizer:singleTap];
        // singleTap.maximumSingleTapDuration = 1.5;
        // singleTap.maximumIntervalBetweenSuccessiveTaps = 5./16.;
        
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_activeTap:)];
        doubleTap.numberOfTapsRequired = 2;
        actionRecognizers[recognizerIndex++] = doubleTap;
        [self addGestureRecognizer:doubleTap];
        
        UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_activeTap:)];
        tripleTap.numberOfTapsRequired = 3;
        actionRecognizers[recognizerIndex++] = tripleTap;
        [self addGestureRecognizer:tripleTap];
        
        [doubleTap requireGestureRecognizerToFail:tripleTap];
        
        UILongPressGestureRecognizer *inspectTap = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_inspectTap:)];
        actionRecognizers[recognizerIndex++] = inspectTap;
        [self addGestureRecognizer:inspectTap];
        
//        UIPanGestureRecognizer *thumbDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_thumbDrag:)];
//        thumbDrag.minimumNumberOfTouches = 1;
//        thumbDrag.maximumNumberOfTouches = 1;
//        actionRecognizers[recognizerIndex++] = thumbDrag;
//        [self addGestureRecognizer:thumbDrag];
//        [thumbDrag release];
        
        assert(recognizerIndex == EF_NUM_ACTION_RECOGNIZERS);
    }
    
    if (didBecomeFirstResponder) {
        focusRecognizer.enabled = NO;
        for(int i = 0; i < EF_NUM_ACTION_RECOGNIZERS; i++)
            actionRecognizers[i].enabled = YES;
    }
    
    [self setNeedsLayout];
    
    if (selection)
        [self setNeedsDisplay];
    
    flags.isEditing = didBecomeFirstResponder;
    
    DEBUG_EDITING(@"<< become first responder");
    return didBecomeFirstResponder;
}

- (BOOL)resignFirstResponder;
{
    DEBUG_EDITING(@">> resign first responder");

    if (![self isFirstResponder]) {
        // OK...
        DEBUG_EDITING(@"<< not first responder");
        return YES;
    }
    
    // If our text inspector is visible and we are losing first responder, something in it must be gaining it. Don't end editing for that (which would lose the selection that the text inspector wants to edit).
    if ([_textInspector isVisible]) {
        // OK, just resign first responder.
        DEBUG_EDITING(@"<< just resign first responder, not ending editing");
        return [super resignFirstResponder];
    }
    
    if ([delegate respondsToSelector:@selector(textViewShouldEndEditing:)] && ![delegate textViewShouldEndEditing:self]) {
        DEBUG_EDITING(@"<< delegate declined");
        return NO;
    }

    [self endEditing];
    
    DEBUG_EDITING(@"<< resign first responder");
    return YES;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)willMoveToSuperview:(UIView *)newSuperview;
{
    // If we're removed from our superview, -layoutSubviews is not called. This is OK for our actual subviews (like our thumbs) since they're removed along with us, but not for the other view layout we normally do in that method.
    
    if (_cursorOverlay && !(_cursorOverlay.hidden)) {
        [_cursorOverlay stopBlinking];
        _cursorOverlay.hidden = YES;
    }
    
    if (_selectionContextMenu) {
        DEBUG_TEXT(@"Hiding context menu (in -willMoveToSuperview:)");
        [_selectionContextMenu setMenuVisible:NO animated:NO];
        [_selectionContextMenu autorelease];
        _selectionContextMenu = nil;
    }
    
    [_loupe setMode:OUILoupeOverlayNone];
    
    [super willMoveToSuperview:newSuperview];
}

#pragma mark UIResponderStandardEditActions

- (void)copy:(id)sender;
{
    if (selection == nil)
        return;

    UIPasteboard *generalPasteboard = [UIPasteboard generalPasteboard];
    NSString *txt = [self textInRange:selection];
    generalPasteboard.string = txt;

    if ([delegate respondsToSelector:@selector(writeAttributedStringFromTextRange:toPasteboard:forTextView:)])
        [delegate writeAttributedStringFromTextRange:selection toPasteboard:generalPasteboard forTextView:self];
}

- (void)cut:(id)sender;
{
    if (selection) {
        [self copy:sender];
        [self delete:sender];
    }
}

- (void)delete:(id)sender;
{
    if (selection && ![selection isEmpty]) {
        [inputDelegate textWillChange:self];
        [inputDelegate selectionWillChange:self];
        [self replaceRange:selection withText:@""];
        [inputDelegate selectionDidChange:self];
        [inputDelegate textDidChange:self];
    }
}

- (void)paste:(id)sender;
{
    NSAttributedString *pastedAttributedString = nil;
    UIPasteboard *generalPasteboard = [UIPasteboard generalPasteboard];
    if ([delegate respondsToSelector:@selector(readAttributedStringFromPasteboard:forTextView:)])
        pastedAttributedString = [delegate readAttributedStringFromPasteboard:generalPasteboard forTextView:self];

    NSString *scrap = generalPasteboard.string;
    if (pastedAttributedString != nil || scrap != nil) {
        UITextRange *seln = self.selectedTextRange;
        if (!seln) {
            seln = [[[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self endOfDocument] end:(OUEFTextPosition *)[self endOfDocument]] autorelease];
        }
        [inputDelegate textWillChange:self];
        [inputDelegate selectionWillChange:self];
        if (pastedAttributedString != nil) {
            OUIEditableFrameMutationOptions options = 0;
            if (!beforeMutate(self, _cmd, options))
                return;

            NSUInteger startIndex = ((OUEFTextPosition *)(seln.start)).index;
            NSUInteger endIndex = ((OUEFTextPosition *)(seln.end)).index;
            [_content replaceCharactersInRange:(NSRange){startIndex, endIndex - startIndex} withAttributedString:pastedAttributedString];

            afterMutate(self, _cmd, options);
            [self _setSelectionToIndex:startIndex + [pastedAttributedString length]];
            notifyAfterMutate(self, _cmd, options);

            [self setNeedsDisplay];
        } else {
            [self replaceRange:seln withText:scrap];
        }
        [inputDelegate selectionDidChange:self];
        [inputDelegate textDidChange:self];
    }
}

- (void)select:(id)sender;
{
    UITextRange *forRange = [[self tokenizer] rangeEnclosingPosition:[selection start] withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
    UITextRange *backRange = [[self tokenizer] rangeEnclosingPosition:[selection end] withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];

    if (forRange && backRange) {
        OUEFTextRange *newRange = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)backRange.start end:(OUEFTextPosition *)forRange.end];
        [self setSelectedTextRange:newRange];
        [newRange release];
    } else if (forRange) {
        [self setSelectedTextRange:forRange];
    } else if (backRange) {
        [self setSelectedTextRange:backRange];
    }
}

- (void)selectAll:(id)sender;
{
    OUEFTextRange *all = [[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)[self beginningOfDocument] end:(OUEFTextPosition *)[self endOfDocument]];
    [self setSelectedTextRange:all];
    [all release];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(inspectSelectedText:) && !flags.showsInspector)
        return NO;

    if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(delete:) || action == @selector(inspectSelectedText:)) {
        return selection && ![selection isEmpty];
    }
    
    if (action == @selector(paste:)) {
        UIPasteboard *generalPasteboard = [UIPasteboard generalPasteboard];
        if ([generalPasteboard containsPasteboardTypes:UIPasteboardTypeListString])
            return YES;
        if ([delegate respondsToSelector:@selector(textView:canPasteFromPasteboard:)])
            return [delegate textView:self canPasteFromPasteboard:generalPasteboard];
        return NO;
    }
    
    if (action == @selector(select:)) {
        if ([selection.start isEqual:selection.end])
            return YES;
        return NO;
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

- (void)_didChangeContent
{
    [immutableContent release];
    immutableContent = nil;
    
    generation ++;
    flags.textNeedsUpdate = YES;
    
    /* Ensure that each paragraph has no more than one paragraph style */
    // OBFinishPortingLater("Move this to -[OATextStorage ensureAttributesAreFixedInRange:] or the like?");
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
    if (_typingAttributes) {
        OBASSERT([_typingAttributes objectForKey:(id)kCTRunDelegateAttributeName] == nil); // We should have a pre-transformed attributed string.
        return _typingAttributes;
    }
    
    NSUInteger contentLength = [_content length];
    if (contentLength == 0)
        return nil;

    NSUInteger insertAt;
    if (!selection) {
        insertAt = contentLength;
    } else {
        insertAt = ((OUEFTextPosition *)(self.selectedTextRange.end)).index;
        if (insertAt > contentLength)
            insertAt = contentLength;
    }
    
    NSDictionary *attributes = [_content attributesAtIndex:(insertAt > 0 ? insertAt-1 : 0) effectiveRange:NULL];
    
    if ([attributes objectForKey:OAAttachmentAttributeName]) {
        NSMutableDictionary *trimmedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        [trimmedAttributes removeObjectForKey:OAAttachmentAttributeName];
        return trimmedAttributes;
    }
    OBASSERT([attributes objectForKey:(id)kCTRunDelegateAttributeName] == nil); // We should have a pre-transformed attributed string.
    
    return attributes;
}

- (void)setTypingAttributes:(NSDictionary *)attributes;
{
    if (OFISEQUAL(_typingAttributes, attributes))
        return;
    
    
    if ([attributes objectForKey:OAAttachmentAttributeName]) {
        NSMutableDictionary *trimmedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        [trimmedAttributes removeObjectForKey:OAAttachmentAttributeName];
        attributes = trimmedAttributes;
    }
    OBASSERT([attributes objectForKey:(id)kCTRunDelegateAttributeName] == nil); // We should have a pre-transformed attributed string.

    [_typingAttributes release];
    _typingAttributes = [attributes copy];
}

- (NSAttributedString *)attributedText;
{
    // If we have an immutable copy that doesn't have attribute transforms applied, return a substring from it (which could potentially just reference the original immutable copy).
    if (immutableContent && !flags.immutableContentHasAttributeTransforms) {
        OBASSERT([_content length] + 1 == [immutableContent length]); // immutableContent has an extra newline
        NSUInteger len = [immutableContent length];
        return [immutableContent attributedSubstringFromRange:(NSRange){0, len-1}];
    }

    // Return an immutable snapshot of our current contents.
    NSUInteger len = [_content length];
    return [_content attributedSubstringFromRange:(NSRange){0, len}];
}

- (NSDictionary *)_allDefaultAttributes;
{
    NSMutableDictionary *allDefaultAttributes = [NSMutableDictionary dictionary];
    if (defaultParagraphStyle != nil)
        [allDefaultAttributes setObject:(id)defaultParagraphStyle forKey:(id)kCTParagraphStyleAttributeName];
    if (defaultFont != nil)
        [allDefaultAttributes setObject:(id)defaultFont forKey:(id)kCTFontAttributeName];
    if (textColor != nil)
        [allDefaultAttributes setObject:(id)[textColor CGColor] forKey:(id)kCTForegroundColorAttributeName];
    return allDefaultAttributes;
}

// Called by both -setAttributedText: and -setTextStorage:
- (void)setAttributedText:(NSAttributedString *)newContent
{
    [self textStorage]; // Make sure our text storage has been created.

    OUIEditableFrameMutationOptions options = OUIEditableFrameMutationOptionNotifyInputDelegate;
    if (!beforeMutate(self, _cmd, options))
        return;

    [_content replaceCharactersInRange:(NSRange){0, [_content length]} withAttributedString:newContent];

    afterMutate(self, _cmd, options);
    afterContentReplaced(self);
}

#pragma mark -
#pragma mark UIKeyInput

- (BOOL)hasText;
{
    return ([_content length] > 0 );
}

// These show up, at least when simulating a hardward keyboard in the simulator. They at least match NSEvent.h
enum {
    NSUpArrowFunctionKey = 0xF700,
    NSDownArrowFunctionKey = 0xF701,
    NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703,
};

/* NB: This should only be called by the iOS input system.
 The reason is that we need to avoid calling [inputDelegate textWillChange:] etc for changes incurred by the iOS input system, and OUIEditableFrame's -insertText: method assumes that it is being called by the OS and should not notify the delegate.
 The only place this is mentioned in the docs is an aside in the "Text, Web, and Editing Programming Guide": "When changes occur in the text view due to external reasons-that is, they aren't caused by calls from the text input system-the UITextInput object should send textWillChange:, textDidChange:, selectionWillChange:, and selectionDidChange: messages to the input delegate".
 The implication of the above is that we *shouldn't* call the delegate methods for changes caused by calls from the text input system, and it turns out that if we do, a variety of small bugs appear in autocorrect and ideographic input.
 (We do call some other UITextInput mutators from non-UITextInput methods, an in those cases we bracket the calls with calls to the inputDelegate.)
 */
- (void)insertText:(NSString *)text;
{
    OBPRECONDITION(_content);

    if (flags.delegateRespondsToShouldInsertText && ![delegate textView:self shouldInsertText:text])
        return;

    [self _setSolidCaret:0];
    
    // iPad simulator's Japanese input method likes to try to insert nil. I don't know why.
    if (!text)
        return;
    
    NSUInteger contentLength = [_content length];
    
    NSRange replaceRange;

    if (markedRange.location != NSNotFound) {
        // Replace marked text.
        replaceRange = markedRange;
    } else if (selection) {
        replaceRange = selection.range;
    } else {
        replaceRange = NSMakeRange(contentLength, 0);
    }
    
    if (NSMaxRange(replaceRange) > contentLength) {
        OBASSERT_NOT_REACHED("Bad selection range");
        return;
    }
    
    DEBUG_TEXT(@"Inserting \"%@\" in range {%"PRIuNS", %"PRIuNS"} (content length %"PRIuNS")", text, replaceRange.location, replaceRange.length, [_content length]);
    
#if 0
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
#endif
    
    [self unmarkText];

    OUIEditableFrameMutationOptions options = 0;
    if (!beforeMutate(self, _cmd, options))
        return;
    
    NSAttributedString *insertThis = [[NSAttributedString alloc] initWithString:text attributes:[self typingAttributes]];
    [_content replaceCharactersInRange:replaceRange withAttributedString:insertThis];
    [insertThis release];
    afterMutate(self, _cmd, options);
    [self _setSelectionToIndex: ( replaceRange.location + [text length] )];
    notifyAfterMutate(self, _cmd, options);
    
    [self setNeedsDisplay];
}

- (void)deleteBackward;
{
    OBPRECONDITION(_content);
    
    [self _setSolidCaret:0];

    NSRange deleteRange;
    if (markedRange.location != NSNotFound)
        deleteRange = markedRange;
    else if (selection)
        deleteRange = selection.range;
    else {
        OBASSERT_NOT_REACHED("-deleteBackward with no selection");
        return;
    }
    
    if (NSMaxRange(deleteRange) > [_content length]) {
        OBASSERT_NOT_REACHED("Bad deletion range in -deleteBackward");
        return;
    }
    
    if (deleteRange.length == 0 && flags.delegateRespondsToShouldDeleteBackwardsFromIndex && ![delegate textView:self shouldDeleteBackwardsFromIndex:deleteRange.location])
        return; // Our delegate has handled (or refused) this delete action

    if (deleteRange.location == 0 && deleteRange.length == 0)
        return; // Insertion point at the beginning, there isn't anything before this to delete

    [self unmarkText];
    
    OUIEditableFrameMutationOptions options = 0;
    if (!beforeMutate(self, _cmd, options))
        return;
    
    if (deleteRange.length)
        deleteRange = [[_content string] rangeOfComposedCharacterSequencesForRange:deleteRange];
    else
        deleteRange = [[_content string] rangeOfComposedCharacterSequenceAtIndex:deleteRange.location - 1];
    OBASSERT(deleteRange.length > 0);
    
    [_content deleteCharactersInRange:deleteRange];
    afterMutate(self, _cmd, options);
    [self _setSelectionToIndex:deleteRange.location];
    notifyAfterMutate(self, _cmd, options);
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UITextInputTraits protocol

@synthesize autocapitalizationType = _autocapitalizationType;
@synthesize autocorrectionType = _autocorrectionType;
@synthesize keyboardType = _keyboardType;

- (UIKeyboardAppearance)keyboardAppearance;
{
    return UIKeyboardAppearanceDefault;
}

- (UIReturnKeyType)returnKeyType;
{
    return UIReturnKeyDefault;
} 

- (BOOL)enablesReturnKeyAutomatically;
{
    return NO;
}

@synthesize autoCorrectDoubleSpaceToPeriodAtSentenceEnd = _autoCorrectDoubleSpaceToPeriodAtSentenceEnd;

- (BOOL)isSecureTextEntry
{
    return NO;
}

#pragma mark -
#pragma mark UITextInput protocol

- (NSString *)textInRange:(UITextRange *)range;
{
    // DEBUG_TEXT(@"-- textInRange:%@", [range description]);

    if (!range || ![range isKindOfClass:[OUEFTextRange class]])
        return nil;
        
    NSUInteger st = ((OUEFTextPosition *)(range.start)).index;
    NSUInteger en = ((OUEFTextPosition *)(range.end)).index;
    
    NSString *result;
    if (en <= st)
        result = @"";
    else
        result = [[_content string] substringWithRange:(NSRange){ st, en - st }];
    
    DEBUG_TEXT(@"textInRange:%@ -> %@", [range description], ([result length] > 10)? [NSString stringWithFormat:@"%u chars", (unsigned)[result length]] : [NSString stringWithFormat:@"\"%@\"", result]);
    
    return result;
}

/*
 NB: This should only be called from other methods that are also part of the UITextInput / UIKeyInput protocols, and not called by user code. See the comment before -insertText: for some more discussion.
 Right now we do call it from other places as well (eg menu actions) and those places are responsible for emitting the inputDelegate messages.
 */
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
    
    OUIEditableFrameMutationOptions options = 0;
    if (!beforeMutate(self, _cmd, options))
        return;
    
    NSUInteger contentLength = [_content length];
    NSUInteger endex;
    if (st > contentLength) {
        OBASSERT_NOT_REACHED("Bad selection range");
        st = contentLength;
    }
    NSDictionary *attributes;
    if (st == en)
        attributes = [self typingAttributes];
    else
        attributes = [_content attributesAtIndex:st effectiveRange:NULL];
    NSAttributedString *newtext = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    if (en > st) {
        NSRange cr = [[_content string] rangeOfComposedCharacterSequencesForRange:(NSRange){ st, en - st }];
        if (cr.location + cr.length > contentLength) {
            OBASSERT_NOT_REACHED("Bad selection range");
            cr.length = ( contentLength - cr.location );
        }
        [_content replaceCharactersInRange:cr withAttributedString:newtext];
        endex = cr.location + [newtext length];
    } else {
        [_content insertAttributedString:newtext atIndex:st];
        endex = st + [newtext length];
    }
    [newtext release];
    afterMutate(self, _cmd, options);
    [self _setSelectionToIndex:endex];
    notifyAfterMutate(self, _cmd, options);
    
    [self setNeedsDisplay];
}

- (UITextRange *)selectedTextRange
{
    DEBUG_TEXT(@"-- selectedTextRange --> %@", selection);
    
    return selection;
}

- (void)setSelectedTextRange:(UITextRange *)newRange;
{
    DEBUG_TEXT(@"-- setSelectedTextRange:%@", newRange);
    OBASSERT(newRange == nil || [newRange isKindOfClass:[OUEFTextRange class]]);

    /* We assume that any selection change that's official enough come through this method should count as caret-solidifying activity. Probably should look for corner cases here. */
    [self _setSolidCaret:0];
    
    // We *cannot* clear marked text here. See <bug:///72439> (Unable to change insertion point within marked text) where the Japanese input manager lets the user drag the insertion point around to get different autocorrections. The insertion point is clamped to the marked range in this case.
    // [self unmarkText];
    
    [self _setSelectedTextRange:(OUEFTextRange *)newRange notifyDelegate:YES];
    self.showingEditMenu = newRange != nil && ![newRange isEmpty];
}


/* If text can be selected, it can be marked. Marked text represents provisionally
 * inserted text that has yet to be confirmed by the user.  It requires unique visual
 * treatment in its display.  If there is any marked text, the selection, whether a
 * caret or an extended range, always resides witihin.
 *
 * Setting marked text either replaces the existing marked text or, if none is present,
 * inserts it from the current selection.
 */

- (UITextRange *)markedTextRange;                       // Nil if no marked text.
{
    DEBUG_TEXT(@"-- markedTextRange");

    if (!markedRange.length)
        return nil;
    
    DEBUG_TEXT(@"   (marked text %"PRIuNS"+%"PRIuNS" is \"%@\")", markedRange.location, markedRange.length, [[_content string] substringWithRange:markedRange]);
    
    return [[[OUEFTextRange alloc] initWithRange:markedRange generation:generation] autorelease];
}

@synthesize markedTextStyle;

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange;  // selectedRange is a range within the markedText
{
    if (!CGRectIsNull(markedTextDirtyRect)) {
        [self setNeedsDisplayInRect:markedTextDirtyRect];
        markedTextDirtyRect = CGRectNull;
    }
    
    NSUInteger contentLength = [_content length];

    NSRange replaceRange;
    if (markedRange.location != NSNotFound) {
        // Have some marked text; replace it.
        replaceRange = markedRange;
    } else if (selection) {
        // No marked text, but there is selected text. Replace that and update the marked range.
        replaceRange = selection.range;
    } else {
        // Append to the end of the text, then?
        OBASSERT_NOT_REACHED("Ever hit?");
        replaceRange = NSMakeRange(contentLength, 0);
    }
    
    DEBUG_TEXT(@"Marked text: \"%@\" seln %"PRIuNS"+%"PRIuNS" replacing %"PRIuNS"+%"PRIuNS"",
               markedText,
               selectedRange.location, selectedRange.length,
               replaceRange.location, replaceRange.length);
    DEBUG_TEXT(@"  (Marked style: %@)", [markedTextStyle description]);

    [self _setSolidCaret:0];
        
    OUIEditableFrameMutationOptions options = 0;
    if (!beforeMutate(self, _cmd, options))
        return;
    
    OBASSERT(NSMaxRange(replaceRange) <= contentLength);

    if (!markedText)
        markedText = @""; // We get nil from the Japanese input manager on delete sometimes
    
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
    
    afterMutate(self, _cmd, options);
    
    [self willChangeValueForKey:@"markedTextRange"];
    OUEFTextRange *newSelection = [[OUEFTextRange alloc] initWithRange:newSeln generation:generation];
    [self _setSelectedTextRange:newSelection notifyDelegate:NO];
    [newSelection release];
    markedRange = (NSRange){ replaceRange.location, markedTextLength };
    [self didChangeValueForKey:@"markedTextRange"];
    
    notifyAfterMutate(self, _cmd, options);
        
    [self setNeedsDisplay];
}

- (void)unmarkText;
{
    if (!markedRange.length)
        return;

    DEBUG_TEXT(@"Unmarking text  (dirty rect was %@)", NSStringFromCGRect(markedTextDirtyRect));
    [self setNeedsDisplayInRect:markedTextDirtyRect];
    
    [self willChangeValueForKey:@"markedTextRange"];
    markedRange = NSMakeRange(NSNotFound, 0);
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
    OUEFTextPosition *p = [[[OUEFTextPosition alloc] initWithIndex:contentLength] autorelease];
    p.generation = generation;
    return p;
}

/* Methods for creating ranges and positions. */
- (UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition;
{
    /* UIKit will sometimes call us with a nil position if we returned a nil position from positionFromPosition:toBoundary:inDirection: (but only for paragraph motion, oddly, see #68542 and RADAR 8857073). Try to fail softly in that case. */
    if (!fromPosition || !toPosition) {
        // Actually, returning nil causes <bug:///71021> (option-up arrow while at the beginning of a field being edited blanks the document view. typing after that can crash)
        UITextPosition *st = [self beginningOfDocument];
        fromPosition = st;
        toPosition = st;
    }
    
    return [[[OUEFTextRange alloc] initWithStart:(OUEFTextPosition *)fromPosition
                                             end:(OUEFTextPosition *)toPosition] autorelease];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset;
{
    return [self positionFromPosition:position inDirection:OUITextLayoutDirectionForward offset:offset];
}

/* True if both or neither of its arguments is true */
#define XNOR(a, b) ((a)? (b) : !(b))

static NSUInteger _leftmostStringIndex(CTRunStatus flags, CFRange sr)
{
#if 0
    if (flags & kCTRunStatusNonMonotonic) {
        /* TODO: Complicated case */
    }
#endif
    if (flags & kCTRunStatusRightToLeft)
        return ( sr.location + sr.length - 1 );
    else
        return sr.location;
}

static NSUInteger _rightmostStringIndex(CTRunStatus flags, CFRange sr)
{
#if 0
    if (flags & kCTRunStatusNonMonotonic) {
        /* TODO: Complicated case */
    }
#endif
    if (flags & kCTRunStatusRightToLeft)
        return sr.location;
    else
        return ( sr.location + sr.length - 1 );
}

/*
 Finds the grapheme cluster that is visually to the left or to the right of the grapheme cluster generated from the characters in 'fromRange'.
 Returns kCFNotFound on failure (typically if the search goes past the end of the line).
 Note that the input range (like the returned index) indicates a character and its glyph(s), not an intercharacter space; this is equivalent to a "logically forward" affinity.
 On input *runIndexPtr must either be the index of a run containing the current grapheme cluster, or kCFNotFound.
 On output *runIndexPtr is the index of a run containing the result grapheme cluster.
*/
static CFIndex move1VisuallyWithinLine(CFArrayRef runs, CFStringRef base, CFRange fromRange, BOOL rtl, CFIndex *runIndexPtr)
{
    CTRunRef run = NULL;
    CFIndex runIndex = *runIndexPtr;
    if (runIndex < 0) {
        runIndex = searchRuns(runs, 0, CFArrayGetCount(runs), fromRange, &run);
    } else {
        run = CFArrayGetValueAtIndex(runs, runIndex);
    }
    CFIndex resultPosition;
    
    for (;;) {
        if (!run) {
            /* Something broke. Maybe we ran off the beginning/end of the line. */
            resultPosition = kCFNotFound;
            break;
        }
        
        CFRange runRange = CTRunGetStringRange(run);
        OBASSERT(cfRangeOverlapsCFRange(runRange, fromRange));
        
        CTRunStatus flags = CTRunGetStatus(run);
        DEBUG_TEXT(@"  moving %@ from=%"PRIdCFIndex"%+"PRIdCFIndex"; found run %"PRIdCFIndex" range=(%"PRIdCFIndex"%+"PRIdCFIndex") flags=%02x",
                   rtl?@"left":@"right", fromRange.location, fromRange.length, runIndex, runRange.location, runRange.length, flags);
#if 0
        if (flags & kCTRunStatusNonMonotonic) {
            /* TODO: Complicated case - in what situation could this happen? */
            /* Need to find an input that will make CT produce a kCTRunStatusNonMonotonic run */
        }
#endif
        if (XNOR(flags & kCTRunStatusRightToLeft, rtl) /* if we're going in the same direction as this run */) {
            CFIndex nextIndex = fromRange.location + fromRange.length;
            if (in_cfrange(runRange, nextIndex)) {
                /* Simple case: advance one grapheme cluster. */
                resultPosition = nextIndex;
                break;
            } else {
                /* Complex case: we ran off the end of the run. */
            }
        } else /* Run is left-to-right and we're going left, or it's right-to-left and we're going right */ {
            CFIndex nextIndex = fromRange.location - 1; /* this is ok since CFIndex is signed */
            if (in_cfrange(runRange, nextIndex)) {
                /* Simple case: retreat one grapheme cluster. */
                resultPosition = nextIndex;
                break;
            } else {
                /* Complex case: we ran off the end of the run. */
            }
        }
        
        DEBUG_TEXT(@"  Fell off end of run %u/%u (%s).", (unsigned)runIndex, (unsigned)CFArrayGetCount(runs), rtl?"moving left":"moving right");
        
        /* We need to jump to the "next" run in one direction or the other. We're assuming that runs are always ordered LTR, regardless of the string layout order, which appears to be experimentally true (but undocumented, of course) */
        
        if (rtl) {
            /* we're trying to hop left past the beginning of a run */
            do {
                if (runIndex <= 0) {
                    /* Whoops. */
                    resultPosition = kCFNotFound;
                    goto breakbreak;
                }
                runIndex --;
                run = CFArrayGetValueAtIndex(runs, runIndex);
                runRange = CTRunGetStringRange(run);
                /* keep going until we get a run that contains something outside of our current grapheme cluster */
            } while (cfRangeContainedByCFRange(runRange, fromRange));
            
            CFIndex pos = _rightmostStringIndex(CTRunGetStatus(run), runRange);
            if (!in_cfrange(fromRange, pos)) {
                /* This run is outside of the current grapheme cluster. Assume we've moved one cluster to the left. */
                resultPosition = pos;
                break;
            }
            /* Otherwise, the current grapheme cluster extends into this run (but doesn't occupy the whole run). */
        } else {
            /* we're trying to hop right past the end of a run */
            CFIndex runCount = CFArrayGetCount(runs);
            do {
                if (runIndex+1 >= runCount) {
                    /* Whoops. */
                    resultPosition = kCFNotFound;
                    goto breakbreak;
                }
                runIndex ++;
                run = CFArrayGetValueAtIndex(runs, runIndex);
                runRange = CTRunGetStringRange(run);
                /* keep going until we get a run that contains something outside of our current grapheme cluster */
            } while (cfRangeContainedByCFRange(runRange, fromRange));
            
            CFIndex pos = _leftmostStringIndex(CTRunGetStatus(run), runRange);
            if (!in_cfrange(fromRange, pos)) {
                /* This run is outside of the current grapheme cluster. Assume we've moved one cluster to the right. */
                resultPosition = pos;
                break;
            }
            /* Otherwise, the current grapheme cluster extends into this run (but doesn't occupy the whole run). */
        }
        
        /* If we've reached here, we've moved to a different run, but are still searching. */
    } /* end loop */
breakbreak:
    
    DEBUG_TEXT(@"  Finished moving %@; result position = %"PRIdCFIndex"",
               rtl?@"left":@"right", resultPosition);
    
    *runIndexPtr = runIndex;
    return resultPosition;
}

static NSUInteger moveVisuallyWithinLine(CTLineRef line, CFStringRef base, NSUInteger startPosition, NSInteger signedOffset)
{
    BOOL rtl;
    NSUInteger offset;
    
    if (signedOffset >= 0) {
        rtl = NO;
        offset = signedOffset;
    } else {
        rtl = YES;
        offset = - signedOffset;
    }
    
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFRange currentPosition = CFStringGetRangeOfGraphemeClusterAtIndex(base, startPosition);
    CFIndex runIndex = kCFNotFound;
    while (offset) {
        CFIndex nextPosition = move1VisuallyWithinLine(runs, base, currentPosition, rtl, &runIndex);
        
        if (nextPosition < 0) {
            /* Something broke. Maybe we ran off the beginning/end of the line. */
            break;
        }
        
        currentPosition = CFStringGetRangeOfGraphemeClusterAtIndex(base, nextPosition);
        offset --;
    } /* end while(offset) */
    
    DEBUG_TEXT(@"  Finished moving %@; result position = %"PRIdCFIndex"%+"PRIdCFIndex"",
               rtl?@"left":@"right", currentPosition.location, currentPosition.length);
    
    return currentPosition.location;
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset;
{
    if (!position)
        return nil;
    
    NSUInteger inGeneration = ((OUEFTextPosition *)position).generation;
    if (inGeneration != generation) {
        DEBUG_TEXT(@"warning: using %@ from gen %"PRIuNS" in gen %"PRIuNS"", [position description], inGeneration, generation);
    }
    
    if (offset == 0)
        return position;
    
    if (!drawnFrame || flags.textNeedsUpdate) {
        if (direction != OUITextLayoutDirectionForward && direction != OUITextLayoutDirectionBackward) {
            /* Except for the text storage directions, we need to have up-to-date layout information */
            
            [self _updateLayout:YES];
            if (!drawnFrame) {
                /* No layout info? Frame may be completely empty. */
                return nil;
            }
        }
    }
    
    NSUInteger contentLength = [_content length];
    NSUInteger pos = [(OUEFTextPosition *)position index];
    NSUInteger result;

    if (direction == OUITextLayoutDirectionForward || direction == OUITextLayoutDirectionBackward) {
        if (direction == OUITextLayoutDirectionBackward)
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
        struct typographicPosition measure;
        getTypographicPosition(lines, pos, ( offset < 0 )? -1 : 1, &measure);
        
        if (!measure.line) {
            /* No line for this position? */
            return nil;
        }
        
        result = moveVisuallyWithinLine(measure.line, (CFStringRef)[immutableContent string], pos, offset);
        if (result == pos)
            return [self positionFromPosition:position inDirection:OUITextLayoutDirectionForward offset:offset];
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
        
        CFIndex newStringIndex = [self _characterIndexOfPoint:(CGPoint){xPosn, origins[0].y} inLine:CFArrayGetValueAtIndex(lines, newIndex) lineOrigin:origins[0] stringRange:NSMakeRange(0, contentLength) lookingForTappedGlyph:NO outWasBeyondLineBounds:NULL];
        
        if (newStringIndex == kCFNotFound)
            return nil;
        
        if (newStringIndex < 0)
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
    OBASSERT(position != nil);
    OBASSERT(other != nil);
    
    /* This method is nonsensical if one of the positions is nil, but UIKit will occasionally ask us about that (see OBS #68542 and RADAR 8857073). */
    /* See also GitHub commit: https://github.com/iridia/OmniGroup/commit/f94eb369311d8b6cf0e84d5d7cdbf01845ce0dc0 */
    if (!position || !other)
        return NSOrderedSame;
    
    return [(OUEFTextPosition *)position compare:other];
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)toPosition;
{
    OBASSERT(from != nil);
    OBASSERT(toPosition != nil);
    /* This method is nonsensical if one of the positions is nil, but UIKit will occasionally ask us about that (see OBS #68542 and RADAR 8857073). */
    if (!from || !toPosition)
        return 0;


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
    if (direction == OUITextLayoutDirectionForward)
        return range.end;
    if (direction == OUITextLayoutDirectionBackward)
        return range.start;
    
    if (!range)
        return nil;
    
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    if (!drawnFrame)
        return nil;
        
    NSRange stringRange = [(OUEFTextRange *)range range];
    CFRange lineRange = [self _lineRangeForStringRange:stringRange];
    
    if (lineRange.length < 1 || lineRange.location < 0)
        return nil;  // Unlikely but not impossible for there to be no lines for this range
    
    UITextPosition *result;
    CGPoint *origins = malloc(sizeof(*origins) * lineRange.length);
    CTFrameGetLineOrigins(drawnFrame, lineRange, origins);
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    CFIndex contentLength = (CFIndex)[_content length];
    
    if (direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionRight) {
        
        CFIndex foundPosition = kCFNotFound;
        CGFloat foundPositionX = 0;
        
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
                    // This run doesn't overlap the range of interest; skip it.
                    if (runRange.location == contentLength && runRange.length == 1) {
                        // As a special case, though, if this run is just the implicit trailing newline we *do* need to consider it. Sometimes the implicit newline is in the final run (in which case the runEdgeIsEndOfContent case below handles it), sometimes not.
                    } else {
                        continue;
                    }
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
                
                // If the run's edge is not in our range, look at the edge of our range. But, if this is due to the implicit newline, don't (so control-e on the last line works, for example).
                BOOL runEdgeOutsideStringRange = ((NSUInteger)runEdge < stringRange.location || (NSUInteger)runEdge >= (stringRange.location + stringRange.length));
                BOOL runEdgeIsEndOfContent = (runEdge == contentLength);
                if (runEdgeOutsideStringRange && !runEdgeIsEndOfContent) {
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
                
                /* The offset that CTLine gives us is the location of the "starting" edge of the character (depending on the writing direction at that point). We really want the leftmost or rightmost edge, depending on our 'direction' argument. We could optionally move one character to the side, but then we get into trouble at run boundaries (it looks like the secondaryOffset might be intended to help with this, but secondaryOffset is basically undocumented).  We could retrieve the glyph advance from the CTRun, if needed. For now, I'm just going to punt. */
                    
                if (foundPosition == kCFNotFound ||
                    XNOR(foundPositionX < pos, direction == UITextLayoutDirectionRight)) {
                    foundPosition = runEdge;
                    foundPositionX = pos;
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
    if (!drawnFrame)
        return nil;
    
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    
    CTLineRef containingLine = NULL;
    if (bsearchLines(lines, 0, CFArrayGetCount(lines), posn.index, &containingLine) < 0 || !containingLine)
        return nil;
    
    CFRange lineRange = CTLineGetStringRange(containingLine);
    
    if (lineRange.location < 0) /* kCFNotFound is negative */
        return nil;
    
    CFIndex contentLength = [_content length];
    if (lineRange.location + lineRange.length > contentLength) // CTFrameGetLines() sees our magic trailing newline, but that isn't actually part of our content
        lineRange.length = contentLength - lineRange.location;

    // We can't do this since UITextInput seems to want newlines to be part of the line, and making that true means that this would cause control-e to not skip to the end of line, but one character short of it. Also, it turns out the UITextInput's emacs key bindings are busted. Testing in iWork, control-k only deletes to the ending of the LINE, not paragraph. AND it will never delete the newline. So... one approach is to be bug-for-bug compatible with them and hope they fix it in the system text input. See <bug:///70843> (Control-right arrow (and control-e) takes you to before the last character in the line [end of line]) for previous approaches to this that failed.
#if 0
    if (lineRange.length > 1 && [[_content string] characterAtIndex:lineRange.location + lineRange.length - 1] == '\n')
        lineRange.length--; // Don't include a trailing newline as part of the line range unless it's the entire range. (Control-K should delete up to the newline character without deleting the newline itself.)
#endif
    
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
    
    // UIKit uses this to position the autocorrection widget; returning a non-integral rect makes it blurry.
    return CGRectIntegral(r);
}

/* This returns the rectangle of the insertion caret, in our bounds coordinates */
- (CGRect)caretRectForPosition:(UITextPosition *)position;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    if (!drawnFrame) {
        OBASSERT_NOT_REACHED("Shouldn't be getting caret queries if we have no content.");
        return CGRectNull;
    }

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

- (UITextPosition *)closestPositionToPoint:(CGPoint)viewPoint withinRange:(UITextRange *)range;
{
    return [self _closestPositionToPoint:viewPoint withinRange:range lookingForTappedGlyph:NO wasBeyondLineBounds:NULL];
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
    if (!position)
        return nil;
    
    OUEFTextPosition *pos = (OUEFTextPosition *)position;
    NSUInteger index = pos.index;
    
    NSDictionary *ctStyles;
    
    if (selection && [selection isEmpty] && ((OUEFTextPosition *)selection.start).index == index)
        // Return typingAttributes, if position is the same as the insertion point. Otherwise, if the insertion point is at the end and we type a character, on the next blink of the caret we'll get an assertion trying to index past the end of our OATextStorage.
        ctStyles = [self typingAttributes];
    else if (direction == UITextStorageDirectionBackward && index > 0)
        ctStyles = [_content attributesAtIndex:index-1 effectiveRange:NULL];
    else
        ctStyles = [_content attributesAtIndex:index effectiveRange:NULL];
    

    NSMutableDictionary *uiStyles = [ctStyles mutableCopy];
    [uiStyles autorelease];
    
    CTFontRef ctFont = (CTFontRef)[ctStyles objectForKey:(id)kCTFontAttributeName];
    if (ctFont) {
        /* As far as I can tell, the name that UIFont wants is the PostScript name of the font. (It's undocumented, of course. RADAR 7881781 / 7241008) */
        CFStringRef fontName = CTFontCopyPostScriptName(ctFont);
        /* There's no way to tell the text input system that we're displaying a zoomed UI, but we can at least scale up the text in the correction rect. */
        UIFont *uif = [UIFont fontWithName:(id)fontName size:CTFontGetSize(ctFont) * MAX(1.0, [self scale])];
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
/*
 
 Only seen this called here so far (when pressing the up arrow in a long bit of wrapped text):
 
 #2  0x001b5b82 in -[OUIEditableFrame selectionAffinity] (self=0x17d5afa0, _cmd=0xcf9632) at /Volumes/Home/bungi/Source/Omni/trunk/OmniGroup/Frameworks/OmniUI/iPad/OUIEditableFrame.m:3204
 #3  0x00bd94a4 in -[NSObject(UITextInput_Internal) _moveUp:withHistory:] ()
 #4  0x00a1d921 in -[UIKeyboardImpl handleKeyCommand:repeatOkay:] ()
 */
#if 0 && defined(DEBUG_bungi)
- (UITextStorageDirection)selectionAffinity;
{
    return UITextStorageDirectionForward;
}
#endif

#if 0 && defined(DEBUG_bungi)
- (BOOL)respondsToSelector:(SEL)aSelector;
{
    BOOL rc = [super respondsToSelector:aSelector];
    if (!rc)
        NSLog(@"OUIEditableFrame respondsToSelector:@selector(%@) --> %d", NSStringFromSelector(aSelector), rc);
    return rc;
}

// This method is not in UITextInput, but they check for it and will call it with appropriate affinity based when you do control-e vs. control-a, for example.
- (void)setSelectedTextRange:(UITextRange *)range withAffinityDownstream:(int)xxx;
{
    NSLog(@"range = %@, downstream %d", range, xxx);
    [self setSelectedTextRange:range];
}
#endif

#pragma mark -
#pragma mark Private

/* Returns the coordinates and (in *what) the string index of the closest intercharacter point in the line */
static CGPoint _closestPointInLine(CTLineRef line, CGPoint lineOrigin, CGPoint tapPoint, NSRange stringRange, NSUInteger *what, BOOL lookingForTappedGlyph, BOOL *outWasBeyondLineBounds)
{
    CGFloat ascent = NAN;
    CGFloat descent = NAN;
    CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    
    CGFloat x = tapPoint.x - lineOrigin.x;
    CGFloat y = tapPoint.y - lineOrigin.y;
    
    // Clamp the y-coordinate to the line's typographic bounds
    if (y < -descent)
        y = -descent;
    else if (y > ascent)
        y = ascent;
    
    CFRange lineStringRange = CTLineGetStringRange(line);
    
    // Check for past the edges... TODO: bidi booyah
    if (x <= 0 && in_range(stringRange, lineStringRange.location)) {
        if (outWasBeyondLineBounds != NULL)
            *outWasBeyondLineBounds = lookingForTappedGlyph;
        *what = lineStringRange.location;
        return (CGPoint){ lineOrigin.x, lineOrigin.y + y };
    }
    if (x >= lineWidth && in_range(stringRange, lineStringRange.location + lineStringRange.length)) {
        if (outWasBeyondLineBounds != NULL)
            *outWasBeyondLineBounds = YES;
        *what = lineStringRange.location + lineStringRange.length;
        return (CGPoint){ lineOrigin.x + lineWidth, lineOrigin.y + y };
    }
    
    CFIndex lineStringIndex = CTLineGetStringIndexForPosition(line, (CGPoint){ x, y });
    if (lookingForTappedGlyph && (NSUInteger)lineStringIndex > stringRange.location) {
        // If you click on the right half of a character, the insertion point follows that character.  But we want to find the character itself (to follow links, open attachments, etc.), so let's look more carefully
        CGFloat previousX = CTLineGetOffsetForStringIndex(line, lineStringIndex - 1, NULL);
        CGFloat currentX = CTLineGetOffsetForStringIndex(line, lineStringIndex, NULL);
        if (x >= previousX && x < currentX) // Must have tapped on the right half of the previous character
            lineStringIndex--;
    }

    NSUInteger hitIndex;
    BOOL wasBeyondLineBounds;

    if (lineStringIndex < 0 || ((NSUInteger)lineStringIndex < stringRange.location)) {
        lineStringIndex = stringRange.location;
        hitIndex = stringRange.location;
        x = CTLineGetOffsetForStringIndex(line, lineStringIndex, NULL);
        wasBeyondLineBounds = YES;
    } else if (((NSUInteger)lineStringIndex - stringRange.location) > stringRange.length) {
        lineStringIndex = stringRange.location + stringRange.length;
        hitIndex = stringRange.location + stringRange.length;
        x = CTLineGetOffsetForStringIndex(line, lineStringIndex, NULL);
        wasBeyondLineBounds = YES;
    } else {
        hitIndex = lineStringIndex;
        wasBeyondLineBounds = NO;
    }

    *what = hitIndex;
    if (outWasBeyondLineBounds != NULL)
        *outWasBeyondLineBounds = wasBeyondLineBounds;
    return (CGPoint){
        .x = lineOrigin.x + x,
        .y = lineOrigin.y + y
    };
}

- (NSUInteger)_characterIndexOfPoint:(CGPoint)tapPoint inLine:(CTLineRef)line lineOrigin:(CGPoint)lineOrigin stringRange:(NSRange)stringRange lookingForTappedGlyph:(BOOL)lookingForTappedGlyph outWasBeyondLineBounds:(BOOL *)outWasBeyondLineBounds;
    // TODO: Change this to return the stringPosition since no callers want our current return value
{
    NSUInteger stringPosition;
    BOOL wasBeyondLineBounds;
    _closestPointInLine(line, lineOrigin, tapPoint, stringRange, &stringPosition, lookingForTappedGlyph, &wasBeyondLineBounds);

    // Tapping beyond the end of a line indicates you're tapping before its end-of-line character, not after it
    if (!lookingForTappedGlyph && wasBeyondLineBounds && stringPosition > 0 && [[_content string] characterAtIndex:stringPosition - 1] == '\n')
        stringPosition--;

    if (outWasBeyondLineBounds != NULL)
        *outWasBeyondLineBounds = wasBeyondLineBounds;

    return stringPosition;
}

- (OUEFTextPosition *)_closestPositionToPoint:(CGPoint)viewPoint withinRange:(UITextRange *)range lookingForTappedGlyph:(BOOL)lookingForTappedGlyph wasBeyondLineBounds:(BOOL *)outWasBeyondLineBounds;
{
    if (!drawnFrame || flags.textNeedsUpdate)
        [self _updateLayout:YES];
    if (!drawnFrame)
        return nil;
    
    NSRange r;
    CFRange lineRange;
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    CFIndex lineCount = CFArrayGetCount(lines);
    NSUInteger contentLength = [_content length];
    
    if (range) {
        r = [(OUEFTextRange *)range range];
        lineRange = [self _lineRangeForStringRange:r];
    } else {
        r.location = 0;
        r.length = contentLength;
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
    
    DEBUG_TEXT(@"For p=%.1f,%.1f: line range is %"PRIdCFIndex"+%"PRIdCFIndex", subIndex = %"PRIdCFIndex"",
               point.x, point.y, lineRange.location, lineRange.length, subIndex);
    
    NSUInteger result;
    BOOL wasBeyondLineBounds;

    if (subIndex == 0 && point.y < origins[0].y) {
        // Before any of our lines
        result = 0;
        wasBeyondLineBounds = lookingForTappedGlyph;
    } else if (subIndex >= lineRange.length){
        // After all of our lines
        result = [[_content string] length];
        wasBeyondLineBounds = YES;
    } else {
        result = [self _characterIndexOfPoint:point inLine:CFArrayGetValueAtIndex(lines, lineRange.location + subIndex) lineOrigin:origins[subIndex] stringRange:r lookingForTappedGlyph:lookingForTappedGlyph outWasBeyondLineBounds:&wasBeyondLineBounds];
    }
    
    free(origins);
    OUEFTextPosition *p = [[[OUEFTextPosition alloc] initWithIndex:result] autorelease];
    p.generation = generation;
    if (outWasBeyondLineBounds)
        *outWasBeyondLineBounds = wasBeyondLineBounds;

    return p;
}

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
    if (!drawnFrame)
        return CGRectNull;
    
    CFArrayRef lines = CTFrameGetLines(drawnFrame);
    
    struct typographicPosition measures;
    
    NSUInteger contentLength = [_content length];
    NSUInteger positionIndex = position.index;
    if (positionIndex > contentLength) {
        OBASSERT_NOT_REACHED("Bad position given");
        positionIndex = contentLength;
    }
    
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
    textRect.size.width = 1.0;
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
    // We cannot early out on the range being the same as before here. The text system depends on us sending selection change notifications to close text input auxilliary views. We probably shouldn't be calling the inputDelegate methods here, though, but in higher level code (unclear, but Apple's sample doesn't). If the higher level code was calling the delegate, then we could go back to having an early-out.
    // See <bug:///72532> (Can't tap out of the suggestions list for Japanese marked text)
#if 0
    if (_rangeIsInsertionPoint(self, newRange))
        return;
#endif
    
    /* TODO: If the old and new selections are both ranges, and only differ by a few characters at one end, we can potentially save a lot of redraw by computing the difference and redrawing only the extension/contraction */
    
    if (!CGRectIsEmpty(selectionDirtyRect)) {
        [self setNeedsDisplayInRect:selectionDirtyRect];
        selectionDirtyRect = CGRectNull;
    }
    
    if (newRange && (![newRange isEmpty] || flags.solidCaret))
        [self _setNeedsDisplayForRange:newRange];
    
    /* shouldNotify is NO if we're being called from a UITextInput / UIKeyInput protocol method. See the comment ahead of -insertText:. */
    if (shouldNotify)
        [inputDelegate selectionWillChange:self];
    [selection release];
    selection = [newRange retain];
    if (_typingAttributes) {
        [_typingAttributes release];
        _typingAttributes = nil;
    }
    if (shouldNotify) {
        [inputDelegate selectionDidChange:self];
        if (flags.delegateRespondsToSelectionChanged)
            [delegate textViewSelectionChanged:self];
    }
    
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

- (BOOL)_characterAtIndex:(NSUInteger)index containsPoint:(CGPoint)p
{
    OUEFTextPosition *start = [[[OUEFTextPosition alloc] initWithIndex:index] autorelease];
    OUEFTextPosition *end = [[[OUEFTextPosition alloc] initWithIndex:index + 1] autorelease];

    UITextRange *range = [self textRangeFromPosition:start toPosition:end];

    CGRect bounds = [self boundsOfRange:range];
    return (CGRectContainsPoint(bounds, p));
}

- (OUEFTextRange *)_textRangeForAttachmentAtIndex:(NSUInteger)index;
{
    OBASSERT([[_content string] characterAtIndex:index] == OAAttachmentCharacter);
    OUEFTextPosition *start = [[[OUEFTextPosition alloc] initWithIndex:index] autorelease];
    OUEFTextPosition *end = [[[OUEFTextPosition alloc] initWithIndex:index + 1] autorelease];
    start.generation = generation;
    end.generation = generation;

    return [[[OUEFTextRange alloc] initWithStart:start end:end] autorelease];
}

- (UITextRange *)selectionRangeForPoint:(CGPoint)p granularity:(UITextGranularity)granularity;
{
    BOOL wasBeyondLineBounds = NO;
    OUEFTextPosition *pp = [self _closestPositionToPoint:p withinRange:nil lookingForTappedGlyph:granularity != UITextGranularityCharacter wasBeyondLineBounds:&wasBeyondLineBounds];
    if (!pp)
        return nil;
    
    if (granularity != UITextGranularityCharacter) {
        UITextRange *wordRange = [[self tokenizer] rangeEnclosingPosition:pp withGranularity:granularity inDirection:UITextStorageDirectionForward];
        if (wordRange != nil)
            return wordRange;
    }

    if (granularity == UITextGranularityCharacter)
        granularity = tapSelectionGranularity;

    NSString *string = [_content string];
    NSUInteger stringLength = [string length];

    if (stringLength > 0 && !wasBeyondLineBounds && granularity != UITextGranularityCharacter) {
        // UITextView looks for the edge of whitespace when performing a tap within a line

        NSUInteger characterIndex = pp.index;
        OFCharacterSet *whitespaceOFCharacterSet = [OFCharacterSet whitespaceOFCharacterSet];
        OBASSERT(characterIndex <= [string length]);

        // Test to see if point was an attachment, if so return a range for the attachment.
        NSUInteger testIndex = characterIndex;
        if (characterIndex == stringLength)
            testIndex--;

        if ([string characterAtIndex:testIndex] == OAAttachmentCharacter && [self _characterAtIndex:testIndex containsPoint:p])
            return [self _textRangeForAttachmentAtIndex:testIndex];
        
        testIndex--;
        
        if ([string characterAtIndex:testIndex] == OAAttachmentCharacter && [self _characterAtIndex:testIndex containsPoint:p])
            return [self _textRangeForAttachmentAtIndex:testIndex];

        if (characterIndex == stringLength || OFCharacterSetHasMember(whitespaceOFCharacterSet, [string characterAtIndex:characterIndex])) {
            // If we're on whitespace, scan backward for non-whitespace
            while (characterIndex > 0) {
                characterIndex--;
                unichar nextCharacter = [string characterAtIndex:characterIndex];
                if (!OFCharacterSetHasMember(whitespaceOFCharacterSet, nextCharacter)) {
                    characterIndex++; // Position just after the non-whitespace
                    break;
                }
            }
        } else {
            // If we're not starting on whitespace, look back a few characters for some whitespace before scanning forward
            BOOL foundLeadingWhitespace = NO;
            NSUInteger lookbackIndex = characterIndex;
            while (lookbackIndex > 0 && characterIndex - lookbackIndex < 2) {
                lookbackIndex--;
                unichar lookbackCharacter = [string characterAtIndex:lookbackIndex];
                if (OFCharacterSetHasMember(whitespaceOFCharacterSet, lookbackCharacter)) {
                    foundLeadingWhitespace = YES;
                    characterIndex = lookbackIndex + 1; // Position just after the whitespace
                    break;
                }
            }

            if (!foundLeadingWhitespace && lookbackIndex == 0) {
                foundLeadingWhitespace = YES; // The start of the buffer can be considered whitespace
                characterIndex = 0;
            }

            if (!foundLeadingWhitespace) {
                // Scan forward for whitespace
                while ((++characterIndex) < stringLength) {
                    unichar nextCharacter = [string characterAtIndex:characterIndex];
                    if (OFCharacterSetHasMember(whitespaceOFCharacterSet, nextCharacter)) {
                        // We've found the end of our non-whitespace
                        break;
                    }
                }
            }
        }

        pp = [[[OUEFTextPosition alloc] initWithIndex:characterIndex] autorelease];
        pp.generation = generation;
    }
    
    return [[[OUEFTextRange alloc] initWithStart:pp end:pp] autorelease];
}

- (UITextRange *)selectionRangeForPoint:(CGPoint)p wordSelection:(BOOL)selectWords;
{
    return [self selectionRangeForPoint:p granularity:selectWords ? UITextGranularityWord : UITextGranularityCharacter];
}

- (UITextPosition *)tappedPositionForPoint:(CGPoint)point;
{
    BOOL wasBeyondLineBounds = NO;
    OUEFTextPosition *textPosition = [self _closestPositionToPoint:point withinRange:nil lookingForTappedGlyph:YES wasBeyondLineBounds:&wasBeyondLineBounds];
    if (wasBeyondLineBounds)
        return nil;
    return textPosition;
}

- (id)attribute:(NSString *)attributeName atPosition:(UITextPosition *)position effectiveRange:(UITextRange **)outRange;
{
    OBPRECONDITION([position isKindOfClass:[OUEFTextPosition class]]);
    OUEFTextPosition *textPosition = (OUEFTextPosition *)position;
    if (outRange == NULL)
        return [_content attributesAtIndex:textPosition.index effectiveRange:NULL];

    NSRange range;
    NSDictionary *attributes = [_content attribute:attributeName atIndex:textPosition.index effectiveRange:&range];
    *outRange = [[[OUEFTextRange alloc] initWithRange:range generation:generation] autorelease];
    return attributes;
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
- (CGRect)boundsOfRange:(UITextRange *)_range;
{
    OBPRECONDITION([_range isKindOfClass:[OUEFTextRange class]]);
    OUEFTextRange *range = (OUEFTextRange *)_range;
    
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

/* Both the single-tap and double-tap recognizers call this */
- (void)_activeTap:(UITapGestureRecognizer *)r;
{
    DEBUG_TEXT(@" -> %@", r);
    CGPoint p = [r locationInView:self];

    UITextGranularity granularity;
    switch (r.numberOfTapsRequired) {
        default: case 1:
            granularity = UITextGranularityCharacter;
            break;
        case 2:
            granularity = UITextGranularityWord;
            break;
        case 3:
            granularity = UITextGranularityParagraph;
            break;
    }
    OUEFTextRange *newSelection = (OUEFTextRange *)[self selectionRangeForPoint:p granularity:granularity];
    OBASSERT(!newSelection || [newSelection isKindOfClass:[OUEFTextRange class]]);
                                 
    if (newSelection) {        
        // Apple's text editor behaves this way: if you tap-to-select on the same point twice (as opposed to a double-tap, which is a different gesture), then it shows the context menu
        // We avoid this case if there is marked text since then we could have input method specific controls up instead. Clearing the marked text and informing the input delegate will close those.
        // See <bug:///72532> (Can't tap out of the suggestions list for Japanese marked text)
        if (r.numberOfTapsRequired == 1 && [newSelection isEqualToRange:selection] && markedRange.location == NSNotFound) {
            self.showingEditMenu = YES;
        } else {
            [self unmarkText];
            [self setSelectedTextRange:newSelection];
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
            [[self _topmostView] addSubview:_loupe];
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
    
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        _loupe.mode = OUILoupeOverlayNone;
        flags.showingEditMenu = 1;  // Hint that the edit menu would be appropriate once the loupe disappears.
        [self _setSolidCaret:-1];
        return;
    }

    /* UITextView has two selection inspecting/altering modes: caret and range. If you have a caret, you get a round selection inspection that just alters the inspection point. If you have a range, then the end of the range that your tap is closest to is altered and a rectangular selection inspector is shown. The endpoint manipulation goes through OUEFTextThumb, so we're just dealing with caret adjustment here. */
    _loupe.mode = OUILoupeOverlayCircle;
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
    CGAffineTransform *centerScanUnderTransform;
    BOOL includeInterline;        // Whether to extend lines vertically to fill gaps
};

/* Convenience routine for initializing the fields of rectpathwalker */
static void getMargins(OUIEditableFrame *self, struct rectpathwalker *r)
{
    CGRect bounds = [self convertRectFromRenderingSpace:[self bounds]];  // Note -convertRectFromRenderingSpace: is misleadingly named
    r->layoutOrigin = self->layoutOrigin;
    r->leftEdge = bounds.origin.x + self->_currentTextInset.left;
    r->rightEdge = bounds.origin.x + bounds.size.width - ( self->_currentTextInset.left + self->_currentTextInset.right );
    r->bounds = CGRectNull;
    
    r->currentLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
    r->previousLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
    
    r->centerScanUnderTransform = NULL;
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
    
    if (r->centerScanUnderTransform) {
        alignExtentToPixelCenters(r->centerScanUnderTransform->tx, r->centerScanUnderTransform->a, &highlightRect.origin.x, &highlightRect.size.width);
        alignExtentToPixelCenters(r->centerScanUnderTransform->ty, r->centerScanUnderTransform->d, &highlightRect.origin.y, &highlightRect.size.height);
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

/* Draw the backgrounds of and runs with non-nil OABackgroundColorAttributeName. This is in this file (rather than OUITextLayout) because it uses internal helpers from OUIEditableFrame. I plan to refactor the two files along different lines soon, though. */
BOOL OUITextLayoutDrawRunBackgrounds(CGContextRef ctx, CTFrameRef drawnFrame, NSAttributedString *immutableContent,
                                     CGPoint layoutOrigin, CGFloat leftEdge, CGFloat rightEdge,
                                     OUITextLayoutSpanBackgroundFilter filter)
{
    BOOL sawAnything = NO;
    
    NSUInteger cursor = 0;
    NSUInteger textLength = [immutableContent length];
    while (cursor < textLength) {
        NSRange span = { 0, 0 };
        CGColorRef bgColor = (CGColorRef)[immutableContent attribute:OABackgroundColorAttributeName
                                                             atIndex:cursor
                                               longestEffectiveRange:&span
                                                             inRange:(NSRange){cursor, textLength-cursor}];
        if (!span.length)
            break;
        
        // Allow the caller to selectively filter our spans. This is used by OO/iPad to avoid double-compositing translucent background colors.
        if (bgColor && CGColorGetAlpha(bgColor) > 0 && (!filter || filter(span, bgColor))) {
            sawAnything = YES;
            
            struct rectpathwalker ctxt;
            ctxt.ctxt = ctx;
            ctxt.includeInterline = YES;
            
            /* cribbed from getMargins() */
            ctxt.layoutOrigin = layoutOrigin;
            ctxt.leftEdge = leftEdge;
            ctxt.rightEdge = rightEdge;
            ctxt.bounds = CGRectNull; /* of the walked rectangles, not of the drawing area */
            
            ctxt.currentLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
            ctxt.previousLine = (struct rectpathwalkerLineBottom){ NAN, NAN, NAN };
            
            ctxt.centerScanUnderTransform = NULL;
            
            CGContextSetFillColorWithColor(ctx, bgColor);
            CGContextBeginPath(ctx);
            rectanglesInRange(drawnFrame, span, NO, addRectsToPath, &ctxt);
            CGContextFillPath(ctx);
        }
        
        cursor = span.location + span.length;
    }
    
    return sawAnything;
}

- (void)_drawDecorationsBelowText:(CGContextRef)ctx
{
    if (!drawnFrame || flags.textNeedsUpdate)
        return;
    
    /* Draw any text background runs */
    if (flags.mayHaveBackgroundRanges) {
        
        CGRect bounds = [self convertRectFromRenderingSpace:[self bounds]];  // Note -convertRectFromRenderingSpace: is misleadingly named

        /* The later args to OUITextLayoutDrawRunBackgrounds() are what getMargins() normally computes */
        BOOL sawAnything = OUITextLayoutDrawRunBackgrounds(ctx, drawnFrame, immutableContent,
                                                           self->layoutOrigin,
                                                           bounds.origin.x + self->_currentTextInset.left,
                                                           bounds.origin.x + bounds.size.width - ( self->_currentTextInset.left + self->_currentTextInset.right ), _backgroundSpanFilter);
        if (!sawAnything)
            flags.mayHaveBackgroundRanges = 0;
    }

    
    /* Draw the selection highlight for range selections. */
    if (selection && ![selection isEmpty]) {
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
    
    /* Draw the marked-text indication's background, if any */
    if (markedRange.length && _markedRangeBackgroundColor) {
        struct rectpathwalker ctxt;
        ctxt.ctxt = ctx;
        ctxt.includeInterline = NO;
        getMargins(self, &ctxt);
        
        CGContextBeginPath(ctx);
        [_markedRangeBackgroundColor setFill];
        rectanglesInRange(drawnFrame, markedRange, NO, addRectsToPath, &ctxt);
        CGContextFillPath(ctx);
        
        // Record the rect we dirtied so we can redraw when the marked range changes
        markedTextDirtyRect = CGRectIntegral([self convertRectToRenderingSpace:ctxt.bounds]); // note this method does the opposite of what its name implies
    }
}

/* We have some decorations that are drawn over the text instead of under it */
- (void)_drawDecorationsAboveText:(CGContextRef)ctx
{
    CGAffineTransform currentCTM = CGContextGetCTM(ctx);
    
    /* Draw the marked-text indication's border, if any */
    if (markedRange.length && _markedRangeBorderColor) {
        struct rectpathwalker ctxt;
        ctxt.ctxt = ctx;
        ctxt.includeInterline = NO;
        getMargins(self, &ctxt);
        ctxt.centerScanUnderTransform = &currentCTM;
        CGFloat strokewidth = _markedRangeBorderThickness;
        
        CGContextBeginPath(ctx);
        [_markedRangeBorderColor setStroke];
        CGContextSetLineWidth(ctx, strokewidth);
        rectanglesInRange(drawnFrame, markedRange, NO, addRectsToPath, &ctxt);
        CGContextStrokePath(ctx);
        
        // note that -convertRectToRenderingSpace: does the opposite of what its name implies
        CGRect dirty = [self convertRectToRenderingSpace:CGRectInset(ctxt.bounds, -0.5 * strokewidth, -0.5 * strokewidth)];
        markedTextDirtyRect = CGRectUnion(markedTextDirtyRect, CGRectIntegral(dirty));
    }
    
    /* If we're not using a separate view to draw our caret, draw it here */
    if (flags.solidCaret) {
        if (selection && [selection isEmpty]) {
            // If we're being drawn zoomed, we might not need as much enlargement of the caret in order for it to be visible
            CGFloat nominalScale = self.scale;
            double actualScale = sqrt(fabs(OQAffineTransformGetDilation(currentCTM)));
            
            CGRect caretRect = [self _caretRectForPosition:(OUEFTextPosition *)(selection.start) affinity:1 bloomScale:MAX(nominalScale, actualScale)];
            
            if (!CGRectIsEmpty(caretRect)) {
                [_insertionPointSelectionColor setFill];
                CGContextFillRect(ctx, caretRect);
                CGRect dirty = [self convertRectToRenderingSpace:caretRect]; // note this method does the opposite of what its name implies
                selectionDirtyRect = CGRectUnion(selectionDirtyRect, CGRectIntegral(dirty));
            }
        }
    }
}

- (void)_setNeedsDisplayForRange:(OUEFTextRange *)range;
{
    /*
     Right now this is only called to invalidate a rectangle when the selection changes.
     If we eventually want to invalidate text ranges for other reasons, we might want to not include the caret rectangles, and we may need to include more space (around attachments or backgrounds, perhaps)
    */
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
        /* We don't want the same behavior as boundsOfRange: here, unfortunately: that method intentionally doesn't extend the rect out to the margins when a line wraps, because the extra area doesn't have any actual text in it for the UI element to point to. On the other hand, _setNeedsDisplayForRange: is usually called to invalidate a rectangle so that the selection can redraw, and we need to extend out in the same way that the selection-drawing code does. */
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
        
        NSMutableAttributedString *contentWithNewline = [[NSMutableAttributedString alloc] initWithAttributedString:_content];
        
        NSDictionary *newlineAttributes;
        if ([contentWithNewline length] > 0) {
            newlineAttributes = OUITextLayoutCopyExtraNewlineAttributes([contentWithNewline attributesAtIndex:[contentWithNewline length] - 1 effectiveRange:NULL]);
        } else
            newlineAttributes = [[self _allDefaultAttributes] copy];
        
        NSAttributedString *newlineAttributedString = [[NSAttributedString alloc] initWithString:@"\n" attributes:newlineAttributes];
        [newlineAttributes release];
        
        [contentWithNewline appendAttributedString:newlineAttributedString];
        [newlineAttributedString release];
        
        immutableContent = OUICreateTransformedAttributedString(contentWithNewline, _linkTextAttributes);
        if (immutableContent) {
            flags.immutableContentHasAttributeTransforms = YES;
            [contentWithNewline release];
        } else {
            // Didn't need transformation
            immutableContent = [contentWithNewline copy];
            [contentWithNewline release];
            flags.immutableContentHasAttributeTransforms = NO;
        }
        flags.mayHaveBackgroundRanges = 1;
        
        framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)immutableContent);
        
        flags.textNeedsUpdate = NO;
    }
    
    while (computeDrawnFrame && !drawnFrame) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGRect bounds = self.bounds;
        CGFloat scale = self.scale;

        // Default to filling our bounds width and growing "infinitely" high. Need to adjust from UIView coordinates to CoreGraphics rendering coordinates for these.
        CGSize frameSize;
        {
            frameSize = bounds.size;
            CGFloat invScale = 1.0/scale;
            frameSize.width *= invScale;
            frameSize.height *= invScale;
        }
        
        if (CGSizeEqualToSize(layoutSize, CGSizeZero)) {
            frameSize.height = OUITextLayoutUnlimitedSize;
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
            frameSize.width = OUITextLayoutUnlimitedSize;
        }
        if (frameSize.height == 0) {
            OBASSERT_NOT_REACHED("Using unlimited layout height since none was specified"); // Need to specify one implicitly via the view frame or textLayoutSize property.
            frameSize.height = OUITextLayoutUnlimitedSize;
        }
        
        BOOL widthIsConstrained = (frameSize.width != OUITextLayoutUnlimitedSize);
        BOOL heightIsConstrained = (frameSize.height != OUITextLayoutUnlimitedSize);
        
        // Adjust the length of any limited layout axis by the insets for that axis. Our CGPath below is still zero-origined and we deal with the offset in origin from the textInset elsewhere (though maybe we could do it via the framesetter path?
        if (widthIsConstrained)
            frameSize.width -= (_minimumTextInset.left + _minimumTextInset.right);
        if (heightIsConstrained)
            frameSize.height -= (_minimumTextInset.top + _minimumTextInset.bottom);
        
        
        DEBUG_TEXT(@"  Laying out with bounds %@, CG size %@", NSStringFromCGRect(self.bounds), NSStringFromCGSize(frameSize));
        
        CGPathAddRect(path, NULL, CGRectMake(0, 0, frameSize.width, frameSize.height));
        DEBUG_TEXT(@"%@ editableFrame using %f x %f", [_content string], frameSize.width, frameSize.height);

        drawnFrame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, NULL);
        
        /* CTFrameGetLines() is documented not to return NULL. */
        OBASSERT(CTFrameGetLines(drawnFrame) != NULL);
        
        CFRelease(path);
        
        // Calculate the used size (ignoring the text inset, if any).
        CGRect typographicFrame = OUITextLayoutMeasureFrame(drawnFrame, YES, widthIsConstrained);
        _usedSize = typographicFrame.size;
        
        if (!widthIsConstrained) {
            CGRect layoutFrame = CGRectMake(0, 0, typographicFrame.size.width, frameSize.height);
            DEBUG_TEXT(@"  Re-laying out with size %@", NSStringFromCGSize(layoutFrame.size));

            path = CGPathCreateMutable();
            CGPathAddRect(path, NULL, layoutFrame);
            
            CFRelease(drawnFrame);
            drawnFrame = CTFramesetterCreateFrame(framesetter, (CFRange){0, 0}, path, NULL);
            CFRelease(path);
        }

        _currentTextInset = _minimumTextInset;
        if (flags.shouldTryToCenterFirstLine) {
            _currentTextInset.top = OUITopTextInsetToCenterFirstLineAtY(drawnFrame, _firstLineCenterTarget / scale, _minimumTextInset);
            _currentTextInset.bottom = _minimumTextInset.bottom + _currentTextInset.top - _minimumTextInset.top;
        }
        layoutOrigin = OUITextLayoutOrigin(typographicFrame, _currentTextInset, bounds, scale);
        
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
            case OUITextLayoutDirectionForward:
            case UITextLayoutDirectionRight:
            case UITextLayoutDirectionDown:
            default:
                positionToSelect = selectionRange.end;
                break;
            case OUITextLayoutDirectionBackward:
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

/* We sometimes need to stash a view at the top of our window's view hierarchy, but if we make it the immediate subview of our UIWindow, then itdoesn't handle interface rotation. So find the subview of our window which is our ancestor (or is us). */
- (UIView *)_topmostView;
{
    UIView *aView = self;
    
    for(;;) {
        UIView *parentView = [aView superview];
        if (!parentView || [parentView isKindOfClass:[UIWindow class]])
            return aView;
        aView = parentView;
    }
}

- (NSAttributedString *)_attributedTextInRange:(UITextRange *)range;
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

#pragma mark Context menu methods

- (BOOL)showsInspector;
{
    return flags.showsInspector;
}

- (void)setShowsInspector:(BOOL)flag;
{
    flags.showsInspector = flag ? 1 : 0;
}

- (NSArray *)inspectableTextSpans;
{
    if (!selection)
        return nil;
    
    // Return one span per run so that the higher level code can make different edits to each span (for example, turning on italic should keep the font face that was on each span or keep the boldness).
    
    NSMutableArray *runs = [NSMutableArray array];

    // An insertion point should be inspectable so we can control the typingAttributes from the inspector.
    NSRange range = selection.range;
    if (range.length == 0) {
        OUEFTextSpan *run = [[OUEFTextSpan alloc] initWithRange:range generation:generation editor:self];
        [runs addObject:run];
        [run release];
        return runs;
    }
    
    while (range.length > 0) {
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

- (NSArray *)_configureInspector;
{
    NSArray *runs = [self inspectableTextSpans];
    if (!runs)
        return nil;
    
    DEBUG_TEXT(@"Inspecting: %@", [runs description]);
    
    if (!_textInspector) {
        _textInspector = [[OUIInspector alloc] init];
        _textInspector.delegate = self;
        _textInspector.mainPane.title = NSLocalizedStringFromTableInBundle(@"Text Style", @"OUIInspectors", OMNI_BUNDLE, @"Inspector title");
        
        // We'll get our slices via our delegate hook (which allows subclasses to add to/remove from/rearrange our default set).
        OBASSERT([_textInspector.mainPane isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
    }
    
    return runs;
}

- (void)inspectSelectedText:(id)sender
{
    CGRect selectionRect = [self boundsOfRange:selection];
    if (CGRectIsEmpty(selectionRect))
        return;
    
    NSArray *runs = [self _configureInspector];
    [_textInspector inspectObjects:runs fromRect:selectionRect inView:self permittedArrowDirections:UIPopoverArrowDirectionAny];
}

- (void)inspectSelectedTextFromBarButtonItem:(UIBarButtonItem *)barButtonItem;
{
    NSArray *runs = [self _configureInspector];
    [_textInspector inspectObjects:runs fromBarButtonItem:barButtonItem];
}

- (NSRange)characterRangeForTextRange:(UITextRange *)textRange;
{
    OBPRECONDITION([textRange isKindOfClass:[OUEFTextRange class]]);
    
    NSRange result = [(OUEFTextRange *)textRange range];

    OBASSERT(NSMaxRange(result) <= [_content length]); // No reason to be asking for anything past the last character (could be insertion point at the end).
    return result;
}

#pragma mark OUIInspectorDelegate

- (NSArray *)inspector:(OUIInspector *)inspector makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    NSMutableArray *slices = [NSMutableArray array];
    [slices addObject:[[[OUITextColorAttributeInspectorSlice alloc] initWithLabel:NSLocalizedStringFromTableInBundle(@"Text color", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the text color.")
                                                                    attributeName:OAForegroundColorAttributeName] autorelease]];
    [slices addObject:[[[OUITextColorAttributeInspectorSlice alloc] initWithLabel:NSLocalizedStringFromTableInBundle(@"Background color", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the text color.")
                                                                    attributeName:OABackgroundColorAttributeName] autorelease]];
    [slices addObject:[[[OUIFontAttributesInspectorSlice alloc] init] autorelease]];
    [slices addObject:[[[OUIFontInspectorSlice alloc] init] autorelease]];
    [slices addObject:[[[OUIParagraphStyleInspectorSlice alloc] init] autorelease]];
    
    return slices;
}

- (void)inspectorDidDismiss:(OUIInspector *)inspector;
{
    [self becomeFirstResponder];
}

#pragma mark -
#pragma mark OATextStorageDelegate

- (void)textStorageDidProcessEditing:(NSNotification *)notification;
{
    OBPRECONDITION([notification object] == _content);
    
    if (immutableContent == nil) {
        // If we made this change, the immutableContent would have been cleared already (in our beforeMutate).
        return;
    }
    
    // Looks like this is some external edit of the text storage (like applying edits via an OSTextSelectionStyle in OO/iPad).
    // We don't get notified before the edit here, so we don't have a way to send the -textWillChange: message to the delegate, so we don't send inputDelegate messages at all here (we do send them to *our* delegate in notifyAfterMutate).
    // Also, since we didn't start the fir... edit, we specify OUIEditableFrameMutationOptionNotifyNotEditingTextStorage to avoid sending -beginEditing/-endEditing.
    OUIEditableFrameMutationOptions options = OUIEditableFrameMutationOptionNotifyNotEditingTextStorage;
    
    if ([_content editedMask] == OATextStorageEditedAttributes) {
        OBASSERT([_content changeInLength] == 0);
        options |= OUIEditableFrameMutationOptionAttributesOnly;
    }
    
    beforeMutate(self, _cmd, options);
    afterMutate(self, _cmd, options);
    notifyAfterMutate(self, _cmd, options);

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

@end

