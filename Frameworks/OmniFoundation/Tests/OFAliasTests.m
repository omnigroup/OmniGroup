// Copyright 2004-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFAlias.h>

#import <OmniBase/rcsid.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>

RCS_ID("$Id$")

@interface OFAliasTest : OFTestCase
{
}
@end

@implementation OFAliasTest

- (void)testAlias
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *path = [fileManager tempFilenameFromHashesTemplate:@"/tmp/OFAliasTest-######"];
    should(path != nil);
    if (!path)
        return;
    
    should([[NSData data] writeToFile:path atomically:NO]);
    
    OFAlias *originalAlias = [[OFAlias alloc] initWithPath:path];
    NSString *resolvedPath = [originalAlias path];
    
    shouldBeEqual([path stringByStandardizingPath], [resolvedPath stringByStandardizingPath]);
    
    NSData *aliasData = [originalAlias data];
    OFAlias *restoredAlias = [[OFAlias alloc] initWithData:aliasData];
    
    NSString *moveToPath1 = [fileManager tempFilenameFromHashesTemplate:@"/tmp/OFAliasTest-######"];
    should([fileManager moveItemAtPath:path toPath:moveToPath1 error:NULL]);
    
    NSString *resolvedMovedPath = [restoredAlias path];
    
    shouldBeEqual([moveToPath1 stringByStandardizingPath], [resolvedMovedPath stringByStandardizingPath]);
    
    NSString *moveToPath2 = [fileManager tempFilenameFromHashesTemplate:@"/tmp/OFAliasTest-######"];
    should([fileManager moveItemAtPath:moveToPath1 toPath:moveToPath2 error:NULL]);
    
    NSData *movedAliasData = [[NSData alloc] initWithBase64String:[[restoredAlias data] base64String]];
    OFAlias *movedAliasFromData = [[OFAlias alloc] initWithData:aliasData];
    should([movedAliasFromData path] != nil);
    
    should([fileManager removeItemAtPath:moveToPath2 error:NULL]);
    
    [originalAlias release];
    [restoredAlias release];
    [movedAliasData release];
    [movedAliasFromData release];
}

@end
