// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import "ODOTestCaseModel.h"

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface ODODeleteTests : ODOTestCase
@end

@implementation ODODeleteTests

// Delete an object while it is in the processed inserts
- (void)testDeleteOfProcessedInsert;
{
    NSError *error = nil;
    
    MASTER(master);
    
    [_editingContext processPendingChanges];
    
    OBShouldNotError([_editingContext deleteObject:master error:&error]);

    [_editingContext processPendingChanges];
}

// Perform a fetch were one of the results in the database is deleted in memory.
- (void)testFetchingWithLocallyDeletedObject;
{
    NSError *error = nil;
    
    MASTER(master1);
    MASTER(master2);
    
    OBShouldNotError([self save:&error]);
    
    // Mark the second object deleted
    OBShouldNotError([_editingContext deleteObject:master2 error:&error]);

    // Do a fetch of all the master objects
    ODOFetchRequest *fetch = [[ODOFetchRequest alloc] init];
    [fetch setEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseMasterEntityName]];
    
    NSArray *results;
    OBShouldNotError((results = [_editingContext executeFetchRequest:fetch error:&error]) != nil);

    XCTAssertTrue([results count] == 1);
    XCTAssertTrue([results lastObject] == master1);
}

// This can easily happen if UI code can select both a parent and child and delete them w/o knowing that the deletion of the parent will get the child too.  Nice if the UI handles it, but shouldn't crash or do something crazy otherwise.
- (void)testDeleteOfAlreadyCascadedDelete;
{
    MASTER(master);
    DETAIL(detail, master);

    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    XCTAssertTrue([master.details count] == 1);
    XCTAssertTrue([master.details member:detail] == detail);
    
    // Delete the master and then the child (which should have been cascaded)
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    XCTAssertTrue([detail isDeleted]);
    OBShouldNotError([_editingContext deleteObject:detail error:&error]);
}

// Inverse of the above, where the item that would be cascaded gets deleted first.  Due to set ordering, either of these could happen if the UI isn't specifically deleting only the container elements.
- (void)testDeleteOfContainerWithAlreadyDeletedMember;
{
    MASTER(master);
    DETAIL(detail, master);
    
    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    XCTAssertTrue([master.details count] == 1);
    XCTAssertTrue([master.details member:detail] == detail);
    
    // Delete the detail and then the master
    OBShouldNotError([_editingContext deleteObject:detail error:&error]);
    XCTAssertTrue(![master isDeleted]);
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
}

- (void)testUndeletableUnset;
{
    MASTER(master1);
    XCTAssertFalse([master1 isUndeletable], @"should not get set");

    ODOTestCaseMaster *master2 = [[ODOTestCaseMaster alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseMasterEntityName] primaryKey:@"master2" insertingIntoEditingContext:_editingContext];
    XCTAssertFalse([master2 isUndeletable], @"should not get set");
}

- (void)testUndeletableSet;
{
    MASTER(master_undeletable);
    XCTAssertTrue([master_undeletable isUndeletable], @"should get set");
}

- (void)testUndoOfUndeletableInsert;
{
    MASTER(master_undeletable);

    XCTAssertNotNil([_editingContext undoManager], @"should be an undo manager");
    XCTAssertFalse([[_editingContext undoManager] canUndo], @"but it should have nothing undoable");
}

- (void)testAttemptedDeletionOfUndeletable;
{
    MASTER(master_undeletable);
    
    NSError *error = nil;
    XCTAssertFalse([_editingContext deleteObject:master_undeletable error:&error], @"should not delete");
    XCTAssertTrue([error causedByUserCancelling], @"should get rejected");
}

- (void)testCascadeToUndeletable;
{
    MASTER(master);
    DETAIL(detail_undeletable, master);
    
    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    
    XCTAssertTrue([master isDeleted], @"direct deletion should work");
    XCTAssertFalse([detail_undeletable isDeleted], @"cascade should not happen");
    XCTAssertNil(detail_undeletable.master, @"instead we should nullify");
}

- (void)testCascadeToUndeletableWithoutSavingFirst;
{
    MASTER(master);
    DETAIL(detail_undeletable, master);
    
    NSError *error = nil;
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    
    XCTAssertTrue([master isDeleted], @"direct deletion should work");
    XCTAssertFalse([detail_undeletable isDeleted], @"cascade should not happen");
    XCTAssertNil(detail_undeletable.master, @"instead we should nullify");
}

- (void)testFaultIsUndeletable;
{
    MASTER(master_undeletable);
    DETAIL(detail, master_undeletable);
    ODOObjectID *detailID = detail.objectID;
    
    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    [_editingContext reset];
    
    // Refetch the detail, should leave the master still being a fault, but undeleteable.
    detail = (typeof(detail))[_editingContext fetchObjectWithObjectID:detailID error:&error];
    OBShouldNotError(detail);
    
    master_undeletable = detail.master;
    XCTAssertTrue([master_undeletable isFault]);
    XCTAssertTrue([master_undeletable isUndeletable]);
}

// Deletes an object along an observed keypath, but not the source itself
- (void)testDeleteObjectOnObservedKeyPath;
{
    MASTER(master);
    DETAIL(detail, master);
    
    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    //[detail addObserver:self forKeyPath:@"master.name" options:0 context:_cmd];
    [detail addObserver:self forKeyPath:@"master.name" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:_cmd];
    
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    
    [detail removeObserver:self forKeyPath:@"master.name"];
}

// Deletes the source object of the they key path
- (void)testDeleteObjectWithObservedKeyPath;
{
    MASTER(master);
    DETAIL(detail, master);
    
    NSError *error = nil;
    OBShouldNotError([self save:&error]);
    
    //[detail addObserver:self forKeyPath:@"master.name" options:0 context:_cmd];
    [detail addObserver:self forKeyPath:@"master.name" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:_cmd];
    
    OBShouldNotError([_editingContext deleteObject:detail error:&error]);
    
    [detail removeObserver:self forKeyPath:@"master.name"];
}

#define CURRENT(x) do { \
    ODOObjectID *objectID = x.objectID; \
    x = (typeof(x))[_editingContext objectRegisteredForID:objectID]; \
    OBASSERT_NOTNULL(x); \
} while(0)

#define LEFT_REQ(x) INSERT_TEST_OBJECT(ODOTestCaseLeftHandRequired, x)
#define RIGHT_REQ(x) INSERT_TEST_OBJECT(ODOTestCaseRightHandRequired, x)
- (void)testDeleteCascadingAcrossOneToOne;
{
    NSError *error = nil;
    
    LEFT_REQ(left);
    RIGHT_REQ(right);

    left.rightHand = right;
    XCTAssertEqual(right.leftHand, left, @"should update inverse");
    
    [self closeUndoGroup];
    
    OBShouldNotError([_editingContext deleteObject:left error:&error]);
    XCTAssertTrue([left isDeleted], @"should cascade to right");
    XCTAssertTrue([right isDeleted], @"should cascade to right");

    // It is generally illegal to access properties on a deleted object after deletion. (It is OK when handing ODOEditingContextObjectsWillBeDeletedNotification.)
    // ODOObject returns nil for relationships for recently deleted objects for the reasons in -testDelete(.*)KeyPath, so this access is OK.
    XCTAssertNil(left.rightHand, @"should be nullified");
    XCTAssertNil(right.leftHand, @"should be nullified");

    OBShouldNotError([self save:&error]);
    [_undoManager undo];

    // The old objects should be dead and gone, but there should be new incarnations
    XCTAssertTrue([left hasBeenDeleted], @"should be dead");
    XCTAssertTrue([right hasBeenDeleted], @"should be dead");
    CURRENT(left);
    CURRENT(right);
    XCTAssertFalse([left isDeleted], @"should be added back");
    XCTAssertFalse([right isDeleted], @"should be added back");

    XCTAssertEqual(left.rightHand, right, @"should restore forward");
    XCTAssertEqual(right.leftHand, left, @"should restore inverse");
    
    OBShouldNotError([self save:&error]); // Turns the undone deletes (inserts) into real objects so that the redo doesn't just disappear them.
    [_undoManager redo];
    
    XCTAssertTrue([left isDeleted], @"should re-delete");
    XCTAssertTrue([right isDeleted], @"should re-delete");

    // It is generally illegal to access properties on a deleted object after deletion. (It is OK when handing ODOEditingContextObjectsWillBeDeletedNotification.)
    // ODOObject returns nil for relationships for recently deleted objects for the reasons in -testDelete(.*)KeyPath, so this access is OK.
    XCTAssertNil(left.rightHand, @"should be re-nullified");
    XCTAssertNil(right.leftHand, @"should be re-nullified");
}

// TODO: Test multi-stage KVO across a one-to-one with undo/redo of insertion/deletion.

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    // sel_isMapped is deprecated. Not sure if -respondsToSelector: is just going to do pointer equality or if it would walk off the end of a buffer with a string compare if context _wasn't_ a selector. In this case, we expect it to really always be one.
    if ([self respondsToSelector:(SEL)context]) {
        //NSLog(@"test:%@ object:%@ keyPath:%@ change:%@", NSStringFromSelector(context), [object shortDescription], keyPath, change);
    } else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];

}

@end
