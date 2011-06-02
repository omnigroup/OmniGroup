// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextInputStringTokenizer.h"

#import <OmniUI/OUIEditableFrame.h>
#import <OmniBase/rcsid.h>

#import "OUEFTextPosition.h"
#import "OUEFTextRange.h"

RCS_ID("$Id$");


/* We rely on the UITextInputStringTokenizer for most behavior; the only thing it can't help with is layout-related questions, which basically means line movement. */
/* You can get UIKit to invoke beginning/end of line methods by using ^A and ^E on a hardware keyboard */

#if 0

extern const struct enumName {} directions[], granularities[];
extern NSString *nameof(NSInteger v, const struct enumName *ns);

#define DEBUGLOG(...) NSLog(__VA_ARGS__)

#else

#define DEBUGLOG(...) /* */

#endif

@implementation OUITextInputStringTokenizer

- (id)initWithTextInput:(UIResponder <UITextInput> *)textInput;
{
    self = [super initWithTextInput:textInput];
    if (self == nil)
        return nil;

    _nonretainedTextInput = textInput;

    return self;
}

- (UITextRange *)rangeEnclosingPosition:(UITextPosition *)position withGranularity:(UITextGranularity)granularity inDirection:(UITextDirection)direction;   // Returns range of the enclosing text unit of the given granularity, or nil if there is no such enclosing unit.  Whether a boundary position is enclosed depends on the given direction, using the same rule as isPosition:withinTextUnit:inDirection:
{
    UITextRange *r;
    
    if (position == nil) {
        r = nil;
    } else if (granularity == UITextGranularityLine) {
        // This causes <bug:///72506> (Control-a while at the beginning of a line in multiple lines of text moves to to the beginning of the line above)
        // With this on, if we have a long bunch of text that is wrapped into multiple lines, and we put the insertion point at the beginning of a line (so it is after the space on the previous line), then control-a will get the range of the *previous* line here. This will make -isPosition:atBoundary:inDirection: return NO and we'll jump to the beginning of the previous line.
#if 0
        /* -[OUIEditableFrame rangeOfLineContainingPosition:] returns the range of the line containing the character pointed to by the position. */
        /* This method appears to be intended to treat the positin as referring to an intercharacter gap. */
        /* We can get the proper behavior by adjusting the position backwards one character, but we don't want to adjust forwards. */
        if (direction != UITextStorageDirectionForward) {
            OUEFTextPosition *adjusted = (OUEFTextPosition *)[_nonretainedTextInput positionFromPosition:position inDirection:direction offset:1];
            if (!adjusted || [adjusted compare:position] == NSOrderedAscending)
                position = adjusted;
            /* Note if adjusted==nil, we want to return nil; -rangeOfLineContainingPosition: will pass through a nil position for us */
        }
#endif   
        r = [(OUIEditableFrame *)_nonretainedTextInput rangeOfLineContainingPosition:(OUEFTextPosition *)position];
    } else {
        r = [super rangeEnclosingPosition:position withGranularity:granularity inDirection:direction];
    }
    
    DEBUGLOG(@"rangeEnclosing(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), [r description]);
    return r;
}

- (BOOL)isPosition:(UITextPosition *)position atBoundary:(UITextGranularity)granularity inDirection:(UITextDirection)direction;                             // Returns YES only if a position is at a boundary of a text unit of the specified granularity in the particular direction.
{
    BOOL rc;
    
    do {
        // The superclass doesn't seem to know about selection affinity (it doesn't ask the textInput for its -selectionAffinity when the position is just after a newline).
        // It seems like it could work for paragraphs by checking for newlines, but it doesn't.
        UITextRange *range = [self rangeEnclosingPosition:position withGranularity:granularity inDirection:direction];
            
        if (direction == UITextStorageDirectionForward || direction == UITextLayoutDirectionRight) {
            rc = [range.end isEqual:position];
            break;
        } else if (direction == UITextStorageDirectionBackward || direction == UITextLayoutDirectionLeft) {
            rc = [range.start isEqual:position];
            break;
        } else {
            OBASSERT_NOT_REACHED("Unhandled direction; fall through and hope for the best from the superclass...");
        }
        
        rc = [super isPosition:position atBoundary:granularity inDirection:direction];
    } while (0);
    
    DEBUGLOG(@"positionAtBoundary(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), rc ? @"YES":@"NO");
    return rc;
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position toBoundary:(UITextGranularity)granularity inDirection:(UITextDirection)direction;   // Returns the next boundary position of a text unit of the given granularity in the given direction, or nil if there is no such position.
{
    DEBUGLOG(@"Computing positionFromTo(%@, %@, %@) ...", [position description], nameof(granularity, granularities), nameof(direction, directions));
    UITextPosition *r;
    if (granularity != UITextGranularityLine) {
        r = [super positionFromPosition:position toBoundary:granularity inDirection:direction];
    } else if (position == nil) {
        r = nil;
    } else {
        UITextRange *line = [self rangeEnclosingPosition:position withGranularity:UITextGranularityLine inDirection:direction];

        if (!line)
            r = nil;
        else {
            /* Up and Down don't make much sense here; treat them like Backwards and Forwards */
            switch (direction) {
                case UITextStorageDirectionForward:
                case UITextLayoutDirectionDown:
                    r = line.end;
                    break;
                case UITextStorageDirectionBackward:
                case UITextLayoutDirectionUp:
                    r = line.start;
                    break;
                default:
                    /* For right and left, we need to ask the laid-out text for layout information again */
                    r = [_nonretainedTextInput positionWithinRange:line farthestInDirection:direction];
            }
        }
    }
    DEBUGLOG(@"positionFromTo(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), [r description]);
    return r;
}


- (BOOL)isPosition:(UITextPosition *)position withinTextUnit:(UITextGranularity)granularity inDirection:(UITextDirection)direction;                         // Returns YES if position is within a text unit of the given granularity.  If the position is at a boundary, returns YES only if the boundary is part of the text unit in the given direction.
{
    /* TODO: Line boundaries? */
    BOOL r = [super isPosition:position withinTextUnit:granularity inDirection:direction];
    DEBUGLOG(@"positionWithinUnit(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), r? @"YES" : @"NO");
    return r;
}

@end
