// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFObject.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static void micro(id object)
{
    NSTimeInterval best = FLT_MAX, total = 0;
    const NSUInteger trials = 50;
    
    for (NSUInteger trial = 0; trial < trials; trial++) {
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        
        const NSUInteger limit = 10000000;
        for (NSUInteger operation = 0; operation < limit; operation++) {
            [object retain];
        }
        for (NSUInteger operation = 0; operation < limit; operation++) {
            [object release];
        }
        
        NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval duration = end - start;
        
        NSLog(@"%@ %f", [object class], duration);
        
        if (best > duration)
            best = duration;
        total += duration;
    }
    
    NSLog(@"  best %f, average %f", best, total/trials);
}

int main(int argc, const char * argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s file1...\n", argv[0]);
        exit(1);
    }
    
    // Micro benchmark retain/release
    {
        micro([[NSObject new] autorelease]);
        micro([[OFObject new] autorelease]);
    }
    
    for (int argi = 1; argi < argc; argi++) {
        @autoreleasepool {
            OFXMLWhitespaceBehavior *whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];

            NSString *fileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
            
            NSError *error;
            NSData *xmlData = [[NSData alloc] initWithContentsOfFile:fileName options:0 error:&error];
            if (!xmlData) {
                NSLog(@"Error reading %@: %@", fileName, [error toPropertyList]);
                continue;
            }

            for (NSUInteger try = 0; try < 100; try++) {
                OFXMLDocument *doc = [[OFXMLDocument alloc] initWithContentsOfFile:fileName whitespaceBehavior:whitespaceBehavior  error:&error];
                if (!doc)
                    NSLog(@"Error parsing %@: %@", fileName, [error toPropertyList]);
            }
        }
    }
    return 0;
}

