// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWProcessorCache.h"

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWContentTypeLink.h>
#import <OWF/OWCookieDomain.h>
#import <OWF/OWMemoryCache.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessor.h>
#import "OWProcessorCacheArc.h"
#import <OWF/OWProcessorDescription.h>
#import <OWF/OWStaticArc.h>

RCS_ID("$Id$");

@interface OWProcessorCache (Private)
- (void)_allocateProcessorContainers;
- (void)_flushCache:(NSNotification *)note;
@end

@implementation OWProcessorCache
{
    NSLock *lock;
    
    OFMultiValueDictionary *processorsFromHashableSources;
    NSMutableArray <OFWeakReference *> *otherProcessors;
}

- init
{
    if (!(self = [super init]))
        return nil;

    lock = [[NSLock alloc] init];

    [self _allocateProcessorContainers];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_flushCache:) name:OWContentCacheFlushNotification object:nil];

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OWContentCacheFlushNotification object:nil];
}

- (NSArray <id <OWCacheArc>> *)allArcs;
{
    __block NSArray *arcs = nil;

    OFWithLock(lock, ^{
        NSMutableArray *arcReferences = [[NSMutableArray alloc] initWithArray:[processorsFromHashableSources allValues]];
        [arcReferences addObjectsFromArray:otherProcessors];
        arcs = [arcReferences arrayByPerformingBlock:^id(OFWeakReference *weakReference) {
            return weakReference.object;
        }];
    });
    
    return arcs;
}

- (NSArray <id <OWCacheArc>> *)arcsWithRelation:(OWCacheArcRelationship)relation toEntry:(OWContent *)anEntry inPipeline:(OWPipeline *)pipe
{
    /* We're only able to look up arcs (processors) by their source */
    if (!(relation & (OWCacheArcSubject | OWCacheArcSource)))
        return nil;

    BOOL localOnly;
    if ([[pipe contextObjectForKey:OWCacheArcCacheBehaviorKey] isEqual:OWCacheArcForbidNetwork])
        localOnly = YES;
    else
        localOnly = NO;

    /* Get a list of OWContentTypeLinks describing processors we could use */
    NSArray *possibleLinks = [[anEntry contentType] directTargetContentTypes];
    if ([anEntry isSource])
        possibleLinks = [possibleLinks arrayByAddingObjectsFromArray:[[OWContentType sourceContentType] directTargetContentTypes]];
    NSUInteger linkCount = [possibleLinks count];

    if (linkCount == 0)
        return nil;

    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *delayedRelease = [[NSMutableArray alloc] init];

    OFWithLock(lock, ^{
        
        NSUInteger preexistingProcessorCount;
        BOOL anEntryIsHashable = [anEntry isHashable];
        
        if (anEntryIsHashable) {
            NSArray *preexistingProcessors;
            
            // If the source content is "complete", then it's possible to store it in a hash table. In this case we check to see if the processorsFromHashableSources dictionary has any applicable arcs for this source content.
            
            preexistingProcessors = [processorsFromHashableSources arrayForKey:anEntry];
            preexistingProcessorCount = [preexistingProcessors count];
            
            for (NSUInteger linkIndex = linkCount; linkIndex > 0; linkIndex--) {
                OWContentTypeLink *possible = [possibleLinks objectAtIndex:linkIndex-1];
                
                for (NSUInteger processorIndex = 0; processorIndex < preexistingProcessorCount; processorIndex ++) {
                    OWProcessorCacheArc *extant = [preexistingProcessors objectAtIndex:processorIndex];
                    
                    if ([extant processorDescription] != [possible processorDescription])
                        continue;
                    
                    [result addObject:extant];
                }
            }
        }
        
        // We also may have some processors whose source content is not yet hashable; we have to scan through those as well.
        preexistingProcessorCount = [otherProcessors count];
        for (NSUInteger processorIndex = 0; processorIndex < preexistingProcessorCount; processorIndex++) {
            OFWeakReference *extantReference = [otherProcessors objectAtIndex:processorIndex];
            OWProcessorCacheArc *extant = extantReference.object;
            if (extant == nil) {
                // Our weak reference is stale, remove it
                [otherProcessors removeObjectAtIndex:processorIndex];
                processorIndex--;
                preexistingProcessorCount--;
                continue;
            }

            OWContent *extantSource = [extant source];
            
            if ([anEntry isEqual:extantSource]) {
                [result addObject:extant];
            }
            
            // If this processor's source content has become hashable since the last time we looked at it, move it to the (more efficient) OFMultiValueDictionary.
            if ([extantSource isHashable]) {
                [processorsFromHashableSources addObject:extantReference forKey:extantSource];
                [delayedRelease addObject:extant];
                // Adding the arc to the delayedRelease array (above) gives it a strong retain which prevents it from trying to invalidate itself. Otherwise, if its last (external) strong retain went away while we were processing, it could try to invalidate itself when we remove it from our otherProcessors array (below), and we'd deadlock with ourselves.
                [otherProcessors removeObjectAtIndex:processorIndex];
                processorIndex--;
                preexistingProcessorCount--;
            }
        }
        
        // Finally, create arcs for any desirable processors which didn't already exist in our cache.
        for (NSUInteger linkIndex = 0; linkIndex < linkCount; linkIndex++) {
            OWContentTypeLink *possible = [possibleLinks objectAtIndex:linkIndex];
            OWProcessorDescription *proc = [possible processorDescription];
            
            if (localOnly && [proc usesNetwork])
                continue;
            
            OWProcessorCacheArc *newArc = [[OWProcessorCacheArc alloc] initWithSource:anEntry link:possible inCache:self forPipeline:pipe];
            
            OBASSERT(processorsFromHashableSources != nil);
            OBASSERT(otherProcessors != nil);
            OFWeakReference *weakReference = [[OFWeakReference alloc] initWithObject:newArc];
            if (anEntryIsHashable)
                [processorsFromHashableSources addObject:weakReference forKey:anEntry];
            else
                [otherProcessors addObject:weakReference];
            
            [result addObject:newArc];
        }
        
    });

    delayedRelease = nil;

    return result;
}

- (float)cost
{
    // return 1e-5;  // cheap, but not totally free
    return 0;
}

- (void)removeArc:(OWProcessorCacheArc *)anArc
{
    OWProcessorCacheArc *retainedArc = anArc; // Avoid weak-retain-release shenanigans inside the lock.
    
    OFWithLock(lock, ^{
        BOOL removed;
        OFWeakReference *weakReference = [[OFWeakReference alloc] initWithDeallocatingObject:anArc];
        NSUInteger arrayIndex = [otherProcessors indexOfObject:weakReference];
        if (arrayIndex != NSNotFound) {
            [otherProcessors removeObjectAtIndex:arrayIndex];
            removed = YES;
        } else {
            removed = [processorsFromHashableSources removeObject:weakReference forKey:[anArc source]];
        }
        OBASSERT(removed);
    });
    
    retainedArc = nil;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    if (processorsFromHashableSources != nil)
        [debugDictionary setObject:processorsFromHashableSources forKey:@"processorsFromHashableSources"];
    if (otherProcessors != nil)
        [debugDictionary setObject:otherProcessors forKey:@"otherProcessors"];

    return debugDictionary;
}

@end

@implementation OWProcessorCache (Private)

- (void)_allocateProcessorContainers;
{
    OBPRECONDITION(processorsFromHashableSources == nil);
    OBPRECONDITION(otherProcessors == nil);

    processorsFromHashableSources = [[OFMultiValueDictionary alloc] initWithKeyCallBacks:&OFNSObjectDictionaryKeyCallbacks];
    otherProcessors = [[NSMutableArray alloc] init];
}

- (void)_flushCache:(NSNotification *)note;
{
    [lock lock];

    // We don't want to hold the lock longer than necessary, so within our lock we just nullify our instance variables (after caching their values on our stack)
    __strong OFMultiValueDictionary *retainedProcessorsFromHashableSources = processorsFromHashableSources;
    __strong NSMutableArray *retainedOtherProcessors = otherProcessors;
    processorsFromHashableSources = nil;
    otherProcessors = nil;
    
    [self _allocateProcessorContainers];
    
    [lock unlock];

    // Now that we're out of the lock, let's go ahead and release these (weakly retained) processor arcs
    retainedProcessorsFromHashableSources = nil;
    retainedOtherProcessors = nil;
}

@end
