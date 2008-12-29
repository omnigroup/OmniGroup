// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

static void usage(const char *pgm)
{
    fprintf(stderr, "usage: %s -s base64String\n", pgm);
    exit(1);
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (argc == 3) {
        if (strcmp(argv[1], "-s") == 0) {
            NSString *base64Input, *base64Result;
            NSData   *data;

            base64Input = [[NSString alloc] initWithCString: argv[2]];
            data = [[NSData alloc] initWithBase64String: base64Input];
            base64Result = [data base64String];

            if (![base64Input isEqualToString: base64Result]) {
                NSLog(@"base64Input = %@, base64Result = %@", base64Input, base64Result);
                return 1;
            } else
                return 0;
        }
    }

    usage(argv[0]);
    
    [pool release];
    return 0;
}
