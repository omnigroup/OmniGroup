// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniBase/OBPostLoader.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

#define MAX_LENGTH (20)

static void usage(const char *pgm)
{
    fprintf(stderr, "usage: %s -r\n", pgm);
    fprintf(stderr, "usage: %s -d \"<data string>\"\n", pgm);
    exit(1);
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool;

    pool = [[NSAutoreleasePool alloc] init];

    [OBPostLoader processClasses];

    if (argc == 2) {
        if (strcmp("-r", argv[1]) == 0) {
            while (YES) {
                NSAutoreleasePool *pool;
                NSData            *sourceData, *resultData;
                NSString          *ascii26String;

                pool = [[NSAutoreleasePool alloc] init];

                sourceData = [NSData randomDataOfLength: OFRandomNext() % MAX_LENGTH];
                ascii26String = [sourceData ascii26String];
                resultData = [[NSData alloc] initWithASCII26String: ascii26String];

                if (![sourceData isEqual: resultData]) {
                    NSLog(@"sourceData = %@, ascii26String = %@, resultData = %@",
                          sourceData, ascii26String, resultData);
                    return 1;
                }
                [resultData release];
                [pool release];
            }
        }
        usage(argv[0]);
    } else if (argc == 3) {
        if (strcmp("-d", argv[1]) == 0) {
            NSData            *sourceData, *resultData;
            NSString          *ascii26String;

            sourceData = [[NSString stringWithCString: argv[2]] propertyList];
            ascii26String = [sourceData ascii26String];
            resultData = [[NSData alloc] initWithASCII26String: ascii26String];

            NSLog(@"ascii26String = %@", ascii26String);

            if (![sourceData isEqual: resultData]) {
                NSLog(@"sourceData = %@, ascii26String = %@, resultData = %@",
                      sourceData, ascii26String, resultData);
                return 1;
            }
            [resultData release];
            return 0;
        } else if (strcmp("-s", argv[1]) == 0) {
            NSString          *sourceString, *resultString;
            NSData            *ascii26Data;

            sourceString = [NSString stringWithCString: argv[2]];
            ascii26Data  = [[NSData alloc] initWithASCII26String: sourceString];
            resultString = [ascii26Data ascii26String];

            NSLog(@"ascii26Data = %@", ascii26Data);

            if (![sourceString isEqual: resultString]) {
                NSLog(@"sourceString = %@, ascii26Data = %@, resultString = %@",
                      sourceString, ascii26Data, resultString);
                return 1;
            }
            [ascii26Data release];
            return 0;
        }
        usage(argv[0]);
    } else
        usage(argv[0]);

    
    return 0;
}
