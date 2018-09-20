// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface ODOTestCaseDynamicProperty : ODOObject
@end

#import "ODOTestCaseDynamicProperty-Properties.h"

@implementation ODOTestCaseDynamicProperty
ODOTestCaseDynamicProperty_DynamicProperties;
@end

@interface ODODynamicPropertyTests : ODOTestCase
{
    BOOL receivedWill, receivedDid;
}
@end

@implementation ODODynamicPropertyTests

static void *KVOContext;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context != &KVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    if ([keyPath isEqualToString:@"name"]) {
        if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue])
            receivedWill = YES;
        else
            receivedDid = YES;
    }
}

- (void)testWillDidAccess;
{
    OBFinishPortingLater("update this test to reflect that will/did access are now only automatically called when the object is a fault in order to clear the fault.");
#if 0
    ODOTestCaseDynamicProperty *dyn = [[ODOTestCaseDynamicProperty alloc] initWithEntity:[ODOTestCaseModel() entityNamed:@"DynamicProperty"] primaryKey:nil insertingIntoEditingContext:_editingContext];

    XCTAssertTrue(dyn->willAccess == NO);
    XCTAssertTrue(dyn->didAccess == NO);
    
    XCTAssertTrue(dyn.name == nil); // access it
    
    XCTAssertTrue(dyn->willAccess == YES);
    XCTAssertTrue(dyn->didAccess == YES);    
#endif
}

- (void)testWillDidChange;
{
    ODOTestCaseDynamicProperty *dyn = [[ODOTestCaseDynamicProperty alloc] initWithEntity:[ODOTestCaseModel() entityNamed:@"DynamicProperty"] primaryKey:nil insertingIntoEditingContext:_editingContext];

    [dyn addObserver:self forKeyPath:@"name" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld|NSKeyValueObservingOptionPrior context:&KVOContext];
    [dyn setValue:@"foo" forKey:@"name"];
    XCTAssertTrue(receivedWill);
    XCTAssertTrue(receivedDid);

    receivedWill = receivedDid = NO;
    dyn.name = @"bar";
    XCTAssertTrue(receivedWill);
    XCTAssertTrue(receivedDid);
    
    [dyn removeObserver:self forKeyPath:@"name"];
}

@end
