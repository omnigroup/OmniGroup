// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
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
#import <SenTestingKit/SenTestingKit.h>

RCS_ID("$Id$");

@interface OWHeaderDictionaryTests : SenTestCase
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
    shouldBeEqual(p, @"");
    shouldBeEqual([d allKeys], [NSArray array]);

    ee = [[NSArray arrayWithObjects:
        @"foom", @"  foom", @"foom\t", @"foom ; ",
        @"foom; ", @"foom\t\n;", nil] objectEnumerator];
    while( (value = [ee nextObject]) != nil) {
        d = [[[OFMultiValueDictionary alloc] init] autorelease];
        p = [OWHeaderDictionary parseParameterizedHeader:value intoDictionary:d valueChars:nil];
        shouldBeEqual([p stringByRemovingSurroundingWhitespace], @"foom");
        shouldBeEqual([d allKeys], [NSArray array]);
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
        shouldBeEqual(p, @"foom");
        shouldBeEqual([d allKeys], [NSArray arrayWithObject:@"foo"]);
        shouldBeEqual([d arrayForKey:@"foo"], [NSArray arrayWithObject:@"bar"]);
    }

    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om; bar=\" ba\\\"z\"; bonk = \"\\\\oof \";" intoDictionary:d valueChars:nil];
    shouldBeEqual(p, @"fo/om");
    should([[d allKeys] count] == 2);
    shouldBeEqual([d arrayForKey:@"bar"], [NSArray arrayWithObject:@" ba\"z"]);
    shouldBeEqual([d arrayForKey:@"bonk"], [NSArray arrayWithObject:@"\\oof "]);

    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om; bar=\"ba\\ \\\\\\\"z\"; bar = \"\\\\\"" intoDictionary:d valueChars:nil];
    shouldBeEqual(p, @"fo/om");
    should([[d allKeys] count] == 1);
    shouldBeEqual([d arrayForKey:@"bar"], ([NSArray arrayWithObjects:@"ba \\\"z", @"\\", nil]));

    // Expected parse failure: parameter names are not supposed to be quoted-strings.
    d = [[[OFMultiValueDictionary alloc] init] autorelease];
    p = [OWHeaderDictionary parseParameterizedHeader:@"fo/om ;bar=\"ba z\"; \"bonk\" = oof;" intoDictionary:d valueChars:nil];
    shouldBeEqual([d allKeys], [NSArray arrayWithObject:@"bar"]);
    shouldBeEqual([d arrayForKey:@"bar"], ([NSArray arrayWithObjects:@"ba z", nil]));
}

- (void)testParameterizedValueFormatting
{
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"bar"], @"foo=bar");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"b ar"], @"foo=\"b ar\"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"bar\""], @"foo=\"bar\\\"\"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@""], @"foo=\"\"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"\\"], @"foo=\"\\\\\"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@" "], @"foo=\" \"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@" ba\\"], @"foo=\" ba\\\\\"");
    shouldBeEqual([OWHeaderDictionary formatHeaderParameter:@"foo" value:@"ab "], @"foo=\"ab \"");
}

- (void)testScannerBehavior
{
    NSScanner *s;
    NSString *scannedValue;
    
    // NSScanner's behavior in some cases is undocumented or vague. We verify here that it's behaving the way we expect.

    s = [NSScanner scannerWithString:@"foo"];
    should([s scanUpToString:@"f" intoString:NULL] == NO); // this one is documented clearly

    // What happens if you scanUpToString where the string is not found? Answer: scanner goes to the end of the string and leaves its scanLocation there.
    should([s scanUpToString:@"zz" intoString:&scannedValue] == YES);
    shouldBeEqual(scannedValue, @"foo");
    should([s scanLocation] == 3);
    should([s isAtEnd]);

    s = [NSScanner scannerWithString:@"bar"];
    should([s scanUpToString:@"r" intoString:&scannedValue] == YES);
    shouldBeEqual(scannedValue, @"ba");
    should([s scanLocation] == 2);
    should(![s isAtEnd]);
    should([s scanString:@"r" intoString:NULL] == YES);
    should([s scanLocation] == 3);
    should([s isAtEnd]);
    should([s scanUpToString:@"r" intoString:&scannedValue] == NO);
    should([s scanLocation] == 3);
    should([s isAtEnd]);
}

- (void)testHeaderSplitting
{
    shouldBeEqual([OWHeaderDictionary splitHeaderValues:[NSArray array]], [NSArray array]);
    shouldBeEqual([OWHeaderDictionary splitHeaderValues:[NSArray arrayWithObject:@"foo,bar"]], ([NSArray arrayWithObjects:@"foo", @"bar", nil]));
    shouldBeEqual([OWHeaderDictionary splitHeaderValues:[NSArray arrayWithObject:@"text/foo;charset=\"blah\", text/bar;q=0.3,text/baz; stupidParam=\"Oh, what a good boy am I\""]], ([NSArray arrayWithObjects:@"text/foo;charset=\"blah\"", @" text/bar;q=0.3", @"text/baz; stupidParam=\"Oh, what a good boy am I\"", nil]));
}

@end

