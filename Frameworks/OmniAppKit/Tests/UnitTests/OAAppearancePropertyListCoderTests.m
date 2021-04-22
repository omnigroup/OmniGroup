// Copyright 2016-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>

RCS_ID("$Id$")

#import "OAAppearanceTestBaseline.h"

#import <OmniAppKit/OAAppearancePropertyListCoder.h>
#import "OAAppearance-Internal.h"
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
                                    @"colorWithWhite": @{@"space": @"gg22", @"w": @(0.5), @"a": @(0.25)},
                                    @"colorWithRGB": @{@"space": @"srgb", @"r": @(0.125), @"g": @(0.25), @"b": @(0.5), @"a": @(0.75)},
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
                                    @"Color": @{@"space": @"srgb", @"r": @(0.5), @"g": @(0.25), @"b": @(0.125), @"a": @(1)},
                                    @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                                    @"OverriddenFloat": @(-1),
                                    @"Nested": @{@"Float": @(1)},
                                    };
    NSDictionary *plist = self.appearanceCoder.propertyList;
    XCTAssertEqualObjects(expectedPlist, plist);
}

- (void)testPathComponentsTree1;
{
    NSArray *input = @[@"A", @"B"];
    NSDictionary *result = [OAAppearancePropertyListCoder _pathComponentsTreeFromKeyPaths:input];
    NSDictionary *expectedResult = @{@"A": @{}, @"B": @{}};
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testPathComponentsTree2;
{
    NSArray *input = @[@"A", @"A.B"];
    NSDictionary *result = [OAAppearancePropertyListCoder _pathComponentsTreeFromKeyPaths:input];
    NSDictionary *expectedResult = @{@"A": @{@"B": @{}}};
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testPathComponentsTree3;
{
    NSArray *input = @[@"A.B", @"A"];
    NSDictionary *result = [OAAppearancePropertyListCoder _pathComponentsTreeFromKeyPaths:input];
    NSDictionary *expectedResult = @{@"A": @{@"B": @{}}};
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testPathComponentsTree4;
{
    NSArray *input = @[@"A.B", @"A", @"B"];
    NSDictionary *result = [OAAppearancePropertyListCoder _pathComponentsTreeFromKeyPaths:input];
    NSDictionary *expectedResult = @{@"A": @{@"B": @{}}, @"B": @{}};
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testValidatePropertyListValuesWithError1
{
    NSError *error = nil;
    BOOL success = [self.appearanceCoder validatePropertyListValuesWithError:&error];
    XCTAssert(success);
}

- (void)testValidatePropertyListValuesWithError2
{
    NSBundle *bundle = [NSBundle bundleForClass:[OAAppearanceTestInvalidPlist class]];
    NSURL *plistURL = [bundle URLForResource:@"OAAppearanceTestInvalidPlist" withExtension:@"plist"];
    NSURL *plistDirectory = [plistURL URLByDeletingLastPathComponent];
    OAAppearanceTestInvalidPlist *appearance = [OAAppearanceTestInvalidPlist appearanceForValidatingPropertyListInDirectory:plistDirectory forClass:[OAAppearanceTestInvalidPlist class]];
    OAAppearancePropertyListCoder *coder = [[OAAppearancePropertyListCoder alloc] initWithCodeable:appearance];
    NSError *error = nil;
    
    BOOL success = [coder validatePropertyListValuesWithError:&error];
    
    XCTAssertFalse(success);
    XCTAssertEqual(error.domain, OAAppearanceErrorDomain);
    XCTAssertEqual(error.code, (NSInteger)OAAppearanceErrorCodeInvalidValueInPropertyList);
}

- (void)testInvalidKeysInPropertyList1;
{
    NSDictionary *plist = self.appearanceCoder.propertyList;
    id result = [self.appearanceCoder invalidKeysInPropertyList:plist];
    XCTAssertNil(result);
}

- (void)testInvalidKeysInPropertyList2;
{
    NSDictionary *badPlist = @{
                                    @"TopLevelFloat": @(1),
                                    @"Color": @{@"r": @(0.42), @"g": @(0.42), @"b": @(0.42), @"a": @(1)},
                                    @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                                    @"OverriddenGoat": @(-1),
                                    @"Nested": @{@"Float": @(1)},
                                    };

    NSDictionary *result = [self.appearanceCoder invalidKeysInPropertyList:badPlist];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[OAAppearanceMissingKeyKey], @[@"OverriddenFloat"]);
    XCTAssertEqualObjects(result[OAAppearanceUnknownKeyKey], @[@"OverriddenGoat"]);
}

- (void)testInvalidKeysInPropertyList3;
{
    NSDictionary *badPlist = @{
                               @"TopLevelFloat": @(1),
                               @"Color": @{@"r": @(0.42), @"g": @(0.42), @"b": @(0.42), @"a": @(1)},
                               @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                               @"OverriddenFloat": @(-1),
                               @"Nested": @{@"Goat": @(1)},
                               };
    
    NSDictionary *result = [self.appearanceCoder invalidKeysInPropertyList:badPlist];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[OAAppearanceMissingKeyKey], @[@"Nested.Float"]);
    XCTAssertEqualObjects(result[OAAppearanceUnknownKeyKey], @[@"Nested.Goat"]);
}

- (void)testInvalidKeysInPropertyList4;
{
    NSDictionary *badPlist = @{
                               @"TopLevelFloat": @(1),
                               @"Color": @{@"r": @(0.42), @"g": @(0.42), @"b": @(0.42), @"a": @(1)},
                               @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                               @"OverriddenFloat": @(-1),
                               @"Crested": @{@"Goat": @(1)},
                               };
    
    NSDictionary *result = [self.appearanceCoder invalidKeysInPropertyList:badPlist];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[OAAppearanceMissingKeyKey], @[@"Nested"]);
    XCTAssertEqualObjects(result[OAAppearanceUnknownKeyKey], @[@"Crested"]);
}

- (void)testInvalidKeysInPropertyList5;
{
    NSDictionary *badPlist = @{
                               @"TopLevelFloat": @(1),
                               @"Color": @{@"r": @(0.42), @"g": @(0.42), @"b": @(0.42), @"a": @(1)},
                               @"EdgeInsets": @{@"top": @(42), @"left": @(42), @"bottom": @(42), @"right": @(42), },
                               @"OverriddenFloat": @(-1),
                               @"Nested": @{@"Float": @(1), @"Goat": @(2)},
                               };
    
    NSDictionary *result = [self.appearanceCoder invalidKeysInPropertyList:badPlist];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[OAAppearanceMissingKeyKey], @[]);
    XCTAssertEqualObjects(result[OAAppearanceUnknownKeyKey], @[@"Nested.Goat"]);
}


@end
