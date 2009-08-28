// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFRegularExpression.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFRegexpTests : OFTestCase
{
}

@end

#define re_match(regex, text, matchText, loc, len) \
	do { \
		OFRegularExpression *rx = [[OFRegularExpression alloc] initWithString:(regex)]; \
		OFRegularExpressionMatch *match = [(rx) matchInString:(text)]; \
		should(match != nil); \
                if (match) { \
                    should1(NSEqualRanges([match matchRange], (NSRange){(loc),(len)}), \
                    ([NSString stringWithFormat:@"Got match range={%d,%d}, should be range={%d,%d}", \
                                                                            [match matchRange].location, [match matchRange].length, (loc), (len)])); \
                                                                            shouldBeEqual([match matchString], (matchText)); \
                } \
		[rx release]; \
	} while (0)

#define re_no_match(regex, text) \
	do { \
		OFRegularExpression *rx = [[OFRegularExpression alloc] initWithString:(regex)]; \
		OFRegularExpressionMatch *match = [rx matchInString:text]; \
		should(match == nil); \
		[rx release]; \
	} while (0)

#define re_equiv(re1, re2) \
	do { \
		OFRegularExpression *rx1 = [[OFRegularExpression alloc] initWithString:re1]; \
		OFRegularExpression *rx2 = [[OFRegularExpression alloc] initWithString:re2]; \
		should([rx1 description] != nil); \
		should([rx2 description] != nil); \
		shouldBeEqual([rx1 description], [rx2 description]); \
		[rx1 release]; \
		[rx2 release]; \
	} while (0);

#define re_bad_regex(regex) \
	do { \
		OFRegularExpression * re = [[OFRegularExpression alloc] initWithString:(regex)]; \
		shouldBeEqual(nil, re); \
		[re release]; \
	} while (0)

@implementation OFRegexpTests

- (void)testSubexpressions
{
    OFRegularExpression *rx;
    OFRegularExpressionMatch *match;

    rx = [[OFRegularExpression alloc] initWithString:@"b(a*)(c*)b"];
    should([rx subexpressionCount] == 2);

    match = [rx matchInString:@"bb"];
    should(match != nil);
    shouldBeEqual(@"", [match subexpressionAtIndex:0]);
    shouldBeEqual(@"", [match subexpressionAtIndex:1]);
    shouldBeEqual(@"bb", [match matchString]);

    match = [rx matchInString:@" bcccb"];
    should(match != nil);
    shouldBeEqual([match subexpressionAtIndex:0], @"");
    shouldBeEqual([match subexpressionAtIndex:1], @"ccc");
    shouldBeEqual([match matchString], @"bcccb");

    match = [rx matchInString:@" baaacbaab  "];
    should(match != nil);
    shouldBeEqual([match subexpressionAtIndex:0], @"aaa");
    shouldBeEqual([match subexpressionAtIndex:1], @"c");
    shouldBeEqual([match matchString], @"baaacb");

    match = [rx matchInString:@" baaacabaab  "];
    should(match != nil);
    shouldBeEqual(@"baab", [match matchString]);

    match = [rx matchInString:@" baaacabcaab  "];
    should(match == nil);

    [rx release];

    rx = [[OFRegularExpression alloc] initWithString:@"a(fo+)?b"];
    should([rx subexpressionCount] == 1);

    match = [rx matchInString:@"afb"];
    should(match == nil);

    match = [rx matchInString:@"abb"];
    should(match != nil);
    shouldBeEqual([match subexpressionAtIndex:0], nil);
    shouldBeEqual([match matchString], @"ab");

    match = [rx matchInString:@"aafooobb"];
    should(match != nil);
    shouldBeEqual([match subexpressionAtIndex:0], @"fooo");
    shouldBeEqual([match matchString], @"afooob");

    [rx release];

    rx = [[OFRegularExpression alloc] initWithString:@"b( (a))?"];
    should([rx subexpressionCount] == 2);

    match = [rx matchInString:@"b a"];
    should(match != nil);

    shouldBeEqual([match subexpressionAtIndex:1], @"a");
    shouldBeEqual([match subexpressionAtIndex:0], @" a");
    shouldBeEqual([match matchString], @"b a");

    match = [match nextMatch];
    should(match == nil);

    match = [rx matchInString:@"a b a b"];
    should(match != nil);

    shouldBeEqual([match subexpressionAtIndex:1], @"a");
    shouldBeEqual([match subexpressionAtIndex:0], @" a");
    shouldBeEqual([match matchString], @"b a");

    match = [match nextMatch];
    should(match != nil);

    shouldBeEqual([match subexpressionAtIndex:1], nil);
    shouldBeEqual([match subexpressionAtIndex:0], nil);
    shouldBeEqual([match matchString], @"b");

    match = [match nextMatch];
    should(match == nil);
    
    [rx release];
}

- (void)testFooPlus
{
    NSString *re = @"foo+";

    re_match(re, @"barfoo", @"foo", 3, 3);
    re_match(re, @"barfooo", @"fooo", 3, 4);
    re_match(re, @"fofoo", @"foo", 2, 3);
    re_match(re, @"fofoobar", @"foo", 2, 3);
    re_match(re, @"fofooo", @"fooo", 2, 4);
    re_match(re, @"fofooobar", @"fooo", 2, 4);
    re_match(re, @"foo", @"foo", 0, 3);
    re_match(re, @"foobar", @"foo", 0, 3);
    re_match(re, @"fooo", @"fooo", 0, 4);
    re_match(re, @"fooobar", @"fooo", 0, 4);
    re_no_match(re, @"barfo");
    re_no_match(re, @"foboar");
    re_no_match(re, @"fofo");
    re_no_match(re, @"fofobooar");
}

- (void)testFoPlus
{
    NSString *re = @"fo+";

    re_match(re, @"ffoofofooo", @"foo", 1, 3);
    re_match(re, @"foofoofooo", @"foo", 0, 3);
    re_match(re, @"foooooo", @"foooooo", 0, 7);
    re_match(re, @"offfofofooo", @"fo", 3, 2);
    re_match(re, @"offoofofooo", @"foo", 2, 3);
}

- (void)testFoPlusQ
{
    NSString *re = @"fo+?";

    re_match(re, @"ffoofofooo", @"fo", 1, 2);
    re_match(re, @"foofoofooo", @"fo", 0, 2);
    re_match(re, @"foooooo", @"fo", 0, 2);
    re_match(re, @"offfofofooo", @"fo", 3, 2);
    re_match(re, @"offoofofooo", @"fo", 2, 2);
}

- (void)testBackslashW
{
	NSString * re1 = @"\\w+";
	re_match(re1, @"abc",     @"abc", 0, 3);
	re_match(re1, @"ABC",     @"ABC", 0, 3);
	re_match(re1, @"123",     @"123", 0, 3);
	re_match(re1, @"aB3_",    @"aB3_", 0, 4);
	re_match(re1, @"  abc  ", @"abc", 2, 3);
	
	re_no_match(re1, @"    ");
}

- (void)testCharClass
{
	NSString * re1 = @"[a-zA-Z0-9_]+";
	re_match(re1, @"abc",     @"abc", 0, 3);
	re_match(re1, @"ABC",     @"ABC", 0, 3);
	re_match(re1, @"123",     @"123", 0, 3);
	re_match(re1, @"aB3_",    @"aB3_", 0, 4);
	re_match(re1, @"  abc  ", @"abc", 2, 3);
	re_no_match(re1, @"    ");
}

- (void)testCharClassBackslashEquivalence
{
	re_equiv(@"\\w",  @"[a-zA-Z0-9_]");
	re_equiv(@"\\W",  @"[^a-zA-Z0-9_]");
	re_equiv(@"\\d",  @"[0-9]");
	re_equiv(@"\\D",  @"[^0-9]");
	re_equiv(@"\\s",  @"[ \t\n\r]");
	re_equiv(@"\\S",  @"[^ \t\n\r]");
	re_equiv(@"[-a-z]", @"[-a-z]");
	re_equiv(@"[a-z-]", @"[a-z-]");
	
	// edge cases:
	re_equiv(@"\\w+", @"[a-zA-Z0-9_]+"); // modifiers
	re_equiv(@"\\w*", @"[a-zA-Z0-9_]*");
	re_equiv(@"\\w?", @"[a-zA-Z0-9_]?");
}

- (void)testBadRegexp
{
	re_bad_regex(@"[a-");
	re_bad_regex(@"[a-z");
}

- (void)testReplace
{
	shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionString:@"^ +" withString:@"X"], @"Xgood stuff    ");
	shouldBeEqual([@"    good stuff.    " stringByReplacingAllOccurrencesOfRegularExpressionString:@"\\.? +$" withString:@"X"], @"    good stuffX");
	shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionString:@"\\.? +$" withString:@"X"], @"    good stuffX");
	shouldBeEqual([@"    goodstuff    " stringByReplacingAllOccurrencesOfRegularExpressionString:@"^ +| +$" withString:@"X"], @"XgoodstuffX");
	// shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionString:@"^ +| +$" withString:@"X"], @"Xgood stuffX"); // TODO: Uh oh, this currently turns into @"XgoodXstuffX"!  See <bug://bugs/40611> (OFRegularExpression bug: anchored space in an expression can incorrectly match an unanchored space in the target).
}

@end

