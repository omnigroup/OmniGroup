// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface ODOUndoTests : ODOTestCase
@end

@implementation ODOUndoTests

- (void)testUndo;
{
    NSError *error = nil;
    
    MASTER(master);

    OBShouldNotError([self save:&error]);
    
    DETAIL(detail, master);
    
    OBShouldNotError([self save:&error]);
    
    // Should undo the insertion of the detail and relationship between it and the master
    [_undoManager undo];
    XCTAssertTrue([_undoManager groupingLevel] == 0);

    XCTAssertTrue([master.details count] == 0);
}

// These ends up checking that the snapshots recorded in the undo manager don't end up resurrecting deleted objects when we undo a delete by doing an 'insert with snapshot'
- (void)testUndoOfDeleteWithToOneRelationship;
{
    NSError *error = nil;
    
    MASTER(master);
    ODOObjectID *masterID = [[master objectID] copy];

    DETAIL(detail, master);
    ODOObjectID *detailID = [[detail objectID] copy];

    OBShouldNotError([self save:&error]);
    
    // Now, delete the master, which should cascade to the detail
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    XCTAssertTrue([detail isDeleted]);
    
    // Close the group and finalize the deletion by saving, making the objects invalidated
    OBShouldNotError([self save:&error]);
    
    // Undo the delete; there should now be two objects registered with the right object IDs.
    [_undoManager undo];
    XCTAssertTrue([_undoManager groupingLevel] == 0);
    
    XCTAssertTrue([[_editingContext registeredObjectByID] count] == 2);
    XCTAssertTrue([_editingContext objectRegisteredForID:masterID] != nil);
    XCTAssertTrue([_editingContext objectRegisteredForID:detailID] != nil);
}

- (void)testClearingEmptyToManyAfterRedo_unconnected;
{    
    MASTER(master);
    ODOObjectID *masterID = [[master objectID] copy];

    [self closeUndoGroup];
    [_undoManager undo];
    
    [_undoManager redo];
    
    // Re-find master after it got deleted and reinserted
    master = (ODOTestCaseMaster *)[_editingContext objectRegisteredForID:masterID];
    XCTAssertTrue(master != nil);
    
    // Crashed prior to the fix
    XCTAssertTrue([master isInserted]);
    XCTAssertTrue(master.details != nil);
    XCTAssertTrue([master.details count] == 0);
}

@end

