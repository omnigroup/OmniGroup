// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSScriptObjectSpecifier-OFExtensions.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSScriptObjectSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    // Subclass to return NO.
    return YES;
}
@end

@interface NSRangeSpecifier (OFExtensions)
@end
@implementation NSRangeSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    return NO; // even if our range is a single index, we are asking for it as an array
}
@end

@interface NSRelativeSpecifier (OFExtensions)
@end
@implementation NSRelativeSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    return [[self baseSpecifier] specifiesSingleObject];
}
@end

@interface NSWhoseSpecifier (OFExtensions)
@end
@implementation NSWhoseSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    NSWhoseSubelementIdentifier startSubelement = [self startSubelementIdentifier];
    NSWhoseSubelementIdentifier endSubelement = [self endSubelementIdentifier];
    
    // Requested a single item (start==index and end==index would probably be interpreted as a length 1 array)
    return ((startSubelement == NSIndexSubelement || startSubelement == NSMiddleSubelement || startSubelement == NSRandomSubelement) &&
            endSubelement == NSNoSubelement);
}
@end




