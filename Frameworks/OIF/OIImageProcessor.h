// Copyright 1997-2005, 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWDataStreamProcessor.h>
#import <ApplicationServices/ApplicationServices.h> // For CGImageRef

@class NSMutableArray;
@class NSImage;
@class OIImage;

#import <Foundation/NSDate.h> // For NSTimeInterval
#import <Foundation/NSGeometry.h> // For NSSize

@interface OIImageProcessor : OWDataStreamProcessor
{
    OIImage *omniImage;
    OWContent *omniImageContent;
    OWDataStreamCursor *reprocessCursor;
@private
    CGImageRef lastImage;
    BOOL needUpdate;

    NSTimeInterval lastDrawTimeInterval;
    NSTimeInterval drawInterval;
}

// These methods are called by our subclasses.

- (void)addOmniImageToPipelineIfIncrementalDisplayIsDesired;

- (void)setImage:(CGImageRef)anImage;
    // set the image, but don't actually try to draw it or anything.

- (void)setImageSize:(NSSize)newImageSize;
    // Set this as soon as the image dimensions are known.

- (BOOL)drawIntervalReached;
    // Returns YES when it's time to draw again.

- (void)flushImage;
    // Call this while decoding the image into resultImage.  It will only call updateImage: if it has been OmniImageProcessorDrawInterval seconds since the last updateImage:.

- (void)updateImage:(CGImageRef)anImage;
    // This manually flushes the image to the screen.

- (void)processImageDataUsingAppKit;
    // Processes the image data using the AppKit

- (void)processColorSyncProfileUsingAppKit;
    // Processes the color sync profile data using the AppKit

- (BOOL)expectsBitmapResult;
    // Returns YES if this processor expects a bitmap image representation in the result.  This is used to double-check AppKit parsing to ensure it doesn't crash when misparsing images.

// Deprecated method:  moved to OIImage as a class method
// - (void)fillGammaCorrectionTable:(OFByte[256])gammaCorrectionTable withSamplesOfGamma:(double)gamma;

@end

extern unsigned int OIImageProcessorCheckTimeEveryNRows;
