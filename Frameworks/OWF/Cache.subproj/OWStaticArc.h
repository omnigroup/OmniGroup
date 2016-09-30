// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OWF/OWContentCacheProtocols.h>

@class NSDictionary, NSDate;

@interface OWStaticArcInitialization : NSObject
@property OWCacheArcType arcType;
@property (retain) OWContent *source, *subject, *object;
@property (retain) NSDictionary *contextDependencies;
@property (retain) NSDate *creationDate, *freshUntil;
@property BOOL resultIsSource, resultIsError;
@property BOOL shouldNotBeCachedOnDisk;
@property BOOL nonReusable;
@end

@interface OWStaticArc : OFObject <OWCacheArc>
{
    OWCacheArcType arcType;
    OWContent *source, *subject, *object;
    NSDictionary *contextDependencies;

    // The date we consider the arc to have been created. This might come from the server, or it might just be the time we performed the fetch. This is *not* the same as the Last-Modified date of the object content.
    // The lifetime of an arc isn't the same as the lifetime of the content it refers to; arcs are very rarely valid for more than a day or so, even if we continually revalidate the content without refetching it.
    NSDate *creationDate;

    // This arc can be considered non-stale until this date. Controlled by the Expires or max-age headers. Don't use this for client-guessed heuristic expiration.
    NSDate *freshUntil;

    BOOL resultIsSource;
    BOOL resultIsError;
    BOOL shouldNotBeCachedOnDisk;
    // shouldNotBeCachedOnDisk means that it's cheaper/better to recompute this arc than to store it in a disk cache (memory cache is still OK). Note that this flag is an efficiency flag; to inhibit caching for security purposes, use content metadata.

    BOOL invalidated;  // Has been marked invalid other than by simple timeout. This is the only mutable field.
    BOOL nonReusable;  // noCache or mustRevalidate
}

// API
+ (BOOL)deserializeProperties:(OWStaticArcInitialization *)stuff fromBuffer:(NSData *)buf;

- initWithArcInitializationProperties:(OWStaticArcInitialization *)stuff;

- (OWCacheArcRelationship)relationsOfEntry:(OWContent *)anEntry intern:(OWContent **)interned;
- (OWContent *)source;
- (NSData *)serialize;

- (BOOL)dominatesArc:(OWStaticArc *)anotherArc;

- (void)invalidate;  // for cache control, not for retain cycle breaking!

@end
