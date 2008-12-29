// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

@interface ODODeleteTests : ODOTestCase
@end

@implementation ODODeleteTests

// Delete an object while it is in the processed inserts
- (void)testDeleteOfProcessedInsert;
{
    NSError *error = nil;
    
    ODOObject *master = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Master"] primaryKey:@"master"];
    [_editingContext insertObject:master];
    [master release];
    
    [_editingContext processPendingChanges];
    
    OBShouldNotError([_editingContext deleteObject:master error:&error]);

    [_editingContext processPendingChanges];
}

// Perform a fetch were one of the results in the database is deleted in memory.
- (void)testFetchingWithLocallyDeletedObject;
{
    NSError *error = nil;

    ODOEntity *entity = [_model entityNamed:@"Master"];
    
    ODOObject *master1 = [[ODOObject alloc] initWithEditingContext:_editingContext entity:entity primaryKey:@"master1"];
    [_editingContext insertObject:master1];
    [master1 release];

    ODOObject *master2 = [[ODOObject alloc] initWithEditingContext:_editingContext entity:entity primaryKey:@"master2"];
    [_editingContext insertObject:master2];
    [master2 release];
    
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    // Mark the second object deleted
    OBShouldNotError([_editingContext deleteObject:master2 error:&error]);

    // Do a fetch of all the master objects
    ODOFetchRequest *fetch = [[[ODOFetchRequest alloc] init] autorelease];
    [fetch setEntity:entity];
    
    NSArray *results;
    OBShouldNotError((results = [_editingContext executeFetchRequest:fetch error:&error]) != nil);

    should([results count] == 1);
    should([results lastObject] == master1);
}

// This can easily happen if UI code can select both a parent and child and delete them w/o knowing that the deletion of the parent will get the child too.  Nice if the UI handles it, but shouldn't crash or do something crazy otherwise.
- (void)testDeleteOfAlreadyCascadedDelete;
{
    ODOObject *master = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Master"] primaryKey:@"master"];
    [_editingContext insertObject:master];
    [master release];
    
    ODOObject *detail = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Detail"] primaryKey:@"detail"];
    [_editingContext insertObject:detail];
    [detail release];

    [detail setValue:master forKey:@"master"];
    
    NSError *error = nil;
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    should([[master valueForKey:@"details"] count] == 1);
    should([[master valueForKey:@"details"] member:detail] == detail);
    
    // Delete the master and then the child (which should have been cascaded)
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
    should([detail isDeleted]);
    OBShouldNotError([_editingContext deleteObject:detail error:&error]);
}

// Inverse of the above, where the item that would be cascaded gets deleted first.  Due to set ordering, either of these could happen if the UI isn't specifically deleting only the container elements.
- (void)testDeleteOfContainerWithAlreadyDeletedMember;
{
    ODOObject *master = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Master"] primaryKey:@"master"];
    [_editingContext insertObject:master];
    [master release];
    
    ODOObject *detail = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[_model entityNamed:@"Detail"] primaryKey:@"detail"];
    [_editingContext insertObject:detail];
    [detail release];
    
    [detail setValue:master forKey:@"master"];
    
    NSError *error = nil;
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    should([[master valueForKey:@"details"] count] == 1);
    should([[master valueForKey:@"details"] member:detail] == detail);
    
    // Delete the detail and then the master
    OBShouldNotError([_editingContext deleteObject:detail error:&error]);
    should(![master isDeleted]);
    OBShouldNotError([_editingContext deleteObject:master error:&error]);
}

@end
