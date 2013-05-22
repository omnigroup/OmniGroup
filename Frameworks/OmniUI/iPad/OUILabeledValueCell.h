// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

typedef enum {
    OUILabeledValueCellStyleDefault = 0,
    OUILabeledValueCellStyleSettings,
    OUILabeledValueCellStyleOmniFocusForiPhoneLegacy
} OUILabeledValueCellStyle;

@interface OUILabeledValueCell : UIView
{
@private
    OUILabeledValueCellStyle _style;
    CGFloat _minimumLabelWidth;
    BOOL _usesActualLabelWidth;
    NSString *_label;
    NSString *_value;
    NSString *_emptyValueString;
    UIImage *_valueImage;
    BOOL _isHighlighted;
}

+ (UIFont *)labelFontForStyle:(OUILabeledValueCellStyle)style;
+ (UIFont *)valueFontForStyle:(OUILabeledValueCellStyle)style;

+ (UIColor *)labelColorForStyle:(OUILabeledValueCellStyle)style isHighlighted:(BOOL)highlighted;
+ (UIColor *)valueColorForStyle:(OUILabeledValueCellStyle)style isHighlighted:(BOOL)highlighted;

- (id)initWithFrame:(CGRect)frame style:(OUILabeledValueCellStyle)style; // designated initializer

@property (nonatomic, readonly) OUILabeledValueCellStyle style;
@property (nonatomic) CGFloat minimumLabelWidth;
@property (nonatomic) BOOL usesActualLabelWidth;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSTextAlignment labelAlignment;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *valuePlaceholder;
@property (nonatomic, retain) UIImage *valueImage;
@property (nonatomic, getter=isHighlighted) BOOL highlighted;

- (void)labelChanged;
- (CGRect)labelRect;
- (CGRect)valueRectForString:(NSString *)valueString labelRect:(CGRect)labelRect;

@end
