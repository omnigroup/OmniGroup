// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorWell.h>

@class OUITextLayout, OUIEditableFrame;

typedef enum {
    OUIInspectorTextWellStyleDefault, // Label and value text combined and centered. If the label has a '%@', then the value text replaces that range, otherwise they are concatenated.
    OUIInspectorTextWellStyleSeparateLabelAndText, // The label is left aligned and the text right aligned. The label should not have a '%@' in it.
} OUIInspectorTextWellStyle;

@interface OUIInspectorTextWell : OUIInspectorWell
{
@private
    OUIInspectorTextWellStyle _style;
    BOOL _editable;
    
    NSString *_text;
    UIFont *_font;
    
    // when in OUIInspectorTextWellStyleSeparateLabelAndText mode    
    OUITextLayout *_labelTextLayout;
    OUITextLayout *_valueTextLayout;
    CGFloat _valueTextWidth; // cache key for _valueTextLayout
    
    // If the label contains a "%@", then the -text replaces this section of the label. Otherwise the two strings are concatenated with the label being first.
    // The "%@" part is the normal -text and is styled with -font. The rest of the label string is styled with -labelFont (if set, otherwise -font).
    NSString *_label;
    UIFont *_labelFont;
    
    // While editing
    OUIEditableFrame *_editor;
    UIKeyboardType keyboardType;
}

@property(nonatomic) OUIInspectorTextWellStyle style;

@property(nonatomic) UIKeyboardType keyboardType;

@property(assign,nonatomic) BOOL editable;
@property(readonly) BOOL editing;
@property(copy,nonatomic) NSString *editingText; // The current contents of the field editor. Only valid when editing is true.

@property(copy,nonatomic) NSString *text;
@property(retain,nonatomic) UIFont *font;

@property(copy,nonatomic) NSString *label;
@property(retain,nonatomic) UIFont *labelFont;

// Subclass
- (NSString *)willCommitEditingText:(NSString *)editingText;

@end
