// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <SenTestingKit/SenTestingKit.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

RCS_ID("$Id$");

@interface OFDictionaryTests : SenTestCase
{
}


@end

@implementation OFDictionaryTests

// Test cases

- (void)testDictionaryWithObject
{
    NSDictionary *a, *b, *c, *d;
    
    a = [NSDictionary dictionary];
    b = [a dictionaryWithObject:@"Foo" forKey:@"Bar"];
    should([b count] == 1);
    shouldBeEqual([b objectForKey:@"Bar"], @"Foo");
    
    c = [b dictionaryWithObject:nil forKey:@"Pizzaz"];
    shouldBeEqual(b, c);
    
    d = [c dictionaryWithObject:nil forKey:@"Bar"];
    should([d count] == 0);
    shouldBeEqual(a, d);
    
    d = [c dictionaryWithObject:@"linguini" forKey:@"Bar"];
    shouldBeEqual([b allKeys], [d allKeys]);
    shouldBeEqual([d objectForKey:@"Bar"], @"linguini");
    should([d count] == 1);
    
    c = [b dictionaryWithObject:@"linguini" forKey:@"Bar"];
    shouldBeEqual(c, d);
    
    c = [b dictionaryWithObject:@"alfredo" forKey:@"Spork"];
    should([c count] == 2);
}

- (void)testDictionaryWithObjectIdentity
{
    NSDictionary *b, *c;
    NSMutableDictionary *a;
    
    a = [NSDictionary dictionary];
    b = [a dictionaryWithObject:@"Foo" forKey:@"Bar"];
    should([b count] == 1);
    shouldBeEqual([b objectForKey:@"Bar"], @"Foo");
    
    c = [b dictionaryWithObject:nil forKey:@"Pizzaz"];
    shouldBeEqual(b, c);
    should(b != c);
    
    a = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"gouda", @"Sparkly", @"havarti", @"Matte", @"cheddar", @"Pellucid", nil];
    b = [a dictionaryWithObject:@"havarti" forKey:@"Matte"];
    shouldBeEqual(a, b);
    shouldnt(a == b);
    [a setObject:@"parmesan" forKey:@"Pellucid"];
    shouldnt([a isEqual:b]);
    shouldBeEqual([b objectForKey:@"Pellucid"], @"cheddar");
    shouldBeEqual([a objectForKey:@"Pellucid"], @"parmesan");
    c = [b dictionaryWithObject:@"parmesan" forKey:@"Pellucid"];
    shouldBeEqual(a, c);
    shouldnt(a == c);
    shouldnt([a isEqual:b]);
    shouldnt([b isEqual:c]);
    [a removeAllObjects];
    c = [c dictionaryWithObject:@"cheddar" forKey:@"Pellucid"];
    shouldBeEqual(b, c);
    shouldnt(b == c);
}

- (void)testDictionaryByAdding
{
    NSDictionary *empty = [NSDictionary dictionary];
    
    shouldBeEqual([empty dictionaryByAddingObjectsFromDictionary:empty], empty);
    
    NSDictionary *cheeses = [NSDictionary dictionaryWithObjectsAndKeys:@"gouda", @"soft", @"brie", @"gooey", @"cheddar", @"firm", @"parmesan", @"hard", @"swiss", @"holey", nil];
    shouldBeEqual([empty dictionaryByAddingObjectsFromDictionary:cheeses], cheeses);
    shouldBeEqual([cheeses dictionaryByAddingObjectsFromDictionary:empty], cheeses);
    shouldBeEqual([cheeses dictionaryByAddingObjectsFromDictionary:cheeses], cheeses);
    
    NSDictionary *tofus = [NSDictionary dictionaryWithObjectsAndKeys:@"wibbly", @"soft", @"crumbly", @"firm", nil];
    shouldBeEqual([tofus dictionaryByAddingObjectsFromDictionary:cheeses], cheeses);
    shouldnt([[cheeses dictionaryByAddingObjectsFromDictionary:tofus] isEqual:cheeses]);
    shouldnt([[cheeses dictionaryByAddingObjectsFromDictionary:tofus] isEqual:tofus]);
    
    NSDictionary *wares = [NSDictionary dictionaryWithObjectsAndKeys:@"editor", @"soft", @"athena widgets", @"gooey", @"boot", @"firm", @"keyboard", @"hard", @"web browser", @"holey", nil];
    shouldBeEqual([cheeses dictionaryByAddingObjectsFromDictionary:wares], wares);
    shouldBeEqual([wares dictionaryByAddingObjectsFromDictionary:cheeses], cheeses);
    shouldBeEqual([[tofus dictionaryByAddingObjectsFromDictionary:wares] allKeys],
                  [[tofus dictionaryByAddingObjectsFromDictionary:cheeses] allKeys]);
    shouldnt([[cheeses dictionaryByAddingObjectsFromDictionary:tofus] isEqual:[wares dictionaryByAddingObjectsFromDictionary:tofus]]);
    
    NSDictionary *breads = [NSDictionary dictionaryWithObjectsAndKeys:@"dough", @"gooey", @"bagel", @"holey", nil];
    shouldBeEqual([breads dictionaryByAddingObjectsFromDictionary:tofus], [tofus dictionaryByAddingObjectsFromDictionary:breads]);
    should([[breads dictionaryByAddingObjectsFromDictionary:tofus] count] == 4);
}

@end
