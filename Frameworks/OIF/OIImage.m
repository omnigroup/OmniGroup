// Copyright 1998-2005, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIImage.h>

#import <OmniFoundation/OFObject-Queue.h> // Working around compiler bug
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

RCS_ID("$Id$")

@implementation OIImage

static OWContentType *contentType;
static BOOL colorSyncEnabled;

+ (void)initialize;
{
    OBINITIALIZE;

    contentType = [OWContentType contentTypeForString:@"omni/image"];
    colorSyncEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"OIColorSyncEnabled"];
}

+ (OWContentType *)contentType;
{
    return contentType;
}

+ (CGImageRef)createCGImageFromBitmapData:(const void *)bitmapData width:(NSUInteger)imageWidth height:(NSUInteger)imageHeight bitsPerSample:(NSUInteger)bitsPerSample samplesPerPixel:(NSUInteger)samplesPerPixel;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
    return NULL;
#if 0    
    OBPRECONDITION(bitmapData != NULL);
    
//    NSLog(@"%s, bitmapData=%p, imageWidth=%d, imageHeight=%d, bitsPerSample=%d, samplesPerPixel=%d", _cmd, bitmapData, imageWidth, imageHeight, bitsPerSample, samplesPerPixel);
    
    // Create CGImageRef
    NSUInteger bytesPerRow = imageWidth * bitsPerSample * samplesPerPixel / 8;
	
	CGColorSpaceRef colorspace;
	if (samplesPerPixel < 3)
		colorspace = CGColorSpaceCreateDeviceGray();
	else
		colorspace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(self, bitmapData, bytesPerRow * imageHeight, NULL);
    CGFloat decode[8] = { 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0 };
    
    CGImageRef image = CGImageCreate(imageWidth, imageHeight, bitsPerSample, bitsPerSample * samplesPerPixel, bytesPerRow, colorspace, (samplesPerPixel == 4 ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNone), provider, decode, NO, kCGRenderingIntentDefault);
    if (image == NULL)
        NSLog(@"-[%@ %s], could not create CGImageRef", OBShortObjectDescription(self), _cmd);
    
    CGColorSpaceRelease(colorspace);
    CGDataProviderRelease(provider);
    
    return image;
#endif
}

// Gamma

+ (double)sourceGamma;
    // Standard is sRGB, approximately 2.2
{
    return 2.2;
}

+ (double)targetGamma;
    // Now that we have ColorSync, this is always sRGB also
{
    return 2.2;
}

+ (double)gammaCorrection;
    // +sourceGamma / +targetGamma
{
    return 1.0; // [self sourceGamma] / [self targetGamma]
}

+ (void)fillGammaCorrectionTable:(OIImageGammaCorrectionTable)gammaCorrectionTable withSamplesOfGamma:(double)gamma;
{
    NSUInteger index;

    index = 256;
    if (gamma == 1.0) {
        // Now that this is the common case, let's optimize it a bit.  (Of course, ideally the caller wouldn't use a gamma table at all in this case.)
        while (index--)
            gammaCorrectionTable[index] = index;
    } else {
        while (index--)
            gammaCorrectionTable[index] = pow(((double)(index) / 255.0), gamma) * 255;
    }
}

+ (BOOL)colorSyncEnabled;
{
    return colorSyncEnabled;
}

// Init and dealloc

- (id)initWithSourceContent:(OWContent *)sourceContent;
{
    static NSString *imageContentName = nil;
    
    if (imageContentName == nil)
        imageContentName = [NSLocalizedStringFromTableInBundle(@"Image", @"OIF", [OIImage bundle], "content or task type name for image content") retain];

    if (!(self = [super initWithName:imageContentName]))
	return nil;

    haveSize = NO;
    imageSize = NSZeroSize;
    cgImage = NULL;
    cgImageLock = [[NSLock alloc] init];
    _observers = [[NSMutableArray alloc] initWithCapacity:1];
    observersLock = [[NSLock alloc] init];
    _pixelData = nil;
    _sourceContent = [sourceContent retain];
    
    return self;
}

- init;
{
    return [self initWithSourceContent:nil];
}

- (void)dealloc;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSUInteger observerIndex, observerCount;

    // Thread safety?
    if (cgImage != NULL)
        CGImageRelease(cgImage);
        
    [cgImageLock release];
    observerCount = [_observers count];
    for (observerIndex = 0; observerIndex < observerCount; observerIndex++) {
        id <OWFWeakRetain> anObserver;
        
        anObserver = [_observers objectAtIndex:observerIndex];
        [anObserver decrementWeakRetainCount];
    }
    [_observers release];
    [observersLock release];
    [_pixelData release];
    [_sourceContent release];
#endif
    [super dealloc];
}


// Info

- (OWContent *)sourceContent;
{
    return _sourceContent;
}

- (BOOL)hasSize;
{
    return haveSize;
}

- (NSSize)size;
{
    return imageSize;
}

- (void)setSize:(NSSize)newSize;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSArray *observers;
    NSUInteger observerIndex, observerCount;
    
    haveSize = YES;
    imageSize = newSize;

    observers = [self observers];
    observerCount = [observers count];
    for (observerIndex = 0; observerIndex < observerCount; observerIndex++) {
        OFObject <OIImageObserver> *observer;

        observer = [observers objectAtIndex:observerIndex];
        [observer imageDidSize:self];
    }
#endif
}

- (CGImageRef)retainedCGImage;
{
    [cgImageLock lock];
    CGImageRef retainedImage = CGImageRetain(cgImage);
    [cgImageLock unlock];
    
    return retainedImage;
}

- (NSImage *)nsImage;
{
    // TODO: Optimize me
    NSImage *image = [[NSImage alloc] initWithSize:imageSize];
    [image lockFocus];
    [self drawInRect:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
    [image unlockFocus];
    
    return [image autorelease];
}

- (void)updateImage:(CGImageRef)anImage;
{
    [cgImageLock lock];
    NS_DURING {
        if (cgImage != anImage) {
            if (cgImage != NULL)
                CGImageRelease(cgImage);
            cgImage = CGImageRetain(anImage);
        }
    } NS_HANDLER {
        NSLog(@"-[OIImage updateImage:] caught exception: %@", [localException reason]);
    } NS_ENDHANDLER;
    [cgImageLock unlock];
    
    [self notifyImageChanged];
}

- (void)notifyImageChanged;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSArray *observers = [self observers];
    NSUInteger observerCount = [observers count];
    NSUInteger observerIndex;
    
    for (observerIndex = 0; observerIndex < observerCount; observerIndex++) {
        OFObject <OIImageObserver> *observer = [observers objectAtIndex:observerIndex];
	[observer imageDidUpdate:self];
    }
#endif
}

- (void)abortImage;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSArray *observers;
    NSUInteger observerIndex, observerCount;
    
    haveSize = YES; // Well, as much as we ever will...

    observers = [self observers];
    observerCount = [observers count];
    for (observerIndex = 0; observerIndex < observerCount; observerIndex++) {
        OFObject <OIImageObserver> *observer;

        observer = [observers objectAtIndex:observerIndex];
	[observer imageDidAbort:self];
    }
#endif
}

- (void)startAnimation;
{
    // Only animating subclasses really care.
}

- (void)stopAnimation;
{
    // Only animating subclasses really care.
}

static inline CGRect _nsRectToCGRect(NSRect aRect)
{
    return CGRectMake(aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height);
}

- (void)drawInRect:(NSRect)rect;
{
    CGContextRef cgContext = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextDrawImage(cgContext, _nsRectToCGRect(rect), cgImage);
}

- (void)drawFlippedInRect:(NSRect)rect;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    CGContextRef cgContext = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(cgContext); {
        CGContextTranslateCTM(cgContext, 0.0, NSMaxY(rect));
        CGContextScaleCTM(cgContext, 1.0, -1.0);
        
        rect.origin.y = 0.0; // We've translated ourselves so it's zero
        [self drawInRect:rect];
    } CGContextRestoreGState(cgContext);
#endif
}

- (NSArray *)observers;
    // Returns a snapshot of the observers array
{
    NSArray *observers;

    [observersLock lock];
    observers = [[NSArray alloc] initWithArray:_observers];
    [observersLock unlock];
    return [observers autorelease];
}

- (NSUInteger)observerCount;
    // Returns the number of observers for this image (more efficient than [[self observers] count])
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSUInteger observerCount;

    [observersLock lock];
    observerCount = [_observers count];
    [observersLock unlock];
    return observerCount;
#endif
}

- (void)addObserver:(id <OIImageObserver, OWFWeakRetain>)anObserver;
    // Subscribed anObserver to receive messages described in the OIImageObserver protocol.  The new observer is  retained.  The new observer is responsible for unsubscribing itself so that it can eventually be deallocated.
{
    [observersLock lock];
    OBASSERT([_observers indexOfObjectIdenticalTo:anObserver] == NSNotFound);
    [_observers addObject:anObserver];
    [observersLock unlock];
    [anObserver incrementWeakRetainCount];
}

- (void)removeObserver:(id <OIImageObserver, OWFWeakRetain>)anObserver;
    // Unsubscribes anObserver such that it will not receive the messages described in the OIImageObserver protocol and is no longer retained by the image.
{
    [anObserver decrementWeakRetainCount];
    [observersLock lock];
    OBASSERT([_observers indexOfObjectIdenticalTo:anObserver] != NSNotFound);
    [_observers removeObjectIdenticalTo:anObserver];
    [observersLock unlock];
}

- (void)setPixelData:(NSData *)newPixelData;
{
    [cgImageLock lock];
    if (_pixelData != newPixelData) {
        [_pixelData release];
        _pixelData = [newPixelData retain];
    }
    [cgImageLock unlock];
}


// OWContent protocol

- (OWContentType *)contentType;
{
    return contentType;
}

- (BOOL)contentIsValid;
{
    return YES;
}

- (BOOL)endOfData
{
#warning TODO make this accurate
    return haveSize && ( _sourceContent? [_sourceContent endOfData] : YES );
}

// NSCopying protocol

- copyWithZone:(NSZone *)newZone
{
    // We're immutable once we've been fully created
    return [self retain];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:haveSize ? @"YES" : @"NO" forKey:@"haveSize"];
    if (cgImage)
	[debugDictionary setObject:[NSString stringWithFormat:@"%p", cgImage] forKey:@"cgImage"];
    [debugDictionary setObject:[self observers] forKey:@"observers"];

    return debugDictionary;
}

@end
