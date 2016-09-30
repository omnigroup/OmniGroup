// Copyright 1998-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWFLowercaseStringCache.h"

#import <OmniFoundation/CFSet-OFExtensions.h>
#import <OmniFoundation/OFScheduler.h>
#import <OmniBase/rcsid.h>

#import <Foundation/NSString.h>
#import <Foundation/NSLock.h>

RCS_ID("$Id$")


// We can get away with one global lock since the vast majority of the time we should expect successful lookups.

static NSLock *_globalLock;

void OWFLowercaseStringCacheInit(OWFLowercaseStringCache *cache)
{
    cache->set = CFSetCreateMutable(kCFAllocatorDefault, 0, &OFCaseInsensitiveStringSetCallbacks);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _globalLock = [[NSLock alloc] init];
    });
}

void OWFLowercaseStringCacheClear(OWFLowercaseStringCache *cache)
{
    CFRelease(cache->set);
    cache->set = NULL;
}

NSString *_OWFLowercaseStringCacheAdd(OWFLowercaseStringCache *cache, NSString *string)
{
    [_globalLock lock];
    
    // NSLog(@"OWFLowercaseStringCache: 0x%08x Adding %@", cache, string);
    
    // Create a new unlimited size set with the same callbacks and values
    CFMutableSetRef newSet = CFSetCreateMutableCopy(kCFAllocatorDefault, 0, cache->set);
    
    // Add the new value
    NSString *lower = [string lowercaseString];
    CFSetSetValue(newSet, CFBridgingRetain(lower));

    // Replace the set atomically (only this thread can change the pointer and pointer
    // sets are atomic).
    CFMutableSetRef oldSet = cache->set;
    cache->set = newSet;
    
    // Schedule the old set to be released in one minute
    [[OFScheduler mainScheduler] scheduleSelector:@selector(self) onObject:CFBridgingRelease(oldSet) withObject:nil afterTime:60.0];

    [_globalLock unlock];
    
    return lower;
}

