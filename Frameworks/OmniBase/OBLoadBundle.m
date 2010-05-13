// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>
#import <OmniBase/OBPostLoader.h>

RCS_ID("$Id$");

int main(int argc, char *argv[])
{
    if (argc <= 1) {
        fprintf(stderr, "usage: %s bundle0 [bundle1, ...]\n", argv[0]);
        return 1;
    }
    
    for (int argi = 1; argi < argc; argi++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (!bundle) {
            NSLog(@"Unable to create bundle from '%@'!", path);
            continue;
        }
        
        if (![bundle load]) {
            NSLog(@"Unable to load bundle %@", bundle);
            continue;
        }
        
        [pool drain];
    }
    
    // Run our ABI checks
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [OBPostLoader processClasses];
    [pool drain];

    return 0;
}
