// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>

RCS_ID("$Id$");

@implementation NSMutableAttributedString (OFExtensions)

- (void)appendString:(NSString *)string attributes:(NSDictionary *)attributes;
{
    NSAttributedString *append;

    append = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    [self appendAttributedString:append];
    [append release];
}

/*" Appends the given string to the receiver, using the attributes of the last character in the receiver for the new characters.  If the receiver is empty, the appended string has no attributes. "*/
- (void)appendString:(NSString *)string;
{
    NSDictionary *attributes = nil;
    unsigned int  length = [self length];

    if (length)
        attributes = [self attributesAtIndex:length-1 effectiveRange:NULL];
    [self appendString:string attributes:attributes];
}

/*" Iterates over the receiver allowing the mutator function to provide replacements for ranges.  If 'matchString' is nil, then the mutator is called once for each contiguous range of identical attributes in the receiver.  If 'matchString' is non-nil, then only ranges with the given string are passed to the mutator.  Note that in the non-nil 'matchString' case, the 'matchRange' will be the range of the found string while the 'effectiveAttributeRange' will be the effective range of the attributes <b>clipped</b> to the match range.  In the nil 'matchString' case, both ranges will be equal.  The mutator function can return nil to indicate no action or it can return an new (retained!) attributed string to be replaced in the receiver for the match range.  The mutator function can also modify attributes on the source text storage and return nil to indicate that no replacement need be done.  In this case, the mutator is responsible for calling -beginEditing and setting *isEditing (only if it is not already set).  If a replacement is done, the replacement itself will not be scanned (that is, the mutator will not be called for any range that it produced).  This method will call -beginEditing and -endEditing if necessary, so the caller need not do that.  Returns YES if any edits were made. "*/
- (BOOL)mutateRanges:(OFMutableAttributedStringMutator)mutator inRange:(NSRange)sourceRange matchingString:(NSString *)matchString context:(void *)context;
{
    NSString     *string = [self string];
    BOOL          didBeginEditing = NO;

    // NOTE: Past this location 'sourceRange' can be invalid; if we replace a string in the source range, we'll only update location/end but not sourceRange!
    unsigned int  location = sourceRange.location;
    unsigned int  end      = sourceRange.location + sourceRange.length;
#define sourceRange doNotUseMe
    
    while (location < end) {
        NSRange matchRange = {0, 0}; // matchRange shouldn't need to be initialized here, but gcc 4.0 / i386 doesn't realize that

        if (matchString) {
            matchRange = [string rangeOfString:matchString options:0 range:NSMakeRange(location,end-location)];
            
            if (matchRange.length <= 0)
                break;
            
            // Match string should fall *entirely* in the remaining source range
            OBASSERT(NSEqualRanges(matchRange, NSIntersectionRange(matchRange, NSMakeRange(location, end - location))));
            location = matchRange.location;
        }

        NSRange effectiveRange;
        NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:&effectiveRange];

        // Make sure the extent of the range we'll mutate doesn't extend outside the source range
        effectiveRange = NSIntersectionRange(effectiveRange, NSMakeRange(location, end - location));
        
        if (matchString) {
            // clip the attribute range to the match range.
            effectiveRange = NSIntersectionRange(effectiveRange, matchRange);
            OBASSERT(effectiveRange.length > 0);
        } else {
            // Set matchRange to *something*
            matchRange = effectiveRange;
        }
        
        NSAttributedString *replacement = mutator(self, attributes, matchRange, effectiveRange, &didBeginEditing, context);

        if (replacement) {
            if (!didBeginEditing) {
                didBeginEditing = YES;
                [self beginEditing];
            }

            unsigned int oldLength = [[self string] length];
            
            [self replaceCharactersInRange:matchRange withAttributedString:replacement];

            string   = [self string]; // Don't know if this is mandatory, but it seems like a really good idea

            // 'end' might be the end of the 'sourceRange', NOT of the entire string!
            unsigned int newLength = [string length];

            if (oldLength > newLength) // Avoid signed/unsigned issues
                end -= (oldLength - newLength);
            else
                end += (newLength - oldLength);

            location = matchRange.location + [replacement length];
            [replacement release];
        } else {
            location = matchRange.location + matchRange.length;
        }
    }

    if (didBeginEditing)
        [self endEditing];
    return didBeginEditing;
#undef sourceRange
}

- (BOOL)mutateRanges:(OFMutableAttributedStringMutator)mutator matchingString:(NSString *)matchString context:(void *)context;
{
    return [self mutateRanges:mutator inRange:(NSRange){0, [self length]} matchingString:matchString context:context];
}

@end

