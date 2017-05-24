// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

@interface ODOSnapshotTests : ODOTestCase
@end

@implementation ODOSnapshotTests

- (void)testNullifyOfOneToOneRelationship;
{
    // Get two objects hooked up, pointing at each other via their one-to-one relationship
    ODOObject *peerA, *peerB;
    {
        peerA = [[[ODOTestCasePeerA alloc] initWithEntity:[ODOTestCaseModel() entityNamed:@"PeerA"] primaryKey:@"pk1" insertingIntoEditingContext:_editingContext] autorelease];
        peerB = [[[ODOTestCasePeerB alloc] initWithEntity:[ODOTestCaseModel() entityNamed:@"PeerB"] primaryKey:@"pk2" insertingIntoEditingContext:_editingContext] autorelease];
        
        [peerA setValue:peerB forKey:@"peerB"];
        XCTAssertEqualObjects(peerA, [peerB valueForKey:@"peerA"], @"Inverse to-one relationship should have been hooked up");
        
        NSError *error = nil;
        OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    }
    
    // Clearing the relationship from one side should clear both sides
    [peerA setValue:nil forKey:@"peerB"];
    XCTAssertNil([peerA valueForKey:@"peerB"]);
    XCTAssertNil([peerB valueForKey:@"peerA"]);
    
    // The committed snapshot value should be valid for both sides
    XCTAssertEqual(peerA, [peerB committedValueForKey:@"peerA"]);
    XCTAssertEqual(peerB, [peerA committedValueForKey:@"peerB"]);
}

@end
