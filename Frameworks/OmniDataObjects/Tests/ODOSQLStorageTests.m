// Copyright 2018 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$");

@interface ODOSQLStorageTests : ODOTestCase
@end

@implementation ODOSQLStorageTests

// N.B. This test includes the string "unconnected" in the name because that's a magic word for -[ODOTestCase setUp] to skip the default connect-to-file behavior.
- (void)testConnectingInMemoryDatabase_unconnected;
{
    OBPRECONDITION([_database connectedURL] == nil);
    
    NSURL *inMemoryURL = [NSURL URLWithString:ODODatabaseInMemoryFileURLString];
    XCTAssertNotNil(inMemoryURL);
    
    NSError *error;
    OBShouldNotError([_database connectToURL:inMemoryURL error:&error]);
    XCTAssertEqual(inMemoryURL, [_database connectedURL]);
    
    [_editingContext insertObjectWithEntityName:@"Master"];
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    OBShouldNotError([_database disconnect:&error]);
}

@end
