// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorTextWell.h> // for OUIInspectorTextWellStyle

/*
 A simple slice with a single text well set up to fire an action.
 */

@class OUIInspectorTextWell;

@interface OUIActionInspectorSlice : OUIInspectorSlice
{
@private
    SEL _action;
    BOOL _shouldEditOnLoad;
    BOOL _shouldSelectAllOnLoad;
    OUIInspectorTextWell *_textWell;
}

+ (Class)textWellClass;
+ (OUIInspectorTextWellStyle)textWellStyle;
+ (OUIInspectorWellBackgroundType)textWellBackgroundType;
+ (UIControlEvents)textWellControlEvents;

- initWithTitle:(NSString *)title action:(SEL)action;

@property(nonatomic) BOOL shouldEditOnLoad;
@property(nonatomic) BOOL shouldSelectAllOnLoad;
@property(strong,readonly,nonatomic) OUIInspectorTextWell *textWell;

@end
