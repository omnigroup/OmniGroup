//
//  OUIUndoButton.m
//  OmniGraffle-iPad
//
//  Created by Ryan Patrick on 5/24/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "OUIUndoButton.h"
#import "OUIUndoButtonController.h"

RCS_ID("$Id$");

@interface OUIUndoButton (/*private*/)
- (void)_undoMenu:(id)sender;
@end


@implementation OUIUndoButton
static UIImage *_loadImage(NSString *imageName)
{
    UIImage *image = [UIImage imageNamed:imageName];
    OBASSERT(image);
    
    // These images should all be stretchable. The caps have to be the same width. The one uncapped px is used for stretching.
    const CGFloat capWidth = 6;
    OBASSERT(image.size.width == capWidth * 2 + 1);
    
    return [image stretchableImageWithLeftCapWidth:capWidth topCapHeight:0];
}

+ (void)initialize;
{
    OBINITIALIZE;
}

+ (CGRect)appropriateBounds;
{
    CGRect _bounds = CGRectMake(0, 0, 55, 30);
    return _bounds;
}

static id _commonInit(OUIUndoButton *self)
{
    UIImage *background = _loadImage(@"OUIUndoButtonBackground.png");
    [self setBackgroundImage:background forState:UIControlStateNormal];
    
    UITapGestureRecognizer *undoTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_undo:)];
    [self addGestureRecognizer:undoTap];
    [undoTap release];
    
    UILongPressGestureRecognizer *undoMenuTap = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_undoMenu:)];
    [self addGestureRecognizer:undoMenuTap];
    [undoMenuTap release];
    
    [self setTitle:NSLocalizedStringFromTableInBundle(@"Undo", @"OmniUI", OMNI_BUNDLE, @"Undo button title") forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self setTitleShadowColor:[UIColor colorWithWhite:0 alpha:.5f] forState:UIControlStateNormal];
    self.titleEdgeInsets = UIEdgeInsetsMake(1, 8, 0, 8);
    
    [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_buttonController release];
    [super dealloc];
}

- (CGRect)backgroundRectForBounds:(CGRect)bounds;
{
    CGRect backgroundBounds = [super backgroundRectForBounds:bounds];
    backgroundBounds.origin.y += 1;
    
    return backgroundBounds;
}

- (void)showUndoMenu;
{
    [self _undoMenu:self];
}

- (void)_undo:(id)sender;
{
    // Try the first responder and then the app delegate.
    SEL action = @selector(undoButtonAction:);
    
    UIApplication *app = [UIApplication sharedApplication];
    if ([app sendAction:action to:nil from:self forEvent:nil])
        return;
    if ([app sendAction:action to:app.delegate from:self forEvent:nil])
        return;
    
    NSLog(@"No target found for menu action %@", NSStringFromSelector(action));
}

- (void)_undoMenu:(id)sender;
{
    if (!_buttonController)
        _buttonController = [[OUIUndoButtonController alloc] initWithNibName:nil bundle:nil];
    
    [_buttonController showUndoMenu:self];
}

@end
