// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextInputStringTokenizer.h"
#import "OUEFTextPosition.h"
#import "OUEFTextRange.h"
#import "OUIEditableFrame.h"
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");


/* TODO: Provide a nonempty implementation of this. Looks like the only behavior we need to implement ourselves is the granularity=UITextGranularityLine case of each method, since the others are unaffected by layout. */
/* TODO: Figure out when those methods might actually be invoked, so we can test whether our implementation actually does the right thing. (On the other hand, if they're never invoked, I guess we don't need to implement them.) */
/* You can get it to invoke beginning/end of line methods by using ^A and ^E on a hardware keyboard */

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
    
    if (granularity == UITextGranularityLine) {
        /* -[OUIEditableFrame rangeOfLineContainingPosition:] returns the range of the line containing the character pointed to by the position. */
        /* This method appears to be intended to treat the positin as referring to an intercharacter gap. */
        /* We can get the proper behavior by adjusting the position backwards one character, but we don't want to adjust forwards. */
        if (direction != UITextStorageDirectionForward) {
            OUEFTextPosition *adjusted = (OUEFTextPosition *)[_nonretainedTextInput positionFromPosition:position inDirection:direction offset:1];
            if (!adjusted || [adjusted compare:position] == NSOrderedAscending)
                position = adjusted;
            /* Note if adjusted==nil, we want to return nil; -rangeOfLineContainingPosition: will pass through a nil position for us */
        }
        
        r = [(OUIEditableFrame *)_nonretainedTextInput rangeOfLineContainingPosition:(OUEFTextPosition *)position];
    } else {
        r = [super rangeEnclosingPosition:position withGranularity:granularity inDirection:direction];
    }
    
    //NSLog(@"rangeEnclosing(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), [r description]);
    return r;
}

- (BOOL)isPosition:(UITextPosition *)position atBoundary:(UITextGranularity)granularity inDirection:(UITextDirection)direction;                             // Returns YES only if a position is at a boundary of a text unit of the specified granularity in the particular direction.
{
    BOOL r = [super isPosition:position atBoundary:granularity inDirection:direction];
    //NSLog(@"positionAtBoundary(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), r?@"YES":@"NO");
    return r;
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position toBoundary:(UITextGranularity)granularity inDirection:(UITextDirection)direction;   // Returns the next boundary position of a text unit of the given granularity in the given direction, or nil if there is no such position.
{
    //NSLog(@"Computing positionFromTo(%@, %@, %@) ...", [position description], nameof(granularity, granularities), nameof(direction, directions));
    UITextPosition *r;
    if (granularity != UITextGranularityLine) {
        r = [super positionFromPosition:position toBoundary:granularity inDirection:direction];
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
    //NSLog(@"positionFromTo(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), [r description]);
    return r;
}


- (BOOL)isPosition:(UITextPosition *)position withinTextUnit:(UITextGranularity)granularity inDirection:(UITextDirection)direction;                         // Returns YES if position is within a text unit of the given granularity.  If the position is at a boundary, returns YES only if the boundary is part of the text unit in the given direction.
{
    BOOL r = [super isPosition:position withinTextUnit:granularity inDirection:direction];
    //NSLog(@"positionWithinUnit(%@, %@, %@) -> %@", [position description], nameof(granularity, granularities), nameof(direction, directions), r? @"YES" : @"NO");
    return r;
}

@end
