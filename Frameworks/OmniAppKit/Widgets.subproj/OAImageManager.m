// Copyright 2003-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAImageManager.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OAImageManager

// API

static OAImageManager *SharedImageManager = nil;

+ (OAImageManager *)sharedImageManager;
{
    if (SharedImageManager == nil)
        SharedImageManager = [[self alloc] init];

    return SharedImageManager;
}

+ (void)setSharedImageManager:(OAImageManager *)newInstance;
{
    if (SharedImageManager != nil)
        [SharedImageManager release];

    SharedImageManager = [newInstance retain];
}

- init
{
    self = [super init];
    nonexistentImageNames = (id)CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    return self;
}

- (void)dealloc
{
    CFRelease(nonexistentImageNames);
    [super dealloc];
}

- (NSImage *)imageNamed:(NSString *)imageName;
{
    OBPRECONDITION(imageName); // Crashes under 10.3 otherwise
    if (!imageName)
	return nil;
    return [NSImage imageNamed:imageName];
}

- (NSImage *)imageNamed:(NSString *)imageName inBundle:(NSBundle *)aBundle;
{
    NSImage *image;
    NSString *path;
    
    OBASSERT([NSThread mainThreadOpsOK]); // Because our caches aren't threadsafe
    
    image = [self imageNamed:imageName];
    if (image && [image isValid])
        return image;
    
    // Try not to hit the filesystem repeatedly if we're looking up nonexistent images (e.g. via +[NSImage(OAExtensions) tintedImageNamed:inBundle:])
    NSMutableSet *nonexistenceCache = (id)CFDictionaryGetValue((CFMutableDictionaryRef)nonexistentImageNames, aBundle);
    if (nonexistenceCache && [nonexistenceCache member:imageName])
        return nil;
    
    path = [aBundle pathForImageResource:imageName];
    if (path) {
        image = [[[NSImage alloc] initByReferencingFile:path] autorelease];
        if (image && [image isValid]) {
            [image setName:imageName];
            return image;
        }
    }
    
    // Cache this lookup failure for next time
    if (!nonexistenceCache) {
        nonexistenceCache = [[NSMutableSet alloc] init];
        CFDictionaryAddValue((CFMutableDictionaryRef)nonexistentImageNames, aBundle, nonexistenceCache);
        [nonexistenceCache autorelease];
    }
    [nonexistenceCache addObject:imageName];
    
    return nil;
}    

@end

