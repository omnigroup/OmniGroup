// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQAlphaScaleFilter.h>

#import <QuartzCore/QuartzCore.h>

RCS_ID("$Id$");

NSString * const OQAlphaScaleFilterName = @"OQAlphaScaleFilter";
NSString * const OQAlphaScaleFilterValueKey = @"inputScale";

@implementation OQAlphaScaleFilter

- (void)dealloc;
{
    [inputImage release];
    inputImage = nil;
    [inputScale release];
    inputScale = nil;
    [super dealloc];
}

- (CIImage *)outputImage
{
    CISampler *src = [CISampler samplerWithImage:inputImage];
    return [self apply:[[self class] kernel], src, inputScale, kCIApplyOptionDefinition, [src definition], nil];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OQAlphaScaleFilter *copy = [super copyWithZone:zone];
    copy->inputImage = [inputImage copy];
    copy->inputScale = [inputScale copy];
    return copy;
}

@end
