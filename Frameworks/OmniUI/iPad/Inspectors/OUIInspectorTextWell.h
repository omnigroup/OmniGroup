// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUICustomKeyboardProtocol.h>

typedef enum {
    OUIInspectorTextWellStyleDefault, // Label and value text combined and centered. If the label has a '%@', then the value text replaces that range, otherwise they are concatenated.
    OUIInspectorTextWellStyleSeparateLabelAndText, // The label is left aligned and the text right aligned. The label should not have a '%@' in it.
} OUIInspectorTextWellStyle;

@interface OUIInspectorTextWell : OUIInspectorWell

+ (UIFont *)defaultLabelFont;
+ (UIFont *)defaultFont;

@property(nonatomic) OUIInspectorTextWellStyle style;

// Subset of UITextInputTraits
@property(nonatomic) UITextAutocapitalizationType autocapitalizationType; // default is UITextAutocapitalizationTypeSentences
@property(nonatomic) UITextAutocorrectionType autocorrectionType;         // default is UITextAutocorrectionTypeDefault
@property(nonatomic) UITextSpellCheckingType spellCheckingType;           // default is UITextSpellCheckingTypeDefault;
@property(nonatomic) UIKeyboardType keyboardType;                         // default is UIKeyboardTypeDefault
@property(nonatomic) UIReturnKeyType returnKeyType;                       // default is UIReturnKeyDefault

@property(nonatomic, readwrite, retain) id <OUICustomKeyboard> customKeyboard;
@property(nonatomic, readwrite, retain) NSFormatter *formatter; // Formatter for turning objectValue into text
@property(nonatomic, readwrite, retain) id objectValue; // Non-string actual content value for a customKeyboard to edit

@property(assign,nonatomic) BOOL editable;
@property(readonly) BOOL editing;
@property(copy,nonatomic) NSString *editingText; // The current contents of the field editor. Only valid when editing is true.
- (void)startEditing;
- (void)selectAll:(id)sender;
- (void)selectAll:(id)sender showingMenu:(BOOL)show;

@property(assign,nonatomic) NSTextAlignment textAlignment; // Only useful for OUIInspectorTextWellStyleDefault

@property(copy,nonatomic) NSString *text;
@property(copy,nonatomic) NSString *suffix;
@property(retain,nonatomic) UIColor *textColor;
@property(retain,nonatomic) UIFont *font;

@property(copy,nonatomic) NSString *label;
@property(retain,nonatomic) UIFont *labelFont;
@property(retain,nonatomic) UIColor *labelColor;

@property(copy,nonatomic) NSString *placeholderText;

// Subclass
- (NSString *)willCommitEditingText:(NSString *)editingText;

@end
