// Copyright 2004-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>

RCS_ID("$Id$");

@interface OFMutableAttributedStringExtensionsTest : OFTestCase
@end

static NSAttributedString *_replacementMutator(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context)
{
    // Supposed to return a retained object
    return [(NSAttributedString *)context retain];
}

// Tests the length calculations in the replacement portion of the NSMutableAttributedString mutator method
static void __testReplace(id self, NSString *sourceString, NSRange sourceRange, NSString *lookFor, NSString *replaceWith, NSString *resultString)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSAttributedString *replacementAttributedString = [[[NSAttributedString alloc] initWithString:replaceWith attributes:nil] autorelease];
    NSMutableAttributedString *mutatingString = [[[NSMutableAttributedString alloc] initWithString:sourceString attributes:nil] autorelease];

    BOOL didReplace = [mutatingString mutateRanges:_replacementMutator inRange:sourceRange matchingString:lookFor context:replacementAttributedString];

    should(didReplace == ([sourceString rangeOfString:lookFor options:0 range:sourceRange].length > 0));
    shouldBeEqual([mutatingString string], resultString);

    [pool release];
}

#define _testReplace(sourceString, sourceRange, lookFor, replaceWith, resultString) \
        __testReplace(self, sourceString, sourceRange, lookFor, replaceWith, resultString)

@implementation OFMutableAttributedStringExtensionsTest

- (void)testMutation;
{
    _testReplace(@"ab",  NSMakeRange(0,2), @"a", @"xxxx", @"xxxxb");       // Replace prefix with something longer
    _testReplace(@"aba", NSMakeRange(0,3), @"a", @"xxxx", @"xxxxbxxxx");  // Prefix and suffix
    _testReplace(@"aba", NSMakeRange(0,2), @"a", @"xxxx", @"xxxxba");     // Two copies of it, but range only covers first
    _testReplace(@"aba", NSMakeRange(1,1), @"a", @"xxxx", @"aba");        // Two copies of it, but range covers neither

    _testReplace(@"xxxxb",     NSMakeRange(0,5), @"xxxx", @"a", @"ab");        // Replace prefix with something shorter
    _testReplace(@"xxxxbxxxx", NSMakeRange(0,9), @"xxxx", @"a", @"aba");       // Prefix and suffix
    _testReplace(@"xxxxbxxxx", NSMakeRange(0,5), @"xxxx", @"a", @"abxxxx");    // Two copies of it, but range only covers first
    _testReplace(@"xxxxbxxxx", NSMakeRange(4,1), @"xxxx", @"a", @"xxxxbxxxx"); // Two copies of it, but range covers neither
}

@end
