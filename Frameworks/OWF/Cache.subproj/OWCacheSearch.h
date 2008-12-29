// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Cache.subproj/OWCacheSearch.h 66176 2005-07-28 17:48:26Z kc $

#import <OmniFoundation/OFObject.h>
#import <OWF/OWContentCacheProtocols.h>

@class /* Foundation */ NSMutableSet, NSSet;
@class /* OmniFoundation */ OFHeap;

/* Parameters often used for searches */
#define COST_PER_LINK (0.1)		// Fixed overhead of traversing a link
#define COST_OF_REJECTION (1e6)   	// "cost" of producing content the target doesn't want
#define COST_OF_UNCERTAINTY (1e4)	// we fear the unknown

@interface OWCacheSearch : OFObject
{
    /* The parameters of the search */
    OWContent *sourceEntry;
    OWCacheArcRelationship searchRelation;
    OWPipeline *weaklyRetainedPipeline;
    float unacceptableCost;
    
    /* Queues of objects to consider */
    OFHeap *cachesToSearch;
    OFHeap *arcsToConsider;

    /* Arcs already considered and either rejected or previously traversed */
    NSMutableSet *rejectedArcs;
    /* These arcs were given to the pipeline in -init, and should be considered effectively free */
    NSMutableSet *freeArcs;
#ifdef DEBUG_kc
    struct {
        unsigned int debug:1;
    } flags;
#endif
}

// API
- initForRelation:(OWCacheArcRelationship)aRelation toEntry:(OWContent *)anEntry inPipeline:(OWPipeline *)context;

// Setting up for the search
- (void)addCaches:(NSArray *)someCaches;
- (void)addFreeArcs:(NSArray *)someArcs;
- (void)setRejectedArcs:(NSSet *)someArcs;
- (void)rejectArc:(id <OWCacheArc>)anArc;
- (void)setCostLimit:(float)unacceptableCost;

- (OWContent *)source;

// Getting the next arc. May return nil even if we aren't at EOF, to avoid expensive ops at the wrong time.
- (id <OWCacheArc>)nextArcWithoutBlocking;

// Returns YES if we know there are no more arcs. Might return NO even if there aren't any more arcs, if there's an expensive cache to query (since that cache might or might not return anything).
- (BOOL)endOfData;

// Query any expensive caches that are up to be searched next. It's a good idea not to hold the global pipeline lock when you call this method.
- (void)waitForAvailability;

// Estimating the cost of traversing an arc (used internally)
- (float)estimateCostForArc:(id <OWCacheArc>)anArc;

@end
