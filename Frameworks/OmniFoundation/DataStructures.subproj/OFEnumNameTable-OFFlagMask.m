// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFEnumNameTable-OFFlagMask.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Id$")

@implementation OFEnumNameTable (OFFlagMask)

- (NSString *)copyStringForMask:(NSUInteger)mask withSeparator:(unichar)separator;
{
    if (mask == 0)
	return [[self nameForEnum:0] copy];
    
    NSMutableString *result = [[NSMutableString alloc] init];
    
    NSUInteger enumIndex, enumCount = [self count];
    for (enumIndex = 0; enumIndex < enumCount; enumIndex++) {
	NSInteger enumValue = [self enumForIndex:enumIndex];
	if (mask & enumValue) { // The 0 entry will fail this trivially so we need not skip it manually
	    NSString *name = [self nameForEnum:enumValue];
	    if ([result length])
		[result appendFormat:@"%C%@", separator, name];
	    else
		[result appendString:name];
	}
    }
    
    return result;
}

- (NSUInteger)maskForString:(NSString *)string withSeparator:(unichar)separator;
{
    // Avoid passing nil to -[OFStringScanner initWithString:];
    if ([string isEqualToString:[self nameForEnum:0]] || [NSString isEmptyString:string])
	return 0;
    
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:string];
    NSString *name;
    NSUInteger mask = 0;
    while ((name = [scanner readFullTokenWithDelimiterCharacter:separator])) {
	mask |= [self enumForName:name];
	[scanner readCharacter];
    }
    [scanner release];
    
    return mask;
}

@end
