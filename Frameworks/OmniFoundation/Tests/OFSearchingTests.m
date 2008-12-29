// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFDataSearch : OFTestCase
{
}


@end

@implementation OFDataSearch

// Test cases

- (void)testContainsData
{
    NSData *txt1 = [[NSData alloc] initWithBytesNoCopy:"xymoofbarbaz" length:12 freeWhenDone:NO];
    NSData *txt2 = [[NSData alloc] initWithBytesNoCopy:"ommoonymooof" length:12 freeWhenDone:NO];
    NSData *txt3 = [[NSData alloc] initWithBytesNoCopy:"moomoomoof"   length:10 freeWhenDone:NO];
    NSData *txt4 = [[NSData alloc] initWithBytesNoCopy:"moolaflmo"    length:9 freeWhenDone:NO];

    NSData *pat1 = [[NSData alloc] initWithBytesNoCopy:"moof"   length:4 freeWhenDone:NO];
    NSData *pat2 = [[NSData alloc] initWithBytesNoCopy:"om"     length:2 freeWhenDone:NO];

#define shouldEqualRange(expr, loc, len) should1(NSEqualRanges(expr, (NSRange){loc,len}), ([NSString stringWithFormat:@"%s == %@", #expr, NSStringFromRange(expr)]))

    should([txt1 containsData:pat1]);
    shouldEqualRange([txt1 rangeOfData:pat1],  2, 4 );
    shouldnt([txt1 containsData:pat2]);
    shouldEqualRange([txt1 rangeOfData:pat2], NSNotFound, 0 );

    shouldnt([txt2 containsData:pat1]);
    shouldEqualRange([txt2 rangeOfData:pat1], NSNotFound, 0 );
    should([txt2 containsData:pat2]);
    shouldEqualRange([txt2 rangeOfData:pat2], 0, 2 );

    should([txt3 containsData:pat1]);
    shouldEqualRange([txt3 rangeOfData:pat1], 6, 4 );
    should([txt3 containsData:pat2]);
    shouldEqualRange([txt3 rangeOfData:pat2], 2, 2 );

    shouldnt([txt4 containsData:pat1]);
    shouldEqualRange([txt4 rangeOfData:pat1], NSNotFound, 0 );
    shouldnt([txt4 containsData:pat2]);
    shouldEqualRange([txt4 rangeOfData:pat2], NSNotFound, 0 );

    [txt1 release];
    [txt2 release];
    [txt3 release];
    [txt4 release];

    [pat1 release];
    [pat2 release];
}

- (void)testContainsDataInRange
{
    NSData *txt1 = [[NSData alloc] initWithBytesNoCopy:"xymoofbarbaz" length:12 freeWhenDone:NO];
    NSData *txt2 = [[NSData alloc] initWithBytesNoCopy:"ommoonymooof" length:12 freeWhenDone:NO];
    NSData *txt4 = [[NSData alloc] initWithBytesNoCopy:"moolaflmo"    length:9 freeWhenDone:NO];
    NSData *txt5 = [[NSData alloc] initWithBytesNoCopy:"om"           length:2 freeWhenDone:NO];
    
#define shouldEqualIndex(expr, ix) { NSUInteger ix_ = (expr); should1(ix_ == ix, ([NSString stringWithFormat:@"%s == %lu, expecting %lu", #expr, (unsigned long)ix_, (unsigned long)ix])); }
    
    shouldEqualIndex(([txt1 indexOfBytes:"xymoof" length:6 range:(NSRange){0, 12}]), 0);
    shouldEqualIndex(([txt1 indexOfBytes:"xymoof" length:6 range:(NSRange){1, 11}]), NSNotFound);
    shouldEqualIndex(([txt1 indexOfBytes:"xymoof" length:6 range:(NSRange){0, 6}]), 0);
    shouldEqualIndex(([txt1 indexOfBytes:"xymoof" length:6 range:(NSRange){0, 5}]), NSNotFound);
    
    shouldEqualIndex(([txt5 indexOfBytes:"om" length:2 range:(NSRange){0,2}]), 0);
    shouldEqualIndex(([txt5 indexOfBytes:"om" length:3 range:(NSRange){0,2}]), NSNotFound);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:3 range:(NSRange){0,9}]), NSNotFound);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:2 range:(NSRange){0,9}]), 0);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:2 range:(NSRange){1,8}]), 7);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:2 range:(NSRange){7,2}]), 7);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:2 range:(NSRange){8,1}]), NSNotFound);
    shouldEqualIndex(([txt4 indexOfBytes:"mo" length:2 range:(NSRange){9,0}]), NSNotFound);
    
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){0,12}]), 3);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){3,9}]), 3);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){4,8}]), 8);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){8,4}]), 8);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){9,3}]), 9);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){10,2}]), NSNotFound);
    shouldEqualIndex(([txt2 indexOfBytes:"oo" length:2 range:(NSRange){12,0}]), NSNotFound);
    
    shouldEqualIndex(([[NSData data] indexOfBytes:"x" length:1 range:(NSRange){0,0}]), NSNotFound);
    shouldEqualIndex(([[NSData data] indexOfBytes:"x" length:0 range:(NSRange){0,0}]), 0);
    shouldEqualIndex(([txt1 indexOfBytes:"f" length:0 range:(NSRange){3,6}]), 3);
    shouldEqualIndex(([txt1 indexOfBytes:"f" length:1 range:(NSRange){3,6}]), 5);
    
    shouldRaise(([[NSData data] indexOfBytes:"x" length:0 range:(NSRange){0,1}]));
    shouldRaise(([[NSData data] indexOfBytes:"x" length:0 range:(NSRange){1,0}]));
    
    [txt1 release];
    [txt2 release];
    [txt4 release];
    [txt5 release];
}


@end

@interface OFStringSplitting : OFTestCase
{
}


@end

@implementation OFStringSplitting

// Test cases

- (void)testLimitedSplit
{
    NSArray *foobar = [NSArray arrayWithObject:@"foo bar"];
    NSArray *foo_bar = [NSArray arrayWithObjects:@"foo", @"bar", nil];
    
    NSArray *foobarx = [NSArray arrayWithObjects:@"foo bar ", nil];
    NSArray *foo_barx = [NSArray arrayWithObjects:@"foo", @"bar ", nil];
    NSArray *foo_bar_ = [NSArray arrayWithObjects:@"foo", @"bar", @"", nil];

    shouldBeEqual([@"foo bar" componentsSeparatedByString:@" " maximum:4], foo_bar);
    shouldBeEqual([@"foo bar" componentsSeparatedByString:@" " maximum:3], foo_bar);
    shouldBeEqual([@"foo bar" componentsSeparatedByString:@" " maximum:2], foo_bar);
    shouldBeEqual([@"foo bar" componentsSeparatedByString:@" " maximum:1], foobar);

    shouldBeEqual([@"foo bar " componentsSeparatedByString:@" " maximum:4], foo_bar_);
    shouldBeEqual([@"foo bar " componentsSeparatedByString:@" " maximum:3], foo_bar_);
    shouldBeEqual([@"foo bar " componentsSeparatedByString:@" " maximum:2], foo_barx);
    shouldBeEqual([@"foo bar " componentsSeparatedByString:@" " maximum:1], foobarx);

    shouldBeEqual([@"oofoo bar" componentsSeparatedByString:@"oo" maximum:3],
                  ([NSArray arrayWithObjects:@"", @"f", @" bar", nil]));
    shouldBeEqual([@"oofoo bar" componentsSeparatedByString:@"oo" maximum:2],
                  ([NSArray arrayWithObjects:@"", @"foo bar", nil]));

    shouldBeEqual([@"foo bar " componentsSeparatedByString:@"z" maximum:3], foobarx);
    shouldBeEqual([@"foo bar " componentsSeparatedByString:@"z" maximum:1], foobarx);

    shouldBeEqual([@"::::" componentsSeparatedByString:@":" maximum:6],
                  ([NSArray arrayWithObjects:@"", @"", @"", @"", @"", nil]));
    shouldBeEqual([@"::::" componentsSeparatedByString:@":" maximum:5],
                  ([NSArray arrayWithObjects:@"", @"", @"", @"", @"", nil]));
    shouldBeEqual([@"::::" componentsSeparatedByString:@":" maximum:4],
                  ([NSArray arrayWithObjects:@"", @"", @"", @":", nil]));
}

@end


