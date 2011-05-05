// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
    OUIInspectorTextWell *_textWell;
}

+ (Class)textWellClass;
+ (OUIInspectorTextWellStyle)textWellStyle;

- initWithTitle:(NSString *)title action:(SEL)action;

@property(nonatomic) BOOL shouldEditOnLoad;
@property(readonly,nonatomic) OUIInspectorTextWell *textWell;

@end
