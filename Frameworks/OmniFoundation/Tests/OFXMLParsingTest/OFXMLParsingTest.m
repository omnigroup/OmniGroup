// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniBase/NSError-OBExtensions.h>

RCS_ID("$Id$")

int main(int argc, const char * argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s file1...\n", argv[0]);
        exit(1);
    }
        
    for (int argi = 1; argi < argc; argi++) {
        @autoreleasepool {
            NSString *fileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
            OFXMLWhitespaceBehavior *whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];

            NSError *error;
            OFXMLDocument *doc = [[OFXMLDocument alloc] initWithContentsOfFile:fileName whitespaceBehavior:whitespaceBehavior  error:&error];
            if (!doc)
                NSLog(@"Error parsing %@: %@", fileName, [error toPropertyList]);
        }
    }
    return 0;
}

