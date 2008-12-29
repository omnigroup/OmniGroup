// Copyright 2003-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Pipelines.subproj/OWProcessorCache.h 79093 2006-09-08 00:05:45Z kc $

#import <OmniFoundation/OFObject.h>

@class NSLock, NSMutableArray;
@class OFMultiValueDictionary;
@class OWProcessorCacheArc;

#import "OWContentCacheProtocols.h" // For OWCacheArcProvider;

@interface OWProcessorCache : OFObject <OWCacheArcProvider>
{
    NSLock *lock;
    
    OFMultiValueDictionary *processorsFromHashableSources;
    NSMutableArray *otherProcessors;
}

- (void)removeArc:(OWProcessorCacheArc *)anArc;

@end


