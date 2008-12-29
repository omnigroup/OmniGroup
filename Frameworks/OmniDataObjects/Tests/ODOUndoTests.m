// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

@interface ODOUndoTests : ODOTestCase
@end

@implementation ODOUndoTests

- (void)testUndo;
{
    NSError *error = nil;
    
    ODOObject *master = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Master"] primaryKey:@"master"];
    [_editingContext insertObject:master];
    [master release];

    [self closeUndoGroup];
    should([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    ODOObject *detail = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Detail"] primaryKey:@"detail"];
    [_editingContext insertObject:detail];

    [detail setValue:master forKey:@"master"];
    
    [self closeUndoGroup];
    should([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    // Should undo the insertion of the detail and relationship between it and the master
    [_undoManager undo];
    should([_undoManager groupingLevel] == 0);

    should([[master valueForKey:@"details"] count] == 0);
}

// These ends up checking that the snapshots recorded in the undo manager don't end up resurrecting deleted objects when we undo a delete by doing an 'insert with snapshot'
- (void)testUndoOfDeleteWithToOneRelationship;
{
    NSError *error = nil;
    
    ODOObject *master = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Master"] primaryKey:@"master"];
    ODOObjectID *masterID = [[master objectID] copy];
    [_editingContext insertObject:master];
    [master release];

    ODOObject *detail = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Detail"] primaryKey:@"detail"];
    ODOObjectID *detailID = [[detail objectID] copy];
    [_editingContext insertObject:detail];
    [detail release];

    [detail setValue:master forKey:@"master"];

    [self closeUndoGroup];
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    // Now, delete the master, which should cascade to the detail
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    should([detail isDeleted]);
    
    // Close the group and finalize the deletion by saving, making the objects invalidated
    [self closeUndoGroup];
    should([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    // Undo the delete; there should now be two objects registered with the right object IDs.
    [_undoManager undo];
    should([_undoManager groupingLevel] == 0);
    
    should([[_editingContext registeredObjectByID] count] == 2);
    should([_editingContext objectRegisteredForID:masterID] != nil);
    should([_editingContext objectRegisteredForID:detailID] != nil);
}

@end

