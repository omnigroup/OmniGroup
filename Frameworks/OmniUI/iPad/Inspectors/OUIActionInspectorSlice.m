// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionInspectorSlice.h>

#import <OmniUI/OUIInspectorTextWell.h>
#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIActionInspectorSlice

+ (Class)textWellClass;
{
    return [OUIInspectorTextWell class];
}

+ (OUIInspectorTextWellStyle)textWellStyle;
{
    return OUIInspectorTextWellStyleDefault;
}

+ (OUIInspectorWellBackgroundType)textWellBackgroundType;
{
    return OUIInspectorWellBackgroundTypeButton;
}

+ (UIControlEvents)textWellControlEvents;
{
    // Return UIControlEventValueChanged for an editable field.
    return UIControlEventTouchUpInside;
}

// There is no target since the receiver will almost always be the target and we don't want to create a retain cycle.
- initWithTitle:(NSString *)title action:(SEL)action;
{
    OBPRECONDITION(title);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _action = action;
    
    self.title = title;
    
    return self;
}

@synthesize shouldEditOnLoad = _shouldEditOnLoad;
@synthesize shouldSelectAllOnLoad = _shouldSelectAllOnLoad;

- (OUIInspectorTextWell *)textWell;
{
    if (!_textWell)
        (void)[self view];
    return _textWell;
}

#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    CGRect textWellFrame = CGRectMake(0, 0, 100, kOUIInspectorWellHeight); // Width doesn't matter; we'll get width-resized as we get put in the stack.
    
    _textWell = [[[[self class] textWellClass] alloc] initWithFrame:textWellFrame];
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.cornerType = OUIInspectorWellCornerTypeLargeRadius;
    
    // Accessibility
    _textWell.isAccessibilityElement = YES;
    _textWell.accessibilityLabel = self.title;

    if (_action)
        [_textWell addTarget:self action:_action forControlEvents:[[self class] textWellControlEvents]];
    
    OUIInspectorTextWellStyle style = [[self class] textWellStyle];
    _textWell.style = style;
    _textWell.backgroundType = [[self class] textWellBackgroundType];
    
    if (style == OUIInspectorTextWellStyleSeparateLabelAndText)
        _textWell.label = self.title;
    else
        _textWell.text = self.title;

    self.view = _textWell;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.shouldEditOnLoad) {
        [[self textWell] startEditing];
        self.shouldEditOnLoad = NO;
        if (self.shouldSelectAllOnLoad)
            [_textWell selectAll:self showingMenu:NO];
    }
}

@end
