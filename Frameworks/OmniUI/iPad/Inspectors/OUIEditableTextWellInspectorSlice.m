// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEditableTextWellInspectorSlice.h>

RCS_ID("$Id$")

@implementation OUIEditableTextWellInspectorSlice

+ (OUIInspectorTextWellStyle)textWellStyle;
{
    return OUIInspectorTextWellStyleSeparateLabelAndText;
}

+ (OUIInspectorWellBackgroundType)textWellBackgroundType;
{
    return OUIInspectorWellBackgroundTypeNormal;
}

+ (UIControlEvents)textWellControlEvents;
{
    return UIControlEventValueChanged;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    self.textWell.editable = YES;
}

@synthesize isUntitled = _isUntitled;

@end
