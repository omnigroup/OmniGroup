// Copyright 2005-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 8/31/05.

#import "NSView-OQExtensions.h"

#import "CIContext-OQExtensions.h"
#import "OQTargetAnimation.h"

RCS_ID("$Id$")

@implementation NSView (OQExtensions)

- (CIImage *)newImage;
{
    return [self newImageFromRect:[self bounds]];
}

- (CIImage *)newImageFromRect:(NSRect)rect;
{
    return [self newImageFromRect:rect compatibleWithWindow:[self window]];
}

- (CIImage *)newImageFromRect:(NSRect)rect compatibleWithWindow:(NSWindow *)targetWindow;
{
    return [self newImageFromRect:rect compatibleWithWindow:targetWindow opaque:YES];
}

// Returns a new retained CIImage that has the contents of the rect specified.  This image will be transparent in the appropriate spots.  If an opaque image is requested, the returned image will contain rendering from the opaque ancestor of the receiver.  The targetWindow is the window into which the image will be drawn, which may be different from the window (possibly none) in which the receiver resides.  The returned image will have the passed in rect's origin at its origin.
- (CIImage *)newImageFromRect:(NSRect)rect compatibleWithWindow:(NSWindow *)targetWindow opaque:(BOOL)opaque;
{
    CGContextRef windowContext = [[targetWindow graphicsContext] graphicsPort];
    
    NSView *viewToDraw = self;
    NSRect  rectToDraw = rect;
    if (opaque) {
	viewToDraw = [self opaqueAncestor];
	rectToDraw = [self convertRect:rect toView:viewToDraw];
    }
    
    // Might need to do something extra to deal with scaleable UI.  This is an attempt to get rid of any view-level scaling so that the output image has the appropriate number of pixels.
    NSRect windowRect = [viewToDraw convertRect:rectToDraw toView:nil];
    
    CGLayerRef layer = CGLayerCreateWithContext(windowContext, (CGSize){windowRect.size.width, windowRect.size.height}, NULL);
    CGContextRef layerCtx = CGLayerGetContext(layer);

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort:layerCtx flipped:[viewToDraw isFlipped]];
    @try {
	CGContextTranslateCTM(layerCtx, -rectToDraw.origin.x, -rectToDraw.origin.y);
	
	// This will apply the receiver's bounds transformation according to the documentation (since the context we are drawing into isn't the window context).  In particular, if the view is flipped, it will scale the y axis by -1 and and transform by the height of the view.  We want the flipping, so that it comes out right side up in the image, but we dno't want to be shifted by the entire height of the view since we aren't drawing the whole thing.  We'll counteract this transform here.
	if ([viewToDraw isFlipped]) {
	    NSRect bounds = [viewToDraw bounds];
	    CGContextTranslateCTM(layerCtx, 0, NSMaxY(rectToDraw) - NSMaxY(bounds) + NSMinY(rectToDraw));
	}
	
	[viewToDraw displayRectIgnoringOpacity:rectToDraw inContext:context];
    } @catch (NSException *exc) {
	NSLog(@"Caught %@ while drawing image", exc);
    }
    
    CIImage *image = [[CIImage alloc] initWithCGLayer:layer];
    CFRelease(layer);
    
    return image;
}

// Either view can be nil.  The frames of the two views are not changed.
// NOTE: This method seems to not work for WebViews since they draw w/o CSS information during fading (possibly since they've been marked as 'hidden')
- (void)fadeOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview;
{
    if (oldSubview == newSubview)
	return;
    
    if (![[self window] isVisible]) {
	// Old view doesn't have a window or the window is off screen.  NSView -replaceSubview:with: doesn't like nil arguments.  The NSView method would preserve the ordering of the view relative to other subviews, but we don't in the case that we animate, so we don't bother to do so here either.
	[oldSubview removeFromSuperview];
	if (newSubview)
	    [self addSubview:newSubview];
    }
    
    NSMutableArray *animations = [NSMutableArray array];
    
    // NSViewAnimation will set the hidden bit on the view when fading out; we remember the old view's hidden bit and restore it (and will consider a hidden old view as being nil).
    BOOL oldSubviewHidden = [oldSubview isHidden];
    if (oldSubview && !oldSubviewHidden) {
	NSDictionary *animation = [[NSDictionary alloc] initWithObjectsAndKeys:
	    oldSubview, NSViewAnimationTargetKey,
	    NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
	    nil];
	[animations addObject:animation];
	[animation release];
    }
    
    if (newSubview) {
	OBASSERT(![newSubview isHidden]); // Fading in a hidden view?  Should we ignore it or should we unhide the view?
	NSDictionary *animation = [[NSDictionary alloc] initWithObjectsAndKeys:
	    newSubview, NSViewAnimationTargetKey,
	    NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
	    nil];
	[animations addObject:animation];
	[animation release];
	[self addSubview:newSubview];
    }

    if ([animations count]) {
	NSViewAnimation *animation = [[NSViewAnimation alloc] initWithViewAnimations:animations];	
	[animation setAnimationBlockingMode:NSAnimationBlocking];
	[animation setDuration:0.15f];
	[animation startAnimation];
	[animation release];
    }
    
    [oldSubview setHidden:oldSubviewHidden];
    [oldSubview removeFromSuperview];
}

typedef struct _TransitionUserInfo {
    BOOL reverse;
    CIImage *oldImage;
    CIImage *newImage;
    CIFilter *filter;
#ifdef DEBUG
    unsigned int frameCount;
#endif
} TransitionUserInfo;

- (void)transitionOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview;
{
    [self transitionOutAndReplaceSubview:oldSubview withView:newSubview reverse:NO];
}

- (void)transitionOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview reverse:(BOOL)reverse;
{
#if 0 && defined(DEBUG_bungi)
    {
	NSArray *names = [CIFilter filterNamesInCategory:kCICategoryTransition];
	NSLog(@"transitions = %@", names);
	
	unsigned int nameIndex = [names count];
	while (nameIndex--) {
	    NSString *name = [names objectAtIndex:nameIndex];
	    
	    CIFilter *filter = [CIFilter filterWithName:name];
	    NSLog(@"filter %@:", name);
	    NSLog(@"  inputs = %@", [[filter inputKeys] sortedArrayUsingSelector:@selector(compare:)]);
	    NSLog(@"  outputs = %@", [[filter outputKeys] sortedArrayUsingSelector:@selector(compare:)]);
	}
    }
#endif
    
    // Later, we may be able to handle either of these being nil by taking a snapshot of ourselves in the same area.
    OBPRECONDITION(oldSubview);
    OBPRECONDITION([oldSubview superview] == self);
    OBPRECONDITION(newSubview);
    OBPRECONDITION(oldSubview && newSubview && NSEqualRects([oldSubview frame], [newSubview frame])); // Simplifies things a lot...
    OBPRECONDITION(oldSubview && NSEqualRects([self bounds], [oldSubview frame])); // Means that we can hide ourselves while animating.
    
    if (oldSubview == newSubview)
	return;
    
    if (![[self window] isVisible]) {
	// Old view doesn't have a window or the window is off screen.  NSView -replaceSubview:with: doesn't like nil arguments.  The NSView method would preserve the ordering of the view relative to other subviews, but we don't in the case that we animate, so we don't bother to do so here either.
	[oldSubview removeFromSuperview];
	if (newSubview)
	    [self addSubview:newSubview];
    }
    
    NSTimeInterval duration = 0.3;
    if ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)
	duration = 2.0f;
    
    TransitionUserInfo info;
    memset(&info, 0, sizeof(info));
    info.reverse = reverse;
    
    // Capture an image of the old view
    info.oldImage = [oldSubview newImage];
    //[[[[self window] graphicsContext] CIContext] writePNGImage:info.oldImage fromRect:[info.oldImage extent] toURL:[NSURL fileURLWithPath:@"/tmp/old-image.png"]];
    
    // Replace the old view with the new one.
    [oldSubview removeFromSuperview];
    [self addSubview:newSubview];
    
    // Capture an image of the new view
    info.newImage = [newSubview newImage];
    //[[[[self window] graphicsContext] CIContext] writePNGImage:info.newImage fromRect:[info.newImage extent] toURL:[NSURL fileURLWithPath:@"/tmp/new-image.png"]];

    CGRect extent;
    if (info.oldImage && info.newImage)
        extent = CGRectUnion([info.oldImage extent], [info.newImage extent]);
    else if (info.oldImage)
        extent = [info.oldImage extent];
    else if (info.newImage)
        extent = [info.newImage extent];
    else {
        OBASSERT_NOT_REACHED("Should only both be nil if both views were nil, and then we'd have bailed at the top");
        return;
    }

    OQTargetAnimation *animation = [[OQTargetAnimation alloc] initWithTarget:self selector:@selector(_setTransitionProgress:forAnimation:userInfo:)];
    [animation setDuration:duration];
    [animation setFrameRate:0.0f];
    
    CIColor *white = [CIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
    
    CIFilter *swipe = [CIFilter filterWithName:@"CISwipeTransition"];
    
    [swipe setValue:[NSNumber numberWithFloat:0.0f] forKey:@"inputAngle"];
    
    if (info.reverse) {
	[swipe setValue:info.newImage forKey:@"inputImage"];
	[swipe setValue:info.oldImage forKey:@"inputTargetImage"];
    } else {
	[swipe setValue:info.oldImage forKey:@"inputImage"];
	[swipe setValue:info.newImage forKey:@"inputTargetImage"];
    }
    [swipe setValue:white forKey:@"inputColor"];
    [swipe setValue:[NSNumber numberWithFloat:50.0f] forKey:@"inputWidth"];
    [swipe setValue:[NSNumber numberWithFloat:0.0f] forKey:@"inputOpacity"];
    [swipe setValue:[CIVector vectorWithValues:&extent.origin.x count:4] forKey:@"inputExtent"];

    info.filter = [swipe retain];

    [animation setUserInfo:&info];
    [animation startAnimation];
    
    // Since we are blocking, we are now done
#ifdef DEBUG
    NSLog(@"animation processed %d frames", info.frameCount);
#endif
    
    [animation release];
    animation = nil;
    OB_UNUSED_VALUE(animation);
    
    [info.oldImage release];
    [info.newImage release];
    [info.filter release];

    [[self window] setViewsNeedDisplay:YES]; // ???
}

- (void)_setTransitionProgress:(NSAnimationProgress)progress forAnimation:(OQTargetAnimation *)animation userInfo:(void *)userInfo;
{
//    NSLog(@"progress = %f, animation = %@, userInfo = %p", progress, animation, userInfo);

    TransitionUserInfo *info = userInfo;
    
    //NSLog(@"animation progress %f", progress);
    
#ifdef DEBUG
    info->frameCount++;
#endif
    
    float filterTime = progress;
    if (info->reverse)
	filterTime = 1.0f - progress;
    
    [info->filter setValue:[NSNumber numberWithFloat:filterTime] forKey:@"inputTime"];
    CIImage *image = [info->filter valueForKey:@"outputImage"];
    
    NSWindow *window = [self window];
    if (0) {
	static unsigned int x = 0;
	CFStringRef outputURLString = (CFStringRef)[NSString stringWithFormat:@"file:///tmp/x-%03d.png", x++];
	NSLog(@"%@", outputURLString);
	CFURLRef destURL = CFURLCreateWithString(kCFAllocatorDefault, outputURLString, NULL);
	CGImageDestinationRef dest = CGImageDestinationCreateWithURL(destURL, kUTTypePNG, 1, NULL);
	CFRelease(destURL);
	
	CGImageRef destImage = [[[window graphicsContext] CIContext] createCGImage:image fromRect:[image extent]];
	
	CGImageDestinationAddImage(dest, destImage, NULL);
	CFRelease(destImage);
	
	if (!CGImageDestinationFinalize(dest))
	    NSLog(@"finalize failed");
	CFRelease(dest);
    }
    
    {
	NSDisableScreenUpdates();
	
	// Update the window frame
#define INTERP(comp) ((1.0f - progress)*transition.oldWindowFrame.comp + progress*transition.newWindowFrame.comp)
//	NSRect frame;
//	frame.origin.x = INTERP(origin.x);
//	frame.origin.y = INTERP(origin.y);
//	frame.size.width = INTERP(size.width);
//	frame.size.height = INTERP(size.height);
//	[window setFrame:frame display:YES animate:NO];
	
	[self lockFocus];
	//[[NSColor redColor] set];
	//NSRectFill([preferenceBox bounds]);
	//NSLog(@"ctx = %@, img = %@, extent = %f, %f, %f, %f", [[window graphicsContext] CIContext], image, [image extent].origin.x, [image extent].origin.y, [image extent].size.width, [image extent].size.height);
	[[[window graphicsContext] CIContext] drawImage:image atPoint:(CGPoint){0,0} fromRect:[image extent]];
	[self unlockFocus];
		[window flushWindow];
		[[window graphicsContext] flushGraphics];
	NSEnableScreenUpdates();
    }
}

// Mostly for debugging; should make a NSError version
- (BOOL)writePNGImageToFile:(NSString *)path;
{
    OBPRECONDITION([self window]); // Need a CIContext.
    
    CIImage *image = [self newImage];
    NSWindow *window = [self window];
    
    BOOL status = [[[window graphicsContext] CIContext] writePNGImage:image fromRect:[image extent] toURL:[NSURL fileURLWithPath:path]];
    [image release];
    return status;
}

@end
