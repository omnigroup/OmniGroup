// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADisclosureButtonCell.h>

RCS_ID("$Id$");

#import <OmniAppKit/NSImage-OAExtensions.h>

@interface OADisclosureButtonCell () {
  @private
    NSImage *_collapsedImage;
    NSImage *_expandedImage;
    NSColor *_tintColor;
    BOOL _showsStateByAlpha;
}

@end

#pragma mark -

@implementation OADisclosureButtonCell

- (instancetype)initTextCell:(NSString *)string
{
    self = [super initTextCell:string];
    if (self == nil) {
        return nil;
    }
    
    [self OADisclosureButtonCell_commonInit];
    
    return self;
}

- (instancetype)initImageCell:(nullable NSImage *)image
{
    self = [super initImageCell:image];
    if (self == nil) {
        return nil;
    }
    
    [self OADisclosureButtonCell_commonInit];
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OADisclosureButtonCell_commonInit];
    
    return self;
}

- (void)OADisclosureButtonCell_commonInit;
{
    if (_collapsedImage == nil)
        _collapsedImage = OAImageNamed(@"OADisclosureButtonCollapsed", OMNI_BUNDLE);
    if (_expandedImage == nil)
        _expandedImage = OAImageNamed(@"OADisclosureButtonExpanded", OMNI_BUNDLE);
    [self _updateImageForCurrentState];
}

- (id)copyWithZone:(NSZone *)zone;
{
    OADisclosureButtonCell *copy = [super copyWithZone:zone];
    
    copy->_collapsedImage = _collapsedImage;
    copy->_expandedImage = _expandedImage;
    copy->_showsStateByAlpha = _showsStateByAlpha;
    
    return copy;
}

- (NSImage *)collapsedImage;
{
    return _collapsedImage;
}

- (void)setCollapsedImage:(NSImage *)collapsedImage;
{
    if (_collapsedImage != collapsedImage) {
        _collapsedImage = collapsedImage;
        [self _updateImageForCurrentState];
    }
}

- (NSImage *)expandedImage;
{
    return _expandedImage;
}

- (void)setExpandedImage:(NSImage *)expandedImage;
{
    if (_expandedImage != expandedImage) {
        _expandedImage = expandedImage;
        [self _updateImageForCurrentState];
    }
}

- (NSColor *)tintColor;
{
    return _tintColor;
}

- (void)setTintColor:(NSColor *)tintColor;
{
    if (_tintColor != tintColor) {
        _tintColor = tintColor;
        [self _updateImageForCurrentState];
    }
}

- (BOOL)showsStateByAlpha;
{
    return _showsStateByAlpha;
}

- (void)setShowsStateByAlpha:(BOOL)showsStateByAlpha;
{
    if (_showsStateByAlpha != showsStateByAlpha) {
        _showsStateByAlpha = showsStateByAlpha;
        [self.controlView setNeedsDisplay:YES];
    }
}

- (void)setState:(NSInteger)value;
{
    [super setState:value];
    
    [self _updateImageForCurrentState];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    NSImage *image = self.image;
    CGFloat alpha = 1.0;
    NSRect imageRect = [self imageRectForBounds:cellFrame];
    NSRect sourceRect = {
        .origin = NSZeroPoint,
        .size = image.size
    };
    
    if (_showsStateByAlpha) {
        alpha = [self isHighlighted] ? 0.60 : 0.40;
    } else if ([self isHighlighted]) {
        image = [self _highlightedImageForImage:image];
    }

    [image drawInRect:imageRect fromRect:sourceRect operation:NSCompositingOperationSourceOver fraction:alpha respectFlipped:YES hints:nil];
}

#pragma mark Private

- (NSImage *)_highlightedImageForImage:(NSImage *)image;
{
    BOOL flipped = [self.controlView isFlipped];
    NSImage *highlightedImage = [NSImage imageWithSize:image.size flipped:flipped drawingHandler:^BOOL(NSRect dstRect) {
        NSRect srcRect = {
            .origin = NSZeroPoint,
            .size = image.size
        };
        
        [image drawInRect:dstRect fromRect:srcRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        
        [[[NSColor blackColor] colorWithAlphaComponent:0.50] set];
        NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceAtop);
        
        return YES;
    }];
    
    return highlightedImage;
}

- (void)_updateImageForCurrentState;
{
    [self.controlView setNeedsDisplay:YES];
    
    NSImage *image = (self.state != 0) ? _expandedImage : _collapsedImage;
    if (_tintColor != nil)
        image = [image imageByTintingWithColor:_tintColor];
    self.image = image;
}

@end
