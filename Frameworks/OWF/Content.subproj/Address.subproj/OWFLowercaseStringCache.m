// Copyright 1998-2005, 2012 Omni Development, Inc.  All rights reserved.
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


// TJW: We could probably get away with one global lock since the vast majority of the time we should expect successful lookups.

void OWFLowercaseStringCacheInit(OWFLowercaseStringCache *cache)
{
    cache->set = CFSetCreateMutable(kCFAllocatorDefault, 0, &OFCaseInsensitiveStringSetCallbacks);
    cache->lock = [[NSLock alloc] init];
}

void OWFLowercaseStringCacheClear(OWFLowercaseStringCache *cache)
{
    CFRelease(cache->set);
    cache->set = NULL;
    [cache->lock release];
    cache->lock = nil;
}


NSString *_OWFLowercaseStringCacheAdd(OWFLowercaseStringCache *cache, NSString *string)
{
    CFMutableSetRef newSet, oldSet;
    NSString *lower;
    
    [cache->lock lock];
    
    // NSLog(@"OWFLowercaseStringCache: 0x%08x Adding %@", cache, string);
    
    // Create a new unlimited size set with the same callbacks and values
    newSet =  CFSetCreateMutableCopy(kCFAllocatorDefault, 0, cache->set);
    
    // Add the new value
    lower = [string lowercaseString];
    CFSetSetValue(newSet, lower);

    // Replace the set atomically (only this thread can change the pointer and pointer
    // sets are atomic).
    oldSet = cache->set;
    cache->set = newSet;
    
    // Schedule the old set to be released in one minute
    [[OFScheduler mainScheduler] scheduleSelector: @selector(release) onObject: (id)oldSet withObject: nil afterTime: 60.0];

    [cache->lock unlock];
    
    return lower;
}

