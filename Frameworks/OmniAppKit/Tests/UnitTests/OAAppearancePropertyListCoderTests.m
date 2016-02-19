// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>

RCS_ID("$Id$")

#import "OAAppearanceTestBaseline.h"

#import <OmniAppKit/OAAppearancePropertyListCoder.h>
#import "OAAppearancePropertyListCoder-Internal.h"

OB_REQUIRE_ARC;

@interface OAAppearancePropertyListCoderTests : XCTestCase
@property (nonatomic, strong) OAAppearanceTestBaseline *appearance;
@property (nonatomic, strong) OAAppearanceTestSubclass1 *subappearance1;
@property (nonatomic, strong) OAAppearanceTestSubclass2 *subappearance2;

@property (nonatomic, strong) OAAppearancePropertyListCoder *appearanceCoder;
@property (nonatomic, strong) OAAppearancePropertyListCoder *subappearance1Coder;
@property (nonatomic, strong) OAAppearancePropertyListCoder *subappearance2Coder;

@property (nonatomic, strong) OAAppearancePropertyListClassKeypathExtractor *appearanceKeypathExtractor;
@property (nonatomic, strong) OAAppearancePropertyListClassKeypathExtractor *subappearance1KeypathExtractor;
@property (nonatomic, strong) OAAppearancePropertyListClassKeypathExtractor *subappearance2KeypathExtractor;
@end

@implementation OAAppearancePropertyListCoderTests

- (void)setUp {
    [super setUp];

    self.appearance = [OAAppearanceTestBaseline appearance];
    self.subappearance1 = [OAAppearanceTestSubclass1 appearance];
    self.subappearance2 = [OAAppearanceTestSubclass2 appearance];
    
    self.appearanceCoder = [[OAAppearancePropertyListCoder alloc] initWithCodeable:self.appearance];
    self.subappearance1Coder = [[OAAppearancePropertyListCoder alloc] initWithCodeable:self.subappearance1];
    self.subappearance2Coder = [[OAAppearancePropertyListCoder alloc] initWithCodeable:self.subappearance2];
    
    self.appearanceKeypathExtractor = self.appearanceCoder.keyExtractor;
    self.subappearance1KeypathExtractor = self.subappearance1Coder.keyExtractor;
    self.subappearance2KeypathExtractor = self.subappearance2Coder.keyExtractor;
}

- (void)tearDown {
    self.appearance = nil;
    self.subappearance1 = nil;
    self.subappearance2 = nil;
    
    self.appearanceCoder = nil;
    self.subappearance1Coder = nil;
    self.subappearance2Coder = nil;
    
    self.appearanceKeypathExtractor = nil;
    self.subappearance1KeypathExtractor = nil;
    self.subappearance2KeypathExtractor = nil;
    
    [super tearDown];
}

- (void)testInstantiation {
    XCTAssertNotNil(self.appearance);
    XCTAssertNotNil(self.subappearance1);
    XCTAssertNotNil(self.subappearance2);

    XCTAssertNotNil(self.appearanceCoder);
    XCTAssertNotNil(self.subappearance1Coder);
    XCTAssertNotNil(self.subappearance2Coder);
    
    XCTAssertNotNil(self.appearanceKeypathExtractor);
    XCTAssertNotNil(self.subappearance1KeypathExtractor);
    XCTAssertNotNil(self.subappearance2KeypathExtractor);
}

- (void)testKeyPaths;
{
    NSMutableSet *expectedResult = [NSMutableSet setWithArray:@[@"TopLevelFloat", @"Color", @"EdgeInsets", @"OverriddenFloat", @"Nested.Float"]];
    NSSet *appearanceResult = [self.appearanceKeypathExtractor _keyPaths];
    XCTAssertEqualObjects(expectedResult, appearanceResult);
    
    NSSet *emptySet = [NSSet new];
    NSSet *subappearance1Result = [self.subappearance1KeypathExtractor _keyPaths];
    XCTAssertEqualObjects(emptySet, subappearance1Result);
    
    [expectedResult addObject:@"SpecialLeafyString"];
    NSSet *subappearance2Result = [self.subappearance2KeypathExtractor _keyPaths];
    XCTAssertEqualObjects(expectedResult, subappearance2Result);
}

- (void)testLocalDynamicPropertyNames;
{
    NSSet *expectedResult = [NSSet setWithArray:@[@"TopLevelFloat", @"Color", @"EdgeInsets", @"OverriddenFloat"]];
    NSSet *appearanceResult = [self.appearanceKeypathExtractor _localDynamicPropertyNames];
    XCTAssertEqualObjects(expectedResult, appearanceResult);

    NSSet *emptySet = [NSSet new];
    NSSet *subappearance1Result = [self.subappearance1KeypathExtractor _localDynamicPropertyNames];
    XCTAssertEqualObjects(emptySet, subappearance1Result);
    
    expectedResult = [NSSet setWithArray:@[@"SpecialLeafyString"]];
    NSSet *subappearance2Result = [self.subappearance2KeypathExtractor _localDynamicPropertyNames];
    XCTAssertEqualObjects(expectedResult, subappearance2Result);
}

- (void)testLocalKeyPaths;
{
    NSSet *expectedResult = [NSSet setWithArray:@[@"TopLevelFloat", @"Color", @"EdgeInsets", @"OverriddenFloat", @"Nested.Float"]];

    NSSet *appearanceResult = [self.appearanceKeypathExtractor _localKeyPaths];
    XCTAssertEqualObjects(expectedResult, appearanceResult);
    
    
    NSSet *emptySet = [NSSet new];
    NSSet *subappearance1Result = [self.subappearance1KeypathExtractor _localKeyPaths];
    XCTAssertEqualObjects(emptySet, subappearance1Result);
    
    expectedResult = [NSSet setWithArray:@[@"SpecialLeafyString"]];
    NSSet *subappearance2Result = [self.subappearance2KeypathExtractor _localKeyPaths];
    XCTAssertEqualObjects(expectedResult, subappearance2Result);
}

- (void)testInheritedKeyPaths;
{
    NSSet *emptySet = [NSSet new];
    NSSet *appearanceResult = [self.appearanceKeypathExtractor _inheritedKeyPaths];
    XCTAssertEqualObjects(emptySet, appearanceResult);
    
    NSSet *subappearance1Result = [self.subappearance1KeypathExtractor _inheritedKeyPaths];
    XCTAssertEqualObjects(emptySet, subappearance1Result);
    
    // Only OAAppearanceTestSubclass2 include(s)SuperclassKeyPaths
    NSSet *expectedResult = [NSSet setWithArray:@[@"TopLevelFloat", @"Color", @"EdgeInsets", @"OverriddenFloat", @"Nested.Float"]];
    NSSet *subappearance2Result = [self.subappearance2KeypathExtractor _inheritedKeyPaths];
    XCTAssertEqualObjects(expectedResult, subappearance2Result);
}

- (void)testPropertyList;
{
    NSDictionary *expectedPlist = @{
                                    @"string": @"forsooth",
                                    @"cgFloat": @((CGFloat)1.3),
                                    @"float_": @((float)1.23),
                                    @"double_": @((double)2.245),
                                    @"integer": @((NSInteger)3),
                                    @"bool_": @(YES),
                                    @"size": @{@"width": @(10), @"height": @(20)},
                                    @"insets": @{@"top": @(1), @"left": @(2), @"bottom": @(3), @"right": @(4)},
                                    @"colorWithWhite": @{@"w": @(0.5), @"a": @(0.25)},
                                    @"colorWithRGB": @{@"r": @(0.125), @"g": @(0.25), @"b": @(0.5), @"a": @(0.75)},
                                    @"colorWithHSB": @{@"h": @(0.125), @"s": @(0.25), @"b": @(0.5), @"a": @(0.75)},
                                    @"imageWithString": @"NSApplicationIcon",
                                    @"imageWithName": @{@"name": @"NSApplicationIcon"},
                                    @"imageWithNameAndBundle": @{@"name": @"testImage", @"bundle": @"self"},
                                    @"imageWithNameAndColor": @{@"name": @"NSApplicationIcon", @"color": @"colorWithRGB"},
                                    @"dictionary": @{@"a": @"apple", @"b": @"banana"},
                                    @"Parent": @{@"Child1": @((NSInteger)213), @"Child2": @((NSInteger)601), },
                                    @"testAlias": @((NSInteger)213),
                                    };
    OAAppearancePropertyListCoder *coder = [[OAAppearancePropertyListCoder alloc] initWithCodeable:[OAAppearanceTestEncodingCoverage appearance]];
    NSDictionary *plist = coder.propertyList;

    // Compare by key so mismatches are easier to find
    XCTAssertEqualObjects([NSSet setWithArray:expectedPlist.allKeys], [NSSet setWithArray:plist.allKeys], @"expect key sets to match");
    for (NSString *key in expectedPlist.allKeys) {
        XCTAssertEqualObjects(expectedPlist[key], plist[key], @"Expect values for keys to match");
    }
    
    // Also compare the whole dictionary to any bugs in the by-key assertions don't sneak through
    XCTAssertEqualObjects(expectedPlist, plist);
}

- (void)testPropertyList2;
{
    NSDictionary *expectedPlist = @{
                                    @"TopLevelFloat": @(1),
                                    @"Color": @{@"r": @(0.42), @"g": @(0.42), @"b": @(0.42), @"a": @(1)},
                                    @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                                    @"OverriddenFloat": @(-1),
                                    @"Nested": @{@"Float": @(1)},
                                    };
    NSDictionary *plist = self.appearanceCoder.propertyList;
    XCTAssertEqualObjects(expectedPlist, plist);
}

// TODO: Enabled for all when done. <bug:///126282> (Feature: Present list of any extra and missing keys to user when importing style file)
#ifdef DEBUG_curt
- (void)testInvalidKeysInPropertyList;
{
    // TODO: test. <bug:///126282> (Feature: Present list of any extra and missing keys to user when importing style file)
}

#endif
@end
