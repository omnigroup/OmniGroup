// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFController.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface OFXMLIdentifierTests : OFTestCase
@end

@implementation OFXMLIdentifierTests

- (void)testZeroBuffersOfVaryingLength;
{
    NSUInteger currentLength = 0, maxLength = 2000;
    NSMutableData *zeros = [NSMutableData dataWithCapacity:maxLength];
    NSMutableSet *seen = [NSMutableSet set];
    
    while (currentLength < maxLength) {
        [zeros setLength:currentLength];
        NSString *encoded = OFXMLCreateIDFromData(zeros);
        
        XCTAssertNil([seen member:encoded], @"Should produce different output for every length");
        [seen addObject:encoded];
        
        currentLength++;
    }
}

- (void)testAllValuesForSmallBuffer;
{
    uint16 value = 0;
    NSMutableSet *seen = [NSMutableSet set];

    while (YES) {
        @autoreleasepool {
            NSData *data = [NSData dataWithBytes:&value length:2];
            NSString *encoded = OFXMLCreateIDFromData(data);
            
            XCTAssertNil([seen member:encoded], @"Should produce different output for every length");
            [seen addObject:encoded];
        }
        
        if (value == UINT16_MAX)
            break;
        value++;
    }
}

- (void)testKnownInputs;
{
    NSArray *inputURLs = [[OFController controllingBundle] URLsForResourcesWithExtension:nil subdirectory:@"OFXMLIdentifierTests"];
    XCTAssertTrue([inputURLs count] > 0, @"Input files missing?");
    
    for (NSURL *inputURL in inputURLs) {
        NSError *error;
        NSData *data;
        
        OBShouldNotError(data = [NSData dataWithContentsOfURL:inputURL options:0 error:&error]);

        NSData *signature = [data sha1Signature];
                             
        NSString *encoded = OFXMLCreateIDFromData(signature);
        XCTAssertEqualObjects(encoded, [inputURL lastPathComponent], @"Should match expected signature");
    }
}

@end

