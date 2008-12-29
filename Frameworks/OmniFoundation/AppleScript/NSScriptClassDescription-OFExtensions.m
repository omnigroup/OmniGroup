// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSScriptClassDescription-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/AppleScript/NSScriptClassDescription-OFExtensions.m 98770 2008-03-17 22:25:33Z kc $");

@implementation NSScriptClassDescription (OFExtensions)

+ (NSScriptClassDescription *)commonScriptClassDescriptionForObjects:(NSArray *)objects;
{
    unsigned int objectIndex = [objects count];
    NSScriptClassDescription *common = nil;
    
    while (objectIndex--) {
	id object = [objects objectAtIndex:objectIndex];
	
	NSScriptClassDescription *desc = (NSScriptClassDescription *)[object classDescription];
	if (!desc)
	    [NSException raise:NSInvalidArgumentException format:@"No class description for %@.", OBShortObjectDescription(object)];
	if (![desc isKindOfClass:[NSScriptClassDescription class]])
	    [NSException raise:NSInvalidArgumentException format:@"Class description for %@ is not a script class description.", OBShortObjectDescription(object)];

	// We expect that objects won't return a synonym class description
	OBASSERT(desc == [[object class] classDescription]);
	
	if (common) {
	    if ([desc isKindOfScriptClassDescription:common]) {
		// already common
	    } else {
		// Look up desc's ancestors to find something that is a parent of common.
		NSScriptClassDescription *ancestor = desc;
		while (ancestor) {
		    if ([common isKindOfScriptClassDescription:ancestor]) {
			common = ancestor;
			break;
		    }
		    ancestor = [ancestor superclassDescription];
		}
		
		if (!ancestor)
		    // No common class description
		    return nil;
	    }
	} else {
	    common = desc;
	}
    }
    
    return common;
}

- (BOOL)isKindOfScriptClassDescription:(NSScriptClassDescription *)desc;
{
    NSScriptClassDescription *ancestor = self;
    while (ancestor && ancestor != desc)
	ancestor = [ancestor superclassDescription];
    return (ancestor != nil);
}

@end
