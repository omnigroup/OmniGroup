// Copyright 2003-2005, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHeaderDictionary.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <XCTest/XCTest.h>

RCS_ID("$Id$");

@interface OWHeaderDictionaryTests : XCTestCase
{
}

@end

@implementation OWHeaderDictionaryTests

- (void)testParameterizedValueParsing
{
    NSEnumerator *ee;
    NSString *value;
    OFMultiValueDictionary *d;
    NSString *p;

    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"" intoDictionary:d valueChars:nil];
    XCTAssertEqualObjects(p, @"");
    XCTAssertEqualObjects([d allKeys], [NSArray array]);

    ee = [[NSArray arrayWithObjects:
        @"foom", @"  foom", @"foom\t", @"foom ; ",
        @"foom; ", @"foom\t\n;", nil] objectEnumerator];
    while( (value = [ee nextObject]) != nil) {
        d = [[[OFMultiValueDictionary alloc] init] autorelease];
        p = [OWHeaderDictionary parseParameterizedHeader:value intoDictionary:d valueChars:nil];
        XCTAssertEqualObjects([p stringByRemovingSurroundingWhitespace], @"foom");
        XCTAssertEqualObjects([d allKeys], [NSArray array]);
    }

    ee = [[NSArray arrayWithObjects:
        @"foom ; foo=bar",
        @"foom;\tfoo = bar ",
        @"foom\n\t;foo=bar\n\t",
        @"\t\t\tfoom ;foo =\"bar\"\n",
        @"foom;foo=\n\"bar\"",
        @"foom;foo=\t\"\\b\\a\\r\"",
        nil] objectEnumerator];
    while( (value = [ee nextObject]) != nil) {
        d = [[[OFMultiValueDictionary alloc] init] autorelease];
        p = [OWHeaderDictionary parseParameterizedHeader:value intoDictionary:d valueChars:nil];
        XCTAssertEqualObjects(p, @"foom");
        XCTAssertEqualObjects([d allKeys], [NSArray arrayWithObject:@"foo"]);
        XCTAssertEqualObjects([d arrayForKey:@"foo"], [NSArray arrayWithObject:@"bar"]);
    }

    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om; bar=\" ba\\\"z\"; bonk = \"\\\\oof \";" intoDictionary:d valueChars:nil];
    XCTAssertEqualObjects(p, @"fo/om");
    XCTAssertTrue([[d allKeys] count] == 2);
    XCTAssertEqualObjects([d arrayForKey:@"bar"], [NSArray arrayWithObject:@" ba\"z"]);
    XCTAssertEqualObjects([d arrayForKey:@"bonk"], [NSArray arrayWithObject:@"\\oof "]);

    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om; bar=\"ba\\ \\\\\\\"z\"; bar = \"\\\\\"" intoDictionary:d valueChars:nil];
    XCTAssertEqualObjects(p, @"fo/om");
    XCTAssertTrue([[d allKeys] count] == 1);
    XCTAssertEqualObjects([d arrayForKey:@"bar"], ([NSArray arrayWithObjects:@"ba \\\"z", @"\\", nil]));

    // Expected parse failure: parameter names are not supposed to be quoted-strings.
    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om ;bar=\"ba z\"; \"bonk\" = oof;" intoDictionary:d valueChars:nil];
    XCTAssertEqualObjects([d allKeys], [NSArray arrayWithObject:@"bar"]);
    XCTAssertEqualObjects([d arrayForKey:@"bar"], ([NSArray arrayWithObjects:@"ba z", nil]));
}

- (void)testParameterizedValueFormatting
{
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"bar"], @"foo=bar");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"b ar"], @"foo=\"b ar\"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"bar\""], @"foo=\"bar\\\"\"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@""], @"foo=\"\"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"\\"], @"foo=\"\\\\\"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@" "], @"foo=\" \"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@" ba\\"], @"foo=\" ba\\\\\"");
    XCTAssertEqualObjects([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"ab "], @"foo=\"ab \"");
}

- (void)testScannerBehavior
{
    NSScanner *s;
    NSString *scannedValue;
    
    // NSScanner's behavior in some cases is undocumented or vague. We verify here that it's behaving the way we expect.

    s = [NSScanner scannerWithString:@"foo"];
    XCTAssertTrue([s scanUpToString:@"f" intoString:NULL] == NO); // this one is documented clearly

    // What happens if you scanUpToString where the string is not found? Answer: scanner goes to the end of the string and leaves its scanLocation there.
    XCTAssertTrue([s scanUpToString:@"zz" intoString:&scannedValue] == YES);
    XCTAssertEqualObjects(scannedValue, @"foo");
    XCTAssertTrue([s scanLocation] == 3);
    XCTAssertTrue([s isAtEnd]);

    s = [NSScanner scannerWithString:@"bar"];
    XCTAssertTrue([s scanUpToString:@"r" intoString:&scannedValue] == YES);
    XCTAssertEqualObjects(scannedValue, @"ba");
    XCTAssertTrue([s scanLocation] == 2);
    XCTAssertTrue(![s isAtEnd]);
    XCTAssertTrue([s scanString:@"r" intoString:NULL] == YES);
    XCTAssertTrue([s scanLocation] == 3);
    XCTAssertTrue([s isAtEnd]);
    XCTAssertTrue([s scanUpToString:@"r" intoString:&scannedValue] == NO);
    XCTAssertTrue([s scanLocation] == 3);
    XCTAssertTrue([s isAtEnd]);
}

- (void)testHeaderSplitting
{
    XCTAssertEqualObjects([OWHeaderDictionary splitHeaderValues:[NSArray array]], [NSArray array]);
    XCTAssertEqualObjects([OWHeaderDictionary splitHeaderValues:[NSArray arrayWithObject:@"foo,bar"]], ([NSArray arrayWithObjects:@"foo", @"bar", nil]));
    XCTAssertEqualObjects([OWHeaderDictionary splitHeaderValues:[NSArray arrayWithObject:@"text/foo;charset=\"blah\", text/bar;q=0.3,text/baz; stupidParam=\"Oh, what a good boy am I\""]], ([NSArray arrayWithObjects:@"text/foo;charset=\"blah\"", @" text/bar;q=0.3", @"text/baz; stupidParam=\"Oh, what a good boy am I\"", nil]));
}

@end

