// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <QuartzCore/CALayer.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIView.h>
#endif

#define OQCurrentAnimationValueInLayer(layer,field) ({ __typeof__(layer) p = (id)layer.presentationLayer; p ? p.field : layer.field; })
#define OQCurrentAnimationValue(field) OQCurrentAnimationValueInLayer(self, field)

@class NSString, NSMutableString;

typedef BOOL (^OQRenderLayerFilter)(CALayer *layer);

@interface CALayer (OQExtensions)
- (CALayer *)rootLayer;
- (BOOL)isSublayerOfLayer:(CALayer *)layer;
- (id)sublayerNamed:(NSString *)name;
- (NSArray *)sublayersNamed:(NSString *)name;
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

- (void)sortSublayersByZOrder;

- (BOOL)isModelLayer;

@property(nonatomic,readonly,class) OQRenderLayerFilter defaultRenderLayerFilter;
- (void)renderRect:(CGRect)rect inContextIgnoringCache:(CGContextRef)ctx;
- (void)renderRect:(CGRect)rect inContextIgnoringCache:(CGContextRef)ctx useAnimatedValues:(BOOL)useAnimatedValues;
- (void)renderRect:(CGRect)rect inContextIgnoringCache:(CGContextRef)ctx filter:(OQRenderLayerFilter)filter useAnimatedValues:(BOOL)useAnimatedValues;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSImage *)imageForRect:(NSRect)rect useAnimatedValues:(BOOL)useAnimatedValues;
- (NSImage *)imageForRect:(NSRect)rect flipped:(BOOL)flipped filter:(OQRenderLayerFilter)filter useAnimatedValues:(BOOL)useAnimatedValues;
- (void)writeImagesAndOpen;
#endif

- (BOOL)drawInVectorContext:(CGContextRef)ctx; // return YES from your subclass's override of this method.

@end

#import <QuartzCore/CAMediaTimingFunction.h>
@interface CAMediaTimingFunction (OQExtensions)
+ (id)functionCompatibleWithDefault;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (CAMediaTimingFunction *)mediaTimingFunctionForUIViewAnimationCurve:(UIViewAnimationCurve)uiViewAnimationCurve;
#endif
@end

@interface NSObject (CALayerOQDelegate)

- (void)layoutLayer:(CALayer *)layer inRect:(CGRect)rect;
- (void)drawLayer:(CALayer *)layer inVectorContext:(CGContextRef)ctx;

@end

// When OQ_ANIMATION_LOGGING_ENABLED is enabled in the .m file, can be used to enable logging for certain layers. Otherwise, this is a no-op.
extern void OQSetAnimationLoggingEnabledForLayer(CALayer *layer, BOOL enabled);
