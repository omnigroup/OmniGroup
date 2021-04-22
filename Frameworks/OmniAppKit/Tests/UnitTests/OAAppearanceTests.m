// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>
#import "OAAppearanceTestBaseline.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFBinding.h> // for OFKeyPathForKeys
#import <OmniAppKit/OAAppearance.h>
#import "OAAppearance-Internal.h"

const CGFloat OAAppearanceTestFloatAccuracy = 1e-6;

@interface _NotificationCounter : NSObject
@property (nonatomic, strong) NSMutableDictionary *nameMap;
@property (nonatomic, strong) NSCountedSet *notificationCounts;
- (void)registerForObject:(id)object name:(NSString *)name;
@end

@interface OAAppearanceTests : XCTestCase
@end

@implementation OAAppearanceTests

- (void)testAppearance;
{
    // If this test fails, the rest are unlikely to succeed – we need to be able to get an appearance instance before asking it for any values
    XCTAssertNotNil([OAAppearanceTestBaseline appearance], @"Expected to be able to find an appearance instance for our test class");
}

#pragma mark Lookup tests

#define OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(keyPath, lookupDescription) do{ \
    CGFloat result = 0.0f; \
    NSString *lookupDescription_ = (lookupDescription); \
    XCTAssertNoThrow(result = [[OAAppearanceTestBaseline appearance] CGFloatForKeyPath:(keyPath)], @"Expected to be able to look up %@", lookupDescription_); \
    XCTAssertNotEqualWithAccuracy(result, 0.0f, OAAppearanceTestFloatAccuracy, @"Expected a non-zero float result when looking up %@", lookupDescription_); \
} while(0);

#define OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_LOOKUP(key, lookupDescription) do{ \
CGFloat result = 0.0f; \
NSString *lookupDescription_ = [(lookupDescription) stringByAppendingString:@", using valueForKey:"]; \
XCTAssertNoThrow(result = ((NSNumber *)[[OAAppearanceTestBaseline appearance] valueForKey:(key)]).cgFloatValue, @"Expected to be able to look up %@", lookupDescription_); \
XCTAssertNotEqualWithAccuracy(result, 0.0f, OAAppearanceTestFloatAccuracy, @"Expected a non-zero float result when looking up %@", lookupDescription_); \
} while(0);

#define OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(keyPath, lookupDescription) do{ \
CGFloat result = 0.0f; \
NSString *lookupDescription_ = [(lookupDescription) stringByAppendingString:@", using valueForKeyPath:"]; \
XCTAssertNoThrow(result = ((NSNumber *)[[OAAppearanceTestBaseline appearance] valueForKeyPath:(keyPath)]).cgFloatValue, @"Expected to be able to look up %@", lookupDescription_); \
XCTAssertNotEqualWithAccuracy(result, 0.0f, OAAppearanceTestFloatAccuracy, @"Expected a non-zero float result when looking up %@", lookupDescription_); \
} while(0);


- (void)testTopLevelDirectLookup;
{
    OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(OAAppearanceTestBaselineTopLevelLeafKey, @"a top-level direct value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_LOOKUP(OAAppearanceTestBaselineTopLevelLeafKey, @"a top-level direct value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(OAAppearanceTestBaselineTopLevelLeafKey, @"a top-level direct value");
}

- (void)testNestedDirectLookup;
{
    NSString *keyPath = OFKeyPathForKeys(OAAppearanceTestBaselineTopLevelContainerKey, OAAppearanceTestBaselineNestedLeafKey, nil);
    OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(keyPath, @"a nested direct value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(keyPath, @"a nested direct value");
}

- (void)testTopLevelAliasLookup;
{
    OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(OAAppearanceTestBaselineLeafAliasKey, @"a top-level aliased value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_LOOKUP(OAAppearanceTestBaselineLeafAliasKey, @"a top-level aliased value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(OAAppearanceTestBaselineLeafAliasKey, @"a top-level aliased value");
}

- (void)testNestedAliasLookup;
{
    NSString *keyPath = OFKeyPathForKeys(OAAppearanceTestBaselineTopLevelContainerKey, OAAppearanceTestBaselineLeafAliasKey, nil);
    OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(keyPath, @"a nested aliased value");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(keyPath, @"a nested aliased value");
}

- (void)testNestedContainerAliasLookup;
{
    NSString *keyPath = OFKeyPathForKeys(OAAppearanceTestBaselineTopLevelContainerKey, OAAppearanceTestBaselineContainerAliasKey, OAAppearanceTestBaselineNestedLeafKey, nil);
    OA_APPEARANCE_ASSERT_FLOAT_LOOKUP(keyPath, @"a nested value through an aliased container");
    OA_APPEARANCE_ASSERT_FLOAT_VALUE_FOR_KEY_PATH_LOOKUP(keyPath, @"a nested value through an aliased container");
}

- (void)_subclassTestForClassName:(NSString *)className expectedValue:(CGFloat) expectedValue;
{
    CGFloat result = 0.0f;
    OAAppearanceTestBaseline *appearance = [NSClassFromString(className) appearance];

    XCTAssertNoThrow(result = appearance.SubclassFloat, @"Expected to be able to look up SubclassFloat on %@", className);
    XCTAssertEqualWithAccuracy(result, expectedValue, OAAppearanceTestFloatAccuracy, @"Wrong value looking up SubclassFloat on %@", className);
}

- (void)testSubclassDirectLookup;
{
    [self _subclassTestForClassName:@"OAAppearanceTestSubclass2" expectedValue:2.0];
    [self _subclassTestForClassName:@"OAAppearanceTestSubclass1" expectedValue:1.0];
}

- (void)_testOverriddenDynamicPropertyForClassName:(NSString *)className expectedValue:(CGFloat)expectedValue
{
    CGFloat result = 0.0f;
    OAAppearanceTestBaseline *appearance = [NSClassFromString(className) appearance];
    
    XCTAssertNoThrow(result = appearance.OverriddenFloat, @"Expected to be able to look up OverriddenFloat on %@", className);
    XCTAssertEqualWithAccuracy(result, expectedValue, OAAppearanceTestFloatAccuracy, @"Wrong value looking up OverriddenFloat on %@", className);
}

- (void)testOverriddenDynamicProperty
{
    // The order of the calls here matters. We want to provoke reification of the OverriddenFloat accessor method for OAAppearanceTestBaseline before accessing the property on one of the subclasses. We also test accessing the property on the other subclass first to detect regressions in the other direction.
    [self _testOverriddenDynamicPropertyForClassName:@"OAAppearanceTestSubclass1" expectedValue:10.0];
    [self _testOverriddenDynamicPropertyForClassName:@"OAAppearanceTestBaseline" expectedValue:-1.0];
    [self _testOverriddenDynamicPropertyForClassName:@"OAAppearanceTestSubclass2" expectedValue:20.0];
}

- (void)testInvalidation
{
    _NotificationCounter *counter = [_NotificationCounter new];
    NSArray *classNames = @[@"OAAppearanceTestSubclass1", @"OAAppearanceTestBaseline", @"OAAppearanceTestSubclass2"];
    
    // Register for notifications and ensure that all singleton instances have been instantiated
    for (NSString *className in classNames) {
        OAAppearance *appearance = [NSClassFromString(className) appearance];
        XCTAssertEqual((NSInteger)appearance.cacheInvalidationCount, 1, @"invalidation count for %@", className); // starts at 1
        [counter registerForObject:appearance name:className];
    }
    
    // Should invalidate all
    [[OAAppearanceTestBaseline appearance] invalidateCachedValues];
    for (NSString *className in classNames) {
        OAAppearance *appearance = [NSClassFromString(className) appearance];
        XCTAssertEqual((NSInteger)[counter.notificationCounts countForObject:className], 1, @"notification count for %@", className);
        XCTAssertEqual((NSInteger)appearance.cacheInvalidationCount, 2, @"invalidation count for %@", className); // should have bumped to 2
    }
    
    // Should also invalidate all
    OAAppearanceSetUserOverrideFolder(@"nonExistantFolder");
    for (NSString *className in classNames) {
        OAAppearance *appearance = [NSClassFromString(className) appearance];
        XCTAssertEqual((NSInteger)[counter.notificationCounts countForObject:className], 2, @"notification count for %@", className);
        XCTAssertEqual((NSInteger)appearance.cacheInvalidationCount, 3, @"invalidation count for %@", className); // should have bumped to 3
    }
    
    // After invalidating a single leaf class, only its counts should have changed
    OAAppearanceTestSubclass1 *subclass1Appearance = [OAAppearanceTestSubclass1 appearance];
    [subclass1Appearance invalidateCachedValues];
    XCTAssertEqual((NSInteger)[counter.notificationCounts countForObject:@"OAAppearanceTestSubclass1"], 3);
    XCTAssertEqual((NSInteger)subclass1Appearance.cacheInvalidationCount, 4, @"invalidation count for %@", @"OAAppearanceTestSubclass1");
    for (NSString *className in classNames) {
        if ([className isEqualToString:@"OAAppearanceTestSubclass1"]) {
            continue;
        }
        OAAppearance *appearance = [NSClassFromString(className) appearance];
        XCTAssertEqual((NSInteger)[counter.notificationCounts countForObject:className], 2, @"notification count for %@", className);
        XCTAssertEqual((NSInteger)appearance.cacheInvalidationCount, 3, @"invalidation count for %@", className); // still 2
    }
}

- (void)testAppearanceForValidatingPropertyListInDirectory
{
    NSBundle *bundle = [NSBundle bundleForClass:[OAAppearanceTestInvalidPlist class]];
    NSURL *plistURL = [bundle URLForResource:@"OAAppearanceTestInvalidPlist" withExtension:@"plist"];
    NSURL *plistDirectory = [plistURL URLByDeletingLastPathComponent];
    OAAppearanceTestInvalidPlist *appearance = [OAAppearanceTestInvalidPlist appearanceForValidatingPropertyListInDirectory:plistDirectory forClass:[OAAppearanceTestInvalidPlist class]];
    
    NSError *error;
    BOOL success = [appearance validateValueAtKeyPath:@"TopLevelFloat" error:&error];

    XCTAssertFalse(success);
    XCTAssertEqual(error.domain, OAAppearanceErrorDomain);
    XCTAssertEqual(error.code, (NSInteger)OAAppearanceErrorCodeInvalidValueInPropertyList);
    
    XCTAssertThrows(appearance.TopLevelFloat);
}

@end

@implementation _NotificationCounter

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _nameMap = [NSMutableDictionary new];
        _notificationCounts = [NSCountedSet new];
    }
    return self;
}

- (void)dealloc;
{
    [_nameMap release];
    [_notificationCounts release];
    [super dealloc];
}

- (void)registerForObject:(id)object name:(NSString *)name;
{
    self.nameMap[NSStringFromClass([object class])] = name;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChange:) name:OAAppearanceValuesDidChangeNotification object:object];
}

- (void)didChange:(NSNotification *)notification
{
    id object = notification.object;
    Class class = [object class];
    NSString *className = NSStringFromClass(class);
    NSString *registeredName = self.nameMap[className];
    [self.notificationCounts addObject:registeredName];
}



@end








