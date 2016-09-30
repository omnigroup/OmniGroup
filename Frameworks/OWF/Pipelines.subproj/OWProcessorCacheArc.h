// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
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

@interface OWProcessorCacheArc : OFObject <OWCacheArc, OWProcessorContext>

- initWithSource:(OWContent *)sourceEntry link:(OWContentTypeLink *)aLink inCache:(OWProcessorCache *)aCache forPipeline:(OWPipeline *)owner;

- (NSUInteger)hash;
- (BOOL)isEqual:another;

- (OWStaticArc *)addToCache:(id <OWCacheArcProvider,OWCacheContentProvider>)actualCache;
- (void)removeFromCache;  // Removes the receiver from the processor cache

- (OWProcessorDescription *)processorDescription;
- (BOOL)isOwnedByPipeline:(OWPipeline *)aContext;

@end

