// Copyright 2004-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFAlias.h>

#import <OmniBase/rcsid.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/OFXMLIdentifier.h>

RCS_ID("$Id$")

/*

 NOTE: These tests and the underlying class are on the way out. High Sierra + APFS breaks resolution of aliases when the underlying file has been moved (and aliases have been deprecated in favor of bookmark data for a long while).

 */

#if 0

@interface OFAliasTest : OFTestCase
@end

@implementation OFAliasTest

static NSString *temporaryPath(void)
{
    return [NSTemporaryDirectory() stringByAppendingString:[@"OFAliasTest-" stringByAppendingString:OFXMLCreateID()]];
}

- (void)testAlias
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *path = temporaryPath();

    XCTAssertTrue([[NSData data] writeToFile:path options:0 error:NULL]);
    
    OFAlias *originalAlias = [[OFAlias alloc] initWithPath:path];
    NSString *resolvedPath = [originalAlias path];
    
    XCTAssertEqualObjects([path stringByStandardizingPath], [resolvedPath stringByStandardizingPath]);
    
    NSData *aliasData = [originalAlias data];
    OFAlias *restoredAlias = [[OFAlias alloc] initWithData:aliasData];
    
    NSString *moveToPath1 = temporaryPath();
    XCTAssertTrue([fileManager moveItemAtPath:path toPath:moveToPath1 error:NULL]);
    
    NSString *resolvedMovedPath = [restoredAlias path];
    
    XCTAssertEqualObjects([moveToPath1 stringByStandardizingPath], [resolvedMovedPath stringByStandardizingPath]);
    
    NSString *moveToPath2 = temporaryPath();
    XCTAssertTrue([fileManager moveItemAtPath:moveToPath1 toPath:moveToPath2 error:NULL]);
    
    NSData *movedAliasData = [[NSData alloc] initWithASCII85String:[[restoredAlias data] ascii85String]];
    OFAlias *movedAliasFromData = [[OFAlias alloc] initWithData:movedAliasData];
    XCTAssertTrue([movedAliasFromData path] != nil);
    
    XCTAssertTrue([fileManager removeItemAtPath:moveToPath2 error:NULL]);
    
}

@end

#endif

