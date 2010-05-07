// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class UILabel;

@interface OUIInspectorTextWell : UIControl <UITextFieldDelegate>
{
@private
    BOOL _rounded;
    BOOL _editable;
    BOOL _showNavigationArrow;
    
    NSString *_text;
    UIFont *_font;

    // "%@ points", for example.  The "%@" part is the normal _text and is styled with _font. The rest of the format string is styled with _fomatFont.    
    NSString *_formatString;
    UIFont *_formatFont;
    
    // While editing
    UITextField *_textField;
    UIKeyboardType keyboardType;
}

+ (CGFloat)fontSize;
+ (UIFont *)italicFormatFont;
+ (UIColor *)textColor;
+ (UIColor *)highlightedTextColor;

@property(nonatomic) UIKeyboardType keyboardType;

@property(assign,nonatomic) BOOL rounded;

@property(assign,nonatomic) BOOL editable;
@property(readonly) BOOL editing;
@property(readonly) UITextField *textField; // returns nil unless editable is YES

@property(copy,nonatomic) NSString *text;
@property(retain,nonatomic) UIFont *font;

@property(copy,nonatomic) NSString *formatString;
@property(retain,nonatomic) UIFont *formatFont;

- (void)setNavigationTarget:(id)target action:(SEL)action;

- (NSAttributedString *)formattedText;  // Overridden in graffle to handle a formatted string with 2 texts

@end
