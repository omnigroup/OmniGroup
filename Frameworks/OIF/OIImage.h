// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OIF/OIImage.h 66178 2005-07-28 17:50:20Z kc $

#import <OWF/OWAbstractContent.h>

@class NSArray, NSData, NSLock, NSMutableArray;
@class NSImage;

#import <Foundation/NSGeometry.h> // For NSSize
#import <OmniFoundation/OFByte.h>
#import <OmniFoundation/OFWeakRetainProtocol.h>
#import <OIF/OIImageObserverProtocol.h>
#import <ApplicationServices/ApplicationServices.h> // For CGImage
#import <AppKit/NSGraphics.h> // For NSCompositingOperation

typedef OFByte *OIImageGammaCorrectionTable;

@interface OIImage : OWAbstractContent <OWConcreteCacheEntry, NSCopying>
{
    BOOL haveSize;
    NSSize imageSize;
    CGImageRef cgImage;
    NSLock *cgImageLock;

    NSMutableArray *_observers;
    NSLock *observersLock;
    
    NSData *_pixelData;
    OWContent *_sourceContent;
}

+ (OWContentType *)contentType;

+ (CGImageRef)createCGImageFromBitmapData:(const void *)bitmapData width:(unsigned int)imageWidth height:(unsigned int)imageHeight bitsPerSample:(unsigned int)bitsPerSample samplesPerPixel:(unsigned int)samplesPerPixel;

// Gamma utility methods

+ (double)sourceGamma;
    // Standard is sRGB, approximately 2.2
+ (double)targetGamma;
    // Standard Macintosh monitors use 1.8
+ (double)gammaCorrection;
    // +sourceGamma / +targetGamma
+ (void)fillGammaCorrectionTable:(OIImageGammaCorrectionTable)gammaCorrectionTable withSamplesOfGamma:(double)gamma;

+ (BOOL)colorSyncEnabled;

// Image API

- (id)initWithSourceContent:(OWContent *)sourceContent;
    // Designated initializer
- (OWContent *)sourceContent;

- (BOOL)hasSize;
- (NSSize)size;
- (void)setSize:(NSSize)newSize;
- (CGImageRef)retainedCGImage;
- (NSImage *)nsImage;

- (void)updateImage:(CGImageRef)anImage;
- (void)notifyImageChanged;
- (void)abortImage;

- (void)startAnimation;
- (void)stopAnimation;

- (void)drawInRect:(NSRect)rect;
- (void)drawFlippedInRect:(NSRect)rect;

- (NSArray *)observers;
    // Returns a snapshot of the array of observers
- (unsigned int)observerCount;
    // Returns the number of observers for this image (more efficient than [[self observers] count])

- (void)addObserver:(id <OIImageObserver, OFWeakRetain>)anObserver;
    // Subscribed anObserver to receive messages described in the OIImageObserver protocol.  The new observer is  retained.  The new observer is responsible for unsubscribing itself so that it can eventually be deallocated.

- (void)removeObserver:(id <OIImageObserver, OFWeakRetain>)anObserver;
    // Unsubscribes anObserver such that it will not receive the messages described in the OIImageObserver protocol and is no longer retained by the image.

- (void)setPixelData:(NSData *)newPixelData;
    // This data provides a pointer to the image backing store so you can render directly into it.

@end
