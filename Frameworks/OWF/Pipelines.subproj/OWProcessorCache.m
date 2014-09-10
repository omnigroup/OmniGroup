// Copyright 2003-2005, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWProcessorCache.h"

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OWContent.h"
#import "OWContentCacheProtocols.h"
#import "OWContentInfo.h"
#import "OWContentType.h"
#import "OWContentTypeLink.h"
#import "OWCookieDomain.h"
#import "OWMemoryCache.h"
#import "OWPipeline.h"
#import "OWProcessor.h"
#import "OWProcessorCacheArc.h"
#import "OWProcessorDescription.h"
#import "OWStaticArc.h"

RCS_ID("$Id$");

@interface OWProcessorCache (Private)
- (void)_allocateProcessorContainers;
- (void)_flushCache:(NSNotification *)note;
@end

@implementation OWProcessorCache

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
    [lock release];
    [processorsFromHashableSources release];
    [otherProcessors release];
    [super dealloc];
}

- (NSArray *)allArcs;
{
    __block NSMutableArray *arcs = nil;

    OFWithLock(lock, ^{
        arcs = [[NSMutableArray alloc] initWithArray:[processorsFromHashableSources allValues]];
        [arcs addObjectsFromArray:otherProcessors];
    });
    
    return [arcs autorelease];
}

- (NSArray *)arcsWithRelation:(OWCacheArcRelationship)relation toEntry:(OWContent *)anEntry inPipeline:(OWPipeline *)pipe
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
            OWProcessorCacheArc *extant = [otherProcessors objectAtIndex:processorIndex];
            OWContent *extantSource = [extant source];
            
            if ([anEntry isEqual:extantSource]) {
                [result addObject:extant];
            }
            
            // If this processor's source content has become hashable since the last time we looked at it, move it to the (more efficient) OFMultiValueDictionary.
            if ([extantSource isHashable]) {
                [processorsFromHashableSources addObject:extant forKey:extantSource];
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
            OWProcessorCacheArc *newArc;
            
            if (localOnly && [proc usesNetwork])
                continue;
            
            newArc = [[OWProcessorCacheArc alloc] initWithSource:anEntry link:possible inCache:self forPipeline:pipe];
            
            OBASSERT(processorsFromHashableSources != nil);
            OBASSERT(otherProcessors != nil);
            if (anEntryIsHashable)
                [processorsFromHashableSources addObject:newArc forKey:anEntry];
            else
                [otherProcessors addObject:newArc];
            OBASSERT([newArc retainCount] >= 2);
            [newArc incrementWeakRetainCount]; // Convert the strong retain from the processorsFromHashableSources or otherProcessors container into a weak retain
            
            [result addObject:newArc];
            
            [newArc release]; // Pairs with -alloc above
        }
        
    });

    [delayedRelease release];

    return result;
}

- (float)cost
{
    // return 1e-5;  // cheap, but not totally free
    return 0;
}

- (void)removeArc:(OWProcessorCacheArc *)anArc
{
    [anArc retain]; // Avoid weak-retain-release shenanigans inside the lock.
    
    OFWithLock(lock, ^{
        BOOL removed;
        
        NSUInteger arrayIndex = [otherProcessors indexOfObjectIdenticalTo:anArc];
        if (arrayIndex != NSNotFound) {
            [otherProcessors removeObjectAtIndex:arrayIndex];
            removed = YES;
        } else {
            removed = [processorsFromHashableSources removeObjectIdenticalTo:anArc forKey:[anArc source]];
        }
        if (removed)
            [anArc decrementWeakRetainCount];
        OBASSERT(removed);
    });
    
    [anArc release];
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
    OFMultiValueDictionary *retainedProcessorsFromHashableSources = processorsFromHashableSources;
    processorsFromHashableSources = nil;

    NSMutableArray *retainedOtherProcessors = otherProcessors;
    otherProcessors = nil;
    
    [self _allocateProcessorContainers];
    
    [lock unlock];

    // Now that we're out of the lock, let's go ahead and release these (weakly retained) processor arcs
    [[retainedProcessorsFromHashableSources allValues] makeObjectsPerformSelector:@selector(decrementWeakRetainCount)];
    [retainedProcessorsFromHashableSources release];
    [retainedOtherProcessors makeObjectsPerformSelector:@selector(decrementWeakRetainCount)];
    [retainedOtherProcessors release];
}

@end
