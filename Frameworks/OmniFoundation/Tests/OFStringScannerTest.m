// Copyright 2000-2008, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/NSScanner-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFStringScannerTest : OFTestCase
{
}

- (void)scanForPattern:(NSString *)pat
                inText:(NSString *)text
             expecting:(BOOL)findIt :(NSString *)follows;

@end

@interface OFNSStringScannerTest : OFTestCase
{
}
@end

@implementation OFStringScannerTest

// TODO: convert into a #define so that line numbers are properly reported
- (void)scanForPattern:(NSString *)pat inText:(NSString *)text expecting:(BOOL)findIt :(NSString *)follows
{
    OFStringScanner *scan;
	
    scan = [[OFStringScanner alloc] initWithString:text];
    if (findIt) {
        XCTAssertTrue([scan scanUpToStringCaseInsensitive:pat]);
    } else {
        XCTAssertFalse([scan scanUpToStringCaseInsensitive:pat]);
    }
    XCTAssertEqualObjects([scan readLine], follows);
}

- (void)testCharScanning
{
    [self scanForPattern:@"oof" inText:@"blah blah oof blah" expecting: YES : @"oof blah"];
    [self scanForPattern:@"oof" inText:@"blah blah ooof blah" expecting: YES : @"oof blah"];
    [self scanForPattern:@"fofoo" inText:@"knurd fofoo blurfl" expecting: YES : @"fofoo blurfl"];
    [self scanForPattern:@"fofoo" inText:@"knurd fofofoo blurfl" expecting: YES : @"fofoo blurfl"];
    [self scanForPattern:@"fofoo" inText:@"knurd foofoofoo blurfl" expecting: NO : nil];
}

@end

@implementation OFNSStringScannerTest

- (void)testScanStringOfLength
{
    NSScanner *s;
    NSString *into;
    
    s = [NSScanner scannerWithString:@"abcdef"];
    into = NULL;
    XCTAssertTrue([s scanStringOfLength:3 intoString:&into]);
    XCTAssertEqualObjects(into, @"abc");
    
    XCTAssertTrue([s scanStringOfLength:3 intoString:&into]);
    XCTAssertEqualObjects(into, @"def");
    
    XCTAssertTrue([s isAtEnd]);
    XCTAssertFalse([s scanStringOfLength:3 intoString:&into]);
    XCTAssertTrue([s isAtEnd]);

    s = [NSScanner scannerWithString:@"ghijkl"];
    into = NULL;
    XCTAssertTrue([s scanStringOfLength:0 intoString:&into]);
    XCTAssertEqualObjects(into, @"");
    
    XCTAssertFalse([s scanStringOfLength:10 intoString:&into]);
    XCTAssertEqualObjects(into, @"");
    
    XCTAssertTrue([s scanStringOfLength:5 intoString:&into]);
    XCTAssertEqualObjects(into, @"ghijk");

    XCTAssertFalse([s scanStringOfLength:2 intoString:&into]);
    XCTAssertEqualObjects(into, @"ghijk");
    XCTAssertFalse([s isAtEnd]);
    
    XCTAssertTrue([s scanStringOfLength:1 intoString:&into]);
    XCTAssertEqualObjects(into, @"l");

    XCTAssertTrue([s isAtEnd]);
    
    XCTAssertTrue([s scanStringOfLength:0 intoString:&into]);
    XCTAssertEqualObjects(into, @"");

    XCTAssertTrue([s isAtEnd]);

    into = @"zzz";
    XCTAssertFalse([s scanStringOfLength:1 intoString:&into]);
    XCTAssertEqualObjects(into, @"zzz");
    XCTAssertTrue([s isAtEnd]);
}

@end // OFStringScannerTest

