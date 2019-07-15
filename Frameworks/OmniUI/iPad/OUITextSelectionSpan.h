// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniUI/OUIInspector.h>

@class OUITextView;
@class NSTextStorage;

@interface OUITextSelectionSpan : NSObject <OUIColorInspection, OUIFontInspection, OUIParagraphInspection>

- initWithRange:(UITextRange *)range inTextView:(OUITextView *)textView;

@property(nonatomic,readonly,strong) UITextRange *range;
@property(nonatomic,readonly,strong) OUITextView *textView;
@property(nonatomic,readonly,strong) NSTextStorage *textStorage;

@end
