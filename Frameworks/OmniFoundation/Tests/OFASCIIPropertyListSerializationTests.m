// Copyright 2019-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

@import OmniFoundation;
@import Foundation;

@interface OFASCIIPropertyListSerializationTests : OFTestCase
@end

@implementation OFASCIIPropertyListSerializationTests

- (void)testInputs;
{
    NSArray *inputURLs = [OFControllingBundle() URLsForResourcesWithExtension:nil subdirectory:@"OFASCIIPropertyListSerializationTests"];
    XCTAssertTrue([inputURLs count] > 0, @"Input files missing?");

    for (NSURL *inputURL in inputURLs) {
        NSError *error;

        NSData *data;
        OBShouldNotError(data = [NSData dataWithContentsOfURL:inputURL options:0 error:&error]);

        NSString *inputString = [NSString stringWithData:data encoding:NSASCIIStringEncoding];
        XCTAssertNotNil(inputString);

        id plist = [inputString propertyList];
        XCTAssertNotNil(plist);

        NSData *resultData;
        OBShouldNotError(resultData = [OFASCIIPropertyListSerialization dataFromPropertyList:plist error:&error]);

        OFDataShouldBeEqual(data, resultData);
    }
}

@end

