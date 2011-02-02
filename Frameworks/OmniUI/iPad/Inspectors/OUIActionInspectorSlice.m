// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionInspectorSlice.h>

#import <OmniUI/OUIInspectorTextWell.h>

RCS_ID("$Id$");

@implementation OUIActionInspectorSlice

+ (Class)textWellClass;
{
    return [OUIInspectorTextWell class];
}

// There is no target since the receiver will almost always be the target and we don't want to create a retain cycle.
- initWithTitle:(NSString *)title action:(SEL)action;
{
    OBPRECONDITION(title);
    OBPRECONDITION(action);
    
    if (!(self = [super init]))
        return nil;
    
    _action = action;
    
    self.title = title;
    
    return self;
}

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
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 45)]; // Width doesn't matter; we'll get width-resized as we get put in the stack.
    
    UIEdgeInsets textWellInsets = UIEdgeInsetsMake(0/*top*/, 9/*left*/, 8/*bottom*/, 9/*right*/);
    CGRect textWellFrame = UIEdgeInsetsInsetRect(view.bounds, textWellInsets);
    
    _textWell = [[[[self class] textWellClass] alloc] initWithFrame:textWellFrame];
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.rounded = YES;
    [_textWell setNavigationTarget:nil action:_action];
    
    _textWell.text = self.title;
    
    [view addSubview:_textWell];
    self.view = view;
}

- (void)viewDidUnload;
{
    [_textWell release];
    _textWell = nil;
    
    [super viewDidUnload];
}

@end
