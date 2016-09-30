// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OWF/OWContentCacheProtocols.h>

@class /* Foundation */ NSMutableSet, NSSet;
@class /* OmniFoundation */ OFHeap;

/* Parameters often used for searches */
#define COST_PER_LINK (0.1f)		// Fixed overhead of traversing a link
#define COST_OF_REJECTION (1e6f)   	// "cost" of producing content the target doesn't want
#define COST_OF_UNCERTAINTY (1e4f)	// we fear the unknown

@interface OWCacheSearch : OFObject

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
