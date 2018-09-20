// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$");

static NSUInteger DidSaveBlockAssociatedObjectKey;

@interface ODOTestCaseMaster (TestSupport)
@property (nonatomic, strong) void (^didSaveBlock)(void);
@end

@implementation ODOTestCaseMaster (TestSupport)

- (void (^)(void))didSaveBlock;
{
    return objc_getAssociatedObject(self, &DidSaveBlockAssociatedObjectKey);
}

- (void)setDidSaveBlock:(void (^)(void))didSaveBlock;
{
    objc_setAssociatedObject(self, &DidSaveBlockAssociatedObjectKey, didSaveBlock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)didSave;
{
    [super didSave];
    if (self.didSaveBlock != nil) {
        self.didSaveBlock();
    }
}

@end

@interface ODOEditingContextTests : ODOTestCase
@end

@implementation ODOEditingContextTests

/// <bug:///138442> (Mac-OmniFocus Engineering: -isInserted should report NO inside of -didSave)
- (void)testIsInsertedInsideDidSave;
{
    MASTER(master);
    
    __block BOOL isInserted = NO;
    master.didSaveBlock = ^{
        isInserted = master.isInserted;
    };
    
    NSError *error = nil;
    XCTAssertTrue([self save:&error]);
    XCTAssertNil(error);
    XCTAssertFalse(isInserted);
}

@end
