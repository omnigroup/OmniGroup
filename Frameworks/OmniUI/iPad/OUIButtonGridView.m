// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIButtonGridView.h>

RCS_ID("$Id$");

@interface OUIButtonGridView() {
  @private
    OUIButtonGridViewBorder _borderMask;
}

@property (nonatomic, readwrite, copy) NSArray *buttons;
@property (nonatomic, copy) NSArray *buttonConstraints;
@property (nonatomic, assign) NSUInteger numberOfRows;

@end

@implementation OUIButtonGridView

+ (UIButton *)buttonGridViewButtonWithTitle:(NSString *)title;
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    return button;
}

#pragma mark - API

- (void)setDataSource:(nullable id<OUIButtonGridViewDataSource>)dataSource;
{
    if (_dataSource != dataSource) {
        _dataSource = dataSource;

        [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
            [button removeFromSuperview];
        }];
        
        self.buttons = nil;
        self.buttonConstraints = nil;
        
        self.numberOfRows = [dataSource numberOfRowsInButtonGridView:self];

        [self setNeedsUpdateConstraints];
        [self setNeedsLayout];
    }
}

- (void)setBorderMask:(OUIButtonGridViewBorder)borderMask;
{
    _borderMask = borderMask;
    [self setNeedsDisplay];
}

- (UIButton *)buttonAtIndexPath:(NSIndexPath *)indexPath;
{
    if (self.buttons == nil) {
        return nil;
    }

    NSInteger row = [indexPath buttonGridViewRow];
    NSUInteger index = 0;
    
    for (NSInteger i = 0; i < row; i++) {
        index += [self.dataSource buttonGridView:self numberOfColumnsInRow:i];
    }
    
    index += [indexPath buttonGridViewColumn];
    OBASSERT(index >= 0 && index < self.buttons.count);
    
    if (index < self.buttons.count) {
        return self.buttons[index];
    }
    
    return nil;
}

#pragma mark - UIView subclass

- (void)setBounds:(CGRect)bounds;
{
    [super setBounds:bounds];
    
    if (self.buttonConstraints != nil) {
        [self removeConstraints:self.buttonConstraints];
    }
    
    self.buttonConstraints = nil;
    [self setNeedsUpdateConstraints];
    [self setNeedsDisplay];
}

- (void)updateConstraints;
{
    [super updateConstraints];
    
    if (self.buttonConstraints != nil) {
        return;
    }

    if (self.buttons == nil) {
        [self createButtons];
    }
    
    if (self.buttons.count == 0) {
        return;
    }
    
    NSUInteger buttonHeight = [self buttonHeight];
    NSUInteger width = floor(CGRectGetWidth(self.frame));
    
    NSMutableArray *buttonConstraints = [NSMutableArray array];
    
    NSUInteger row = 0;
    NSUInteger i = 0;
    for (; row < self.numberOfRows; row++) {
        
        NSUInteger numberOfColumnsInRow = [self numberOfColumnsInRow:row];
        NSUInteger buttonWidth = floor(width / numberOfColumnsInRow);

        for (NSUInteger column = 0; column < numberOfColumnsInRow; column++, i++) {
            UIButton *button = [self.buttons objectAtIndex:i];
            NSLayoutConstraint *leadingSpaceConstraint = [NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:buttonWidth * column];
            NSLayoutConstraint *topSpaceConstraint = [NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1.0 constant:buttonHeight * row];
            NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:buttonHeight];
            NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:buttonWidth];
            
            [buttonConstraints addObjectsFromArray:@[leadingSpaceConstraint, topSpaceConstraint, heightConstraint, widthConstraint]];
        }
    }
    
    [self addConstraints:buttonConstraints];
    self.buttonConstraints = [NSArray arrayWithArray:buttonConstraints];
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    if (self.buttonSeparatorStrokeColor != nil) {
        [self.buttonSeparatorStrokeColor setFill];
    } else {
        [[UIColor colorWithHue:0.0 saturation:0.0 brightness:0.8 alpha:1.0] setFill];
    }

    CGRect bounds = self.bounds;

    NSUInteger buttonHeight = [self buttonHeight];
    if (buttonHeight <= 0) {
        return;
    }
    
    NSUInteger numberOfRows = self.numberOfRows;
    NSUInteger height = floor(CGRectGetHeight(self.frame));
    NSUInteger buttonHeightRemainder = height % buttonHeight;
    
    for (NSUInteger row = 0; row <= numberOfRows; row++) {
        
        BOOL hasHeightRemainder = (buttonHeightRemainder > 0 && row == numberOfRows);
        
        CGRect lineRect = CGRectMake(CGRectGetMinX(bounds), row * buttonHeight, CGRectGetMaxX(bounds) - CGRectGetMinX(bounds), 0.5);
        if (hasHeightRemainder) {
            lineRect.origin.y += (buttonHeightRemainder - 0.5);
        }
        
        // Draw a horizontal border for the rows on the outer edges when configured with the correct border mask; draw all middle horizontal bordersa
        if (row == 0 && self.borderMask & OUIButtonGridViewBorderTop) {
            _DrawButtonBorder(ctx, lineRect);
        } else if (row == numberOfRows && self.borderMask & OUIButtonGridViewBorderBottom) {
            _DrawButtonBorder(ctx, lineRect);
        } else if (row != 0 && row != numberOfRows) {
            _DrawButtonBorder(ctx, lineRect);
        }
        
        NSUInteger numberOfColumnsInRow = [self numberOfColumnsInRow:row - 1];
        for (NSUInteger column = 1; column < numberOfColumnsInRow; column++) {
            NSUInteger width = floor(CGRectGetWidth(self.bounds));
            NSUInteger buttonWidth = floor(width / numberOfColumnsInRow);
            
            NSUInteger yOrigin = MAX(0, (NSInteger)((row - 1) * buttonHeight));
            CGRect buttonRect = CGRectMake(column * buttonWidth, yOrigin, 0.5, row * buttonHeight - yOrigin + 1);
            if (hasHeightRemainder) {
                buttonRect.size.height += buttonHeightRemainder;
            }
            
            _DrawButtonBorder(ctx, buttonRect);
        }
    }
}

#pragma mark - Private

static void _DrawButtonBorder(CGContextRef ctx, CGRect lineRect)
{
    CGContextFillRect(ctx, lineRect);
}

- (NSUInteger)numberOfColumnsInRow:(NSInteger)row;
{
    return [self.dataSource buttonGridView:self numberOfColumnsInRow:row];
}

- (NSUInteger)buttonHeight;
{
    if (self.numberOfRows == 0) {
        return 0;
    }
    
    NSUInteger height = floor(CGRectGetHeight(self.frame));
    NSUInteger buttonHeight = floor(height / self.numberOfRows);
    return buttonHeight;
}

- (void)createButtons;
{
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger row = 0; row < self.numberOfRows; row++) {
        for (NSUInteger column = 0; column < [self numberOfColumnsInRow:row]; column++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForButtonGridViewColumn:column inButtonGridViewRow:row];
            UIButton *button = [self.dataSource buttonGridView:self buttonForIndexPath:indexPath];
            [button addTarget:self action:@selector(_didPressGridViewButton:) forControlEvents:UIControlEventTouchUpInside];
            button.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:button];
            [buttons addObject:button];
        }
    }
    self.buttons = buttons;
}

- (void)_didPressGridViewButton:(id)sender;
{
    NSUInteger index = 0;
    for (NSUInteger row = 0; row < self.numberOfRows; row++) {
        NSUInteger numberOfColumnsInRow = [self numberOfColumnsInRow:row];
        NSUInteger column = [self.buttons indexOfObjectIdenticalTo:sender inRange:NSMakeRange(index, numberOfColumnsInRow)];
        if (column != NSNotFound) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForButtonGridViewColumn:column - index inButtonGridViewRow:row];
            [self.dataSource buttonGridView:self tappedButton:sender atIndexPath:indexPath];
            return;
        }
        
        index += numberOfColumnsInRow;
    }
    
    OBASSERT_NOT_REACHED("Unknown button pressed");
}

@end

#pragma mark

@implementation NSIndexPath (OUIButtonGridViewDataSource)

+ (NSIndexPath *)indexPathForButtonGridViewColumn:(NSInteger)column inButtonGridViewRow:(NSInteger)row;
{
    NSUInteger indexes[] = {row, column};
    return [NSIndexPath indexPathWithIndexes:indexes length:2];
}

- (NSInteger)buttonGridViewRow;
{
    return [self indexAtPosition:0];
}

- (NSInteger)buttonGridViewColumn;
{
    return [self indexAtPosition:1];
}

@end
