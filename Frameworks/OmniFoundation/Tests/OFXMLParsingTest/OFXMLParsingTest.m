// Copyright 2012-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

int main(int argc, const char * argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s file1...\n", argv[0]);
        exit(1);
    }
    
    for (int argi = 1; argi < argc; argi++) {
        @autoreleasepool {
            //OFXMLWhitespaceBehavior *whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];

            // More realistic whitespace behavior for things that use our text archiving format.
            OFXMLWhitespaceBehavior *whitespaceBehavior = [[OFXMLWhitespaceBehavior alloc] initWithDefaultBehavior:OFXMLWhitespaceBehaviorTypeIgnore];
            [whitespaceBehavior setBehavior:OFXMLWhitespaceBehaviorTypePreserve forElementName:@"lit"];

            NSString *fileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
            
            NSData *xmlData;
            {
                __autoreleasing NSError *error;
                xmlData = [[[NSData alloc] initWithContentsOfFile:fileName options:0 error:&error] autorelease];
                if (!xmlData) {
                    NSLog(@"Error reading %@: %@", fileName, [error toPropertyList]);
                    continue;
                }
            }

            OFPerformanceMeasurement *perf = [[OFPerformanceMeasurement alloc] init];
            [perf addValues:5 withAction:^{
                __autoreleasing NSError *error;
                OFXMLDocument *doc = [[OFXMLDocument alloc] initWithContentsOfFile:fileName whitespaceBehavior:whitespaceBehavior error:&error];
                if (!doc)
                    NSLog(@"Error parsing %@: %@", fileName, [error toPropertyList]);
                [doc release];
            }];
            
            NSLog(@"performance = %@", perf);
            [perf release];
        }
    }
    return 0;
}

