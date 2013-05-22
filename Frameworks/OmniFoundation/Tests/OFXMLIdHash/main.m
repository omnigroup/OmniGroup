// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/Foundation.h>

// We directly compile a few files from OmniFoundation so we can build them 32- and 64-bit.
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/NSData-OFSignature.h>

static void _log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void _log(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    fprintf(stderr, "%s\n", [string UTF8String]);
    [string release];
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        //NSLog(@"sizeof(long) = %ld", sizeof(long));
        for (int argi = 1; argi < argc; argi++) {
            NSString *path = [NSString stringWithUTF8String:argv[argi]];
            NSError *error;
            NSData *data = [[NSData alloc] initWithContentsOfFile:path options:0 error:&error];
            if (!data) {
                _log(@"Error reading \"%@\": %@", path, error);
                continue;
            }
            
            NSData *signature = [data sha1Signature];
            _log(@"%@: %@ %@", path, [OFXMLCreateIDFromData(signature) autorelease], [OFXMLCreateIDFromData(data) autorelease]);
            [data release];
        }
    }
    return 0;
}

