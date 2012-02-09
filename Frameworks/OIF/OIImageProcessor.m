// Copyright 1998-2005, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIImageProcessor.h>

#import <math.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSImage.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

#import <OIF/OIImage.h>

RCS_ID("$Id$")

@interface OIImageProcessor (Private)
- (void)_addOmniImageToPipeline;
- (void)_mainThreadProcessAppKitImageData:(NSData *)someImageData usingLock:(NSConditionLock *)profileLock;
@end

enum {
    PROCESSING_NOT_DONE,
    PROCESSING_DONE,
};

@implementation OIImageProcessor

unsigned int OIImageProcessorCheckTimeEveryNRows = 16;

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super initWithContent:initialContent context:aPipeline]))
        return nil;

    // Hmmm, should images be in a "content" zone or in a "UI" zone?
    omniImage = [[OIImage alloc/*WithZone:OWContentZone*/] initWithSourceContent:initialContent];
    reprocessCursor = [[initialContent dataCursor] retain];
    
    return self;
}

- (void)dealloc;
{
    [reprocessCursor release];
    
    // Thread safety?
    if (lastImage != NULL)
        CGImageRelease(lastImage);

    [omniImage release];
    [omniImageContent release];
    [super dealloc];
}

// These methods are called by our subclasses

- (void)addOmniImageToPipelineIfIncrementalDisplayIsDesired;
{
    if (![pipeline contextObjectForKey:@"DisableIncrementalDisplay"])
        [self _addOmniImageToPipeline];
}

- (void)setImage:(CGImageRef)anImage;
{
    if (lastImage != anImage) {
        if (lastImage != NULL)
            CGImageRelease(lastImage);
        lastImage = CGImageRetain(anImage);
    }
}

- (void)setImageSize:(NSSize)newImageSize;
{
    [omniImage setSize:newImageSize];
}

- (BOOL)drawIntervalReached;
{
    return [NSDate timeIntervalSinceReferenceDate] - lastDrawTimeInterval >
           drawInterval;
}

- (void)flushImage;
{
    NSTimeInterval nowTimeInterval;

    needUpdate = YES;

    nowTimeInterval = [NSDate timeIntervalSinceReferenceDate];
    if (nowTimeInterval - lastDrawTimeInterval > drawInterval) {
        lastDrawTimeInterval = nowTimeInterval;
        [self updateImage:lastImage];
    }
}

- (void)updateImage:(CGImageRef)anImage;
{
    needUpdate = NO;
    [self setImage:anImage];
    [omniImage updateImage:anImage];
}

- (void)processImageDataUsingAppKit;
    // Parses the image data using the AppKit
{
    NSData *imageData;
    NSConditionLock *processingLock;

    imageData = [reprocessCursor readAllData];
    [reprocessCursor release];
    reprocessCursor = nil;
    
    processingLock = [[NSConditionLock alloc] initWithCondition:PROCESSING_NOT_DONE];
    [self mainThreadPerformSelector:@selector(_mainThreadProcessAppKitImageData:usingLock:) withObject:imageData withObject:processingLock];
    [processingLock lockWhenCondition:PROCESSING_DONE];
    [processingLock unlock];
    [processingLock release];
}

- (void)processColorSyncProfileUsingAppKit;
    // Processes the color sync profile data using the AppKit
{
    if ([OIImage colorSyncEnabled] && reprocessCursor != nil)
        [self processImageDataUsingAppKit];
}

- (BOOL)expectsBitmapResult;
{
    return NO;
}

//

- (void)fillGammaCorrectionTable:(OFByte[256])gammaCorrectionTable withSamplesOfGamma:(double)gamma;
{
    [OIImage fillGammaCorrectionTable:gammaCorrectionTable withSamplesOfGamma:gamma];
}

// OWProcessor subclass

- (void)processBegin;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    NSUserDefaults *userDefaults;

    [super processBegin];
    
    userDefaults = [NSUserDefaults standardUserDefaults];

    if ([pipeline contextObjectForKey:@"DisableIncrementalDisplay"])
	drawInterval = 1e+10;
    else
	drawInterval = [userDefaults floatForKey:@"OIImageProcessorDrawInterval"];
    OIImageProcessorCheckTimeEveryNRows = [userDefaults integerForKey:@"OIImageProcessorCheckTimeEveryNRows"];
    lastDrawTimeInterval = [NSDate timeIntervalSinceReferenceDate];
#endif
}

- (void)processEnd;
{
    if (needUpdate)
	[self updateImage:lastImage];
    if ([pipeline contextObjectForKey:@"DisableIncrementalDisplay"])
	[self _addOmniImageToPipeline];
    [super processEnd];
}

- (void)processAbort;
{
    [omniImage abortImage];
    [super processAbort];
}

//

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:omniImage forKey:@"omniImage"];
    [debugDictionary setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:lastDrawTimeInterval] forKey:@"lastDrawTimeInterval"];

    return debugDictionary;
}

@end

@implementation OIImageProcessor (Private)

- (void)_addOmniImageToPipeline;
{
    if (omniImageContent == nil) {
        omniImageContent = [(OWContent *)[OWContent alloc] initWithContent:omniImage];
        [omniImageContent markEndOfHeaders];
    }
    [pipeline addContent:omniImageContent fromProcessor:self flags:OWProcessorTypeDerived];
}

- (void)_mainThreadProcessAppKitImageData:(NSData *)someImageData usingLock:(NSConditionLock *)profileLock;
{
    // TODO: Implement me using CGImageCreateCopyWithColorSpace(cgImage, CGColorSpaceCreateICCBased(...))
#if 0
    NSImage *profiledImage = nil;

    NS_DURING {
        NSArray *representations;
        NSSize pixelSize;
        unsigned int representationIndex, representationCount;
        BOOL needsBitmapImageRep;

        // The easiest way for us to do this right now is simply to hand the image data off to the AppKit
        profiledImage = [[NSImage alloc] initWithData:someImageData];

        // Unfortunately, the AppKit scales the representation size based on DPI, which we don't want.  Set it back.
        pixelSize = [omniImage size];
        representations = [profiledImage representations];
        representationCount = [representations count];
        needsBitmapImageRep = [self expectsBitmapResult];
        for (representationIndex = 0; representationIndex < representationCount; representationIndex++) {
            NSImageRep *representation;

            representation = [representations objectAtIndex:representationIndex];
            [representation setSize:pixelSize];
            if (needsBitmapImageRep && [representation isKindOfClass:[NSBitmapImageRep class]])
                profiledImageRep = 
                needsBitmapImageRep = NO;
        }

        if (needsBitmapImageRep) {
            NSLog(@"%@: Not processing ICC profile: AppKit did not correctly parse this image", [pipeline logDescription]);
        } else {
            // Set the parameters we normally do on our images
            [profiledImage setDataRetained:YES];
            [profiledImage setCachedSeparately:YES];
            [profiledImage lockFocus]; // Ensure we create a cached representation or scrolling will be deathly slow!
            [profiledImage unlockFocus];
            [self setImageRep:profiledImageRep];
        }
    } NS_HANDLER {
        NSLog(@"%@: Exception processing ICC profile: %@", [pipeline logDescription], [localException reason]);
    } NS_ENDHANDLER;
    [profileLock lock];
    [profileLock unlockWithCondition:PROCESSING_DONE];
    [profiledImage release];
#endif
}

@end
