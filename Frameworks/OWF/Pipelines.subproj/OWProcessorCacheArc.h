// Copyright 2003-2005, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSDate, NSLock, NSMutableArray;
@class OWCacheControlSettings, OWContent, OWContentTypeLink, OWPipeline, OWProcessor, OWProcessorCache, OWProcessorDescription, OWStaticArc, OWTask;

#import <Foundation/NSDate.h> // For NSTimeInterval
#import <OWF/OWContentCacheProtocols.h> // For OWCacheArcType
#import <OWF/OWProcessor.h> // For OWProcessorStatus
#import <OWF/OWFWeakRetainConcreteImplementation.h>

@interface OWProcessorCacheArc : OFObject <OWCacheArc, OWProcessorContext, OWFWeakRetain>
{
    OWContent /* *subject, */ *source, *object;

    OWCacheArcType arcType;
    struct {
        enum {
            ArcStateInitial = 1,
            ArcStateStarting,
            ArcStateLoadingBundle,
            ArcStateRunning,
            ArcStateRetired
        } state: 8;
        unsigned int objectIsSource:1, objectIsError:1;
        unsigned int arcShouldNotBeCachedOnDisk:1;
        unsigned int possiblyProducesSource:1;
        unsigned int traversalIsAction:1;
        unsigned int havePassedOn: 1;
        unsigned int haveRemovedFromCache: 1;
        unsigned int _pad: 1;
    } flags;

    /* Locking discipline */
    /* Not changed after initialization: source, link */
    /* protected by OWPipeline lock: ... */
    /* protected by local lock: dependentContext, all members of 'flags', cacheControl, 'processor', auxiliaryContent, ... */

    OWProcessorCache *owner;
    OWContentTypeLink *link;
    OWProcessor *processor;

    NSLock *lock; /* LEAF LOCK */
    NSMutableDictionary *dependentContext;
    
    // Keeping track of when we started working and when we got the beginning of the response
    NSDate *processStarted, *processGotResponse;
    OWProcessorStatus previousStatus;
    
    // Cacheability information from the processor or server (mostly applies to HTTP content)
    OWCacheControlSettings *cacheControl;

    // Derived information: derived from processStarted, processGotResponse, cacheControl.serverDate, and cacheControl.ageAtFetch
    NSTimeInterval clockSkew;
    NSDate *arcCreationDate;

    unsigned short cachedTaskPriority;
    OWTask *cachedTaskInfo;
    OWPipeline *context;

    OFSimpleLockType displayablesSimpleLock;
    NSDate *firstBytesDate;
    NSUInteger bytesProcessed;
    NSUInteger totalBytes;

    CFMutableArrayRef observers;  // Nonretained observers; protected by local lock

    NSMutableArray *auxiliaryContent;

    OWFWeakRetainConcreteImplementation_IVARS;
}

- initWithSource:(OWContent *)sourceEntry link:(OWContentTypeLink *)aLink inCache:(OWProcessorCache *)aCache forPipeline:(OWPipeline *)owner;

- (NSUInteger)hash;
- (BOOL)isEqual:another;

- (OWStaticArc *)addToCache:(id <OWCacheArcProvider,OWCacheContentProvider>)actualCache;
- (void)removeFromCache;  // Removes the receiver from the processor cache

- (OWProcessorDescription *)processorDescription;
- (BOOL)isOwnedByPipeline:(OWPipeline *)aContext;

@end

