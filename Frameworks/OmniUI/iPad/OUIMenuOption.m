// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuOption.h>

RCS_ID("$Id$");

@implementation OUIMenuOption
{
    OUIMenuOptionAction _action;
    NSString *_title;
    UIImage *_image;
}

- initWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;
{
    OBPRECONDITION(title);
    OBPRECONDITION(action);
    
    if (!(self = [super init]))
        return nil;
    
    _action = [action copy];
    _title = [title copy];
    _image = [image retain];
    
    return self;
}

- (void)dealloc;
{
    [_action release];
    [_title release];
    [_image release];
    [super dealloc];
}

@synthesize title = _title;
@synthesize image = _image;
@synthesize action = _action;

@end
