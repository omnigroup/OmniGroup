// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSearchWell.h>
#import <OmniUI/OUIInspectorSliceView.h>

RCS_ID("$Id$");


@implementation OUIInspectorSearchWell

+ (NSString *)searchPlaceHolderText;
{
    return NSLocalizedStringFromTableInBundle(@"Search", @"OmniUI", OMNI_BUNDLE, @"Search field placeholder text");
}

static id _commonInit(OUIInspectorSearchWell *self)
{
    self.backgroundColor = [UIColor colorWithWhite:.89 alpha:1.0f];
    self.placeholderText = [OUIInspectorSearchWell searchPlaceHolderText];
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.spellCheckingType = UITextSpellCheckingTypeNo;
    self.clearButtonMode = UITextFieldViewModeWhileEditing;
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }
    
    return _commonInit(self);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder;
{
    if ((self = [super initWithCoder:aDecoder]) == nil) {
        return nil;
    }
    
    return _commonInit(self);
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
}

- (CGRect)interiorRect;
{
    return CGRectInset(self.bounds, 8.0f, 8.0f);
}

- (CGRect)contentsRect;
{
    return CGRectInset(self.interiorRect, 8.0f, 8.0f);
}

- (void)drawRect:(CGRect)rect;
{
    CGRect  interiorRect = self.interiorRect;
    UIBezierPath *interiorPath = [UIBezierPath bezierPathWithRoundedRect:interiorRect cornerRadius:4.0f];
    [[UIColor whiteColor] set];
    [interiorPath fill];
}

@end
