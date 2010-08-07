// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CALayer.h>

#define OQCurrentAnimationValueInLayer(layer,field) ({ __typeof__(layer) p = (id)layer.presentationLayer; p ? p.field : layer.field; })
#define OQCurrentAnimationValue(field) OQCurrentAnimationValueInLayer(self, field)

@class NSString, NSMutableString;

@interface CALayer (OQExtensions)
- (CALayer *)rootLayer;
- (BOOL)isSublayerOfLayer:(CALayer *)layer;
- (id)sublayerNamed:(NSString *)name;
//- (void)hideLayersBasedOnPotentiallyVisibleRect:(CGRect)r;
- (NSUInteger)countLayers;
- (NSUInteger)countVisibleLayers;
- (void)logGeometry;
- (void)logLocalGeometry;
- (void)logAncestorGeometry;
- (void)appendGeometry:(NSMutableString *)str depth:(unsigned)depth;
- (void)appendLocalGeometry:(NSMutableString *)str;
- (BOOL)ancestorHasAnimationForKey:(NSString *)key;

- (void)recursivelyRemoveAnimationForKey:(NSString *)key;
- (void)recursivelyRemoveAllAnimations;

- (BOOL)isModelLayer;
- (BOOL)isPresentationLayer;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (void)renderInContextIgnoringCache:(CGContextRef)ctx;
- (void)renderInContextIgnoringCache:(CGContextRef)ctx useAnimatedValues:(BOOL)useAnimatedValues;
- (void)renderInContextIgnoringHiddenIgnoringCache:(CGContextRef)ctx useAnimatedValues:(BOOL)useAnimatedValues;
- (NSImage *)imageForRect:(NSRect)rect useAnimatedValues:(BOOL)useAnimatedValues;
- (void)writeImagesAndOpen;
#endif

@end

#import <QuartzCore/CAMediaTimingFunction.h>
@interface CAMediaTimingFunction (OQExtensions)
+ (id)functionCompatibleWithDefault;
@end
