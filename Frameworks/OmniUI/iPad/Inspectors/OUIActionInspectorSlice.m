// Copyright 2010-2011 The Omni Group. All rights reserved.
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

+ (UIControlEvents)textWellControlEvents;
{
    // Return UIControlEventValueChanged for an editable field.
    return UIControlEventTouchUpInside;
}

// There is no target since the receiver will almost always be the target and we don't want to create a retain cycle.
- initWithTitle:(NSString *)title action:(SEL)action;
{
    OBPRECONDITION(title);
    OBPRECONDITION(action);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _action = action;
    
    self.title = title;
    
    return self;
}

@synthesize shouldEditOnLoad = _shouldEditOnLoad;

- (OUIInspectorTextWell *)textWell;
{
    if (!_textWell)
        [self view];
    return _textWell;
}

- (void)dealloc;
{
    [_textWell release];
    [super dealloc];
}


#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    CGRect textWellFrame = CGRectMake(0, 0, 100, kOUIInspectorWellHeight); // Width doesn't matter; we'll get width-resized as we get put in the stack.
    
    _textWell = [[[[self class] textWellClass] alloc] initWithFrame:textWellFrame];
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.rounded = YES;
    
    [_textWell addTarget:nil action:_action forControlEvents:UIControlEventTouchUpInside|UIControlEventValueChanged];
    
    OUIInspectorTextWellStyle style = [[self class] textWellStyle];
    _textWell.style = style;
    
    if (style == OUIInspectorTextWellStyleSeparateLabelAndText)
        _textWell.label = self.title;
    else
        _textWell.text = self.title;

    self.view = _textWell;
}

- (void)viewDidUnload;
{
    [_textWell release];
    _textWell = nil;
    
    [super viewDidUnload];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.shouldEditOnLoad) {
        [[self textWell] startEditing];
        self.shouldEditOnLoad = NO;
    }
}

@end
