// Copyright 2003-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniNetworking/OmniNetworking.h>

RCS_ID("$Id$");

int main()
{
    NSAutoreleasePool *pool;
    NSArray *ifs;
    
    [OBObject class];
    
    pool = [[NSAutoreleasePool alloc] init];
    
    ifs = [ONInterface interfaces];  // Get a list of the system's interfaces
    
    [ifs makeObjectsPerformSelector:@selector(maximumTransmissionUnit)];  // Cause them to cache their MTUs
    
    NSLog(@"Interfaces: %@", [ifs description]);  // Print them out
    
    [pool release];

    return 0;
}
