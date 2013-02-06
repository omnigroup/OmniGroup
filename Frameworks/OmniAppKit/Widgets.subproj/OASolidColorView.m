// Copyright 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASolidColorView.h>
#import <OmniAppKit/NSColor-OAExtensions.h>

RCS_ID("$Id$")

@implementation OASolidColorView

#pragma mark - Init and dealloc

- (void)dealloc;
{
    [_backgroundColor release];
    
    OBASSERT_NULL(_nonretained_windowBackingPropertiesObserver); // This has a +1 retain on us by virtue of the block reference, so the only way we should die is if we got -viewWillMoveToWindow:nil.
    
    [super dealloc];
}

#pragma mark - API

- (void)_updateLayerBackgroundColor:(CALayer *)layer;
{
    if (layer) {
        NSColor *convertedBackgroundColor = [_backgroundColor colorUsingColorSpace:self.window.colorSpace];
        CGColorRef colorRef = [convertedBackgroundColor newCGColor];
        if (colorRef) {
            layer.backgroundColor = colorRef;
            CFRelease(colorRef);
        } else {
            layer.backgroundColor = NULL;
        }
    }
}

- (NSColor *)backgroundColor;
{
    return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor;
{
    [backgroundColor retain];
    [_backgroundColor release];
    _backgroundColor = backgroundColor;
    
    [self _updateLayerBackgroundColor:self.layer];
}

#pragma mark - NSView subclass

- (void)drawRect:(NSRect)dirtyRect;
{
    OBASSERT(self.layer == nil, "Shouldn't be getting -drawRect if we are layer-backed");
    if (_backgroundColor) {
        [_backgroundColor setFill];
        NSRectFill(dirtyRect);
    }
}

- (CALayer *)makeBackingLayer;
{
    // If we're asked to provide a backing layer, we want to provide a generic CALayer that way we don't wind up creating a huge, unnecessary backing store.
    CALayer *layer = [CALayer layer];
    [self _updateLayerBackgroundColor:layer];
    return layer;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
{
    if (_nonretained_windowBackingPropertiesObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_nonretained_windowBackingPropertiesObserver];
        _nonretained_windowBackingPropertiesObserver = nil;
    }
    
    [super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow;
{
    NSWindow *window = self.window;
    
    if (window) {
        OBASSERT_NULL(_nonretained_windowBackingPropertiesObserver);
        _nonretained_windowBackingPropertiesObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidChangeBackingPropertiesNotification object:self.window queue:nil usingBlock:^(NSNotification *note) {
            [self _updateLayerBackgroundColor:self.layer];
        }];
    }
    
    [super viewDidMoveToWindow];
}

@end
