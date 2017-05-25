// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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

@protocol OUIInspectorTextWellDelegate
@optional
- (NSString *)textWell:(OUIInspectorTextWell *)textWell willCommitEditingText:(NSString *)editingText;
@end

@interface OUIInspectorTextWell : OUIInspectorWell

+ (UIFont *)defaultLabelFont;
+ (UIFont *)defaultFont;

@property(nonatomic) OUIInspectorTextWellStyle style;

// Subset of UITextInputTraits
@property(nonatomic) UITextAutocapitalizationType autocapitalizationType; // default is UITextAutocapitalizationTypeSentences
@property(nonatomic) UITextAutocorrectionType autocorrectionType;         // default is UITextAutocorrectionTypeDefault
@property(nonatomic) UITextFieldViewMode clearButtonMode;                 // default is UITextFieldViewModeNever
@property(nonatomic) UITextSpellCheckingType spellCheckingType;           // default is UITextSpellCheckingTypeDefault;
@property(nonatomic) UIKeyboardType keyboardType;                         // default is UIKeyboardTypeDefault
@property(nonatomic) UIReturnKeyType returnKeyType;                       // default is UIReturnKeyDefault

@property(nonatomic, readwrite, strong) id <OUICustomKeyboard> customKeyboard;
@property(nonatomic, readwrite, strong) NSFormatter *formatter; // Formatter for turning objectValue into text
@property(nonatomic, readwrite, strong) id objectValue; // Non-string actual content value for a customKeyboard to edit
@property(nonatomic, readwrite) BOOL customKeyboardChangedText; // So subclasses can cancel editing

@property(assign,nonatomic) BOOL editable;
@property(readonly) BOOL editing;
@property(copy,nonatomic) NSString *editingText; // The current contents of the field editor. Only valid when editing is true.
- (void)startEditing;
- (void)selectAll:(id)sender;
- (void)selectAll:(id)sender showingMenu:(BOOL)show;

@property(assign,nonatomic) NSTextAlignment textAlignment; // Only useful for OUIInspectorTextWellStyleDefault

@property(copy,nonatomic) NSString *text;
@property(copy,nonatomic) NSString *suffix;
@property(strong,nonatomic) UIColor *textColor;
@property(strong,nonatomic) UIFont *font;

// If the label contains a "%@", then the -text replaces this section of the label. Otherwise the two strings are concatenated with the label being first.
// The "%@" part is the normal -text and is styled with -font. The rest of the label string is styled with -labelFont (if set, otherwise -font).
@property(copy,nonatomic) NSString *label;
@property(strong,nonatomic) UIFont *labelFont;
@property(strong,nonatomic) UIColor *labelColor;
@property(strong,nonatomic) UIColor *disabledTextColor; // Used in the value for TextTypePlaceholder, label if !enabled. [OUIInspector disabledLabelTextColor] by default

@property(copy,nonatomic) NSString *placeholderText;

// Subclass
- (NSString *)willCommitEditingText:(NSString *)editingText;

@property(nonatomic,assign) NSObject <OUIInspectorTextWellDelegate> *delegate;

@end
