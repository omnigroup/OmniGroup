// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
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
        should([scan scanUpToStringCaseInsensitive:pat]);
    } else {
        shouldnt([scan scanUpToStringCaseInsensitive:pat]);
    }
    shouldBeEqual([scan readLine], follows);
    [scan release];
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
    should([s scanStringOfLength:3 intoString:&into]);
    shouldBeEqual(into, @"abc");
    
    should([s scanStringOfLength:3 intoString:&into]);
    shouldBeEqual(into, @"def");
    
    should([s isAtEnd]);
    shouldnt([s scanStringOfLength:3 intoString:&into]);
    should([s isAtEnd]);

    s = [NSScanner scannerWithString:@"ghijkl"];
    into = NULL;
    should([s scanStringOfLength:0 intoString:&into]);
    shouldBeEqual(into, @"");
    
    shouldnt([s scanStringOfLength:10 intoString:&into]);
    shouldBeEqual(into, @"");
    
    should([s scanStringOfLength:5 intoString:&into]);
    shouldBeEqual(into, @"ghijk");

    shouldnt([s scanStringOfLength:2 intoString:&into]);
    shouldBeEqual(into, @"ghijk");
    shouldnt([s isAtEnd]);
    
    should([s scanStringOfLength:1 intoString:&into]);
    shouldBeEqual(into, @"l");

    should([s isAtEnd]);
    
    should([s scanStringOfLength:0 intoString:&into]);
    shouldBeEqual(into, @"");

    should([s isAtEnd]);

    into = @"zzz";
    shouldnt([s scanStringOfLength:1 intoString:&into]);
    shouldBeEqual(into, @"zzz");
    should([s isAtEnd]);
}

@end // OFStringScannerTest

