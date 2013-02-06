// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsView.h"

#import <OmniUI/OUIInspectorWell.h>

RCS_ID("$Id$")

static const NSUInteger kMaximumChoicesPerRow = 3;
static const CGFloat kLabelHeight = 20;
static const CGFloat kVerticalBorder = 20;
static const CGFloat kImageSize = 128;
static const CGFloat kRowPadding = 15;

@interface OUIExportOptionsButton : UIButton
@end
@implementation OUIExportOptionsButton

- (CGRect)backgroundRectForBounds:(CGRect)bounds;
{
    bounds.size.height -= kLabelHeight;
    if (bounds.size.height > kImageSize)
        bounds = CGRectInset(bounds, 0, (bounds.size.height - kImageSize)/2);
    if (bounds.size.width > kImageSize)
        bounds = CGRectInset(bounds, (bounds.size.width - kImageSize)/2, 0);
    
    bounds.origin.y = 0.0; // Ensure that the background image is always top aligned.
    return CGRectIntegral(bounds);
}

@end

@implementation OUIExportOptionsView

static id _commonInit(OUIExportOptionsView *self)
{
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];

    self->_choiceButtons = [[NSMutableArray alloc] init];
    
    UIImage *borderImage = [UIImage imageNamed:@"OUIExportOptionsBorder.png"];
    borderImage = [borderImage stretchableImageWithLeftCapWidth:11 topCapHeight:11];
    
    OBASSERT(borderImage);
    [self setImage:borderImage];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}


- (void)addChoiceWithImage:(UIImage *)image label:(NSString *)label target:(id)target selector:(SEL)selector;
{
    OUIExportOptionsButton *choice = [OUIExportOptionsButton buttonWithType:UIButtonTypeCustom];
    [choice setBackgroundImage:image forState:UIControlStateNormal];
    [choice setTitle:label forState:UIControlStateNormal];
    [choice setTitleColor:[UIColor colorWithRed:0.196 green:0.224 blue:0.29 alpha:1] forState:UIControlStateNormal];
    [choice setTitleShadowColor:[UIColor colorWithWhite:1 alpha:.5] forState:UIControlStateNormal];
    choice.titleLabel.shadowOffset = CGSizeMake(0, 1);
    choice.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    choice.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    choice.titleLabel.textAlignment = NSTextAlignmentCenter;
    choice.titleEdgeInsets = UIEdgeInsetsMake(kImageSize, 0, 0, 0);
    [choice addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];

    choice.tag = [_choiceButtons count];
    
#if 0
    choice.backgroundColor = [UIColor redColor];
#endif
    
    [choice sizeToFit];
    [_choiceButtons addObject:choice];
    
    [self addSubview:choice];
}

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    CGFloat yOffset = kVerticalBorder;
    NSUInteger choiceIndex = 0, choiceCount = [_choiceButtons count];
    CGFloat containingFrameHeight = 0;
    
    while (choiceIndex < choiceCount) {
        CGFloat maxChoiceHeightForRow = 0;
        NSUInteger choicesOnThisRow = MIN(choiceCount - choiceIndex, kMaximumChoicesPerRow);
        
        CGFloat horizontalPadding = (CGRectGetWidth(bounds) - kImageSize*choicesOnThisRow) / (choicesOnThisRow + 1);
        
        CGFloat maxHeightInRow = 0;
        for (NSUInteger rowIndex = 0; rowIndex < choicesOnThisRow; rowIndex++) {
            OUIExportOptionsButton *choice = [_choiceButtons objectAtIndex:choiceIndex + rowIndex];
            
            CGRect choiceFrame = choice.frame; // sized already.
            
            choiceFrame.origin.x = floor(horizontalPadding + (horizontalPadding + kImageSize) * rowIndex);
            choiceFrame.origin.y = yOffset;
            choiceFrame.size.width = kImageSize;
            
            CGRect actualLabelRect = [choice titleRectForContentRect:[choice contentRectForBounds:choice.bounds]];
            choiceFrame.size.height = kImageSize + actualLabelRect.size.height;
            
            choice.frame = choiceFrame;
            
            maxHeightInRow = MAX(maxHeightInRow, CGRectGetHeight(choiceFrame));
            maxChoiceHeightForRow = MAX(maxChoiceHeightForRow, choiceFrame.size.height);
        }
        
        // containgFrameHeight must be tall enough to hold the max choices for each row. All padding will be added below.
        containingFrameHeight += maxChoiceHeightForRow;
        choiceIndex += choicesOnThisRow;
        
        yOffset += ceil(maxHeightInRow + kRowPadding);
    }
    
    // Set frame height tall enough to fit all choices now that they've actually been laid out.
    NSUInteger rows = ([_choiceButtons count] + kMaximumChoicesPerRow - 1) / kMaximumChoicesPerRow;
    OBASSERT(rows >= 1);

    CGRect frame = self.frame;
    frame.size.height = containingFrameHeight + 2*kVerticalBorder + (rows-1)*kRowPadding;
    self.frame = frame;
}

@end
