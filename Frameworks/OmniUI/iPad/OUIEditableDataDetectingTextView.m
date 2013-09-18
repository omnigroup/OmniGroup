// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFEncoding.h>

#import <OmniUI/OUIEditableDataDetectingTextView.h>

RCS_ID("$Id$");

#define ALLOW_LINK_DETECTION (YES)

@interface OUIEditableDataDetectingTextView () {
  @private
    BOOL _detectsLinks;
    NSString *_placeholder;
    BOOL _drawsPlaceholder;
    BOOL _drawsBorder;
    BOOL _observingEditingNotifications;
}

@end

#pragma mark -

@implementation OUIEditableDataDetectingTextView

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
        
    [self EditableDataDetectingTextView_commonInit];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self EditableDataDetectingTextView_commonInit];
    return self;
}

- (void)EditableDataDetectingTextView_commonInit;
{
    _drawsPlaceholder = YES;
    _drawsBorder = NO;
    _detectsLinks = ALLOW_LINK_DETECTION;
    
    self.contentMode = UIViewContentModeRedraw;
    self.editable = NO;
    self.dataDetectorTypes = UIDataDetectorTypeAll;
    self.alwaysBounceVertical = YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)placeholder;
{
    return _placeholder;
}

- (void)setPlaceholder:(NSString *)placeholder;
{
    if (_placeholder != placeholder) {
        _placeholder = [placeholder copy];
        
        [self _addEditingObserversIfNecessary];

        if ([self _shouldDrawPlaceholder]) {
            [self setNeedsDisplay];
        }
    }
}

- (BOOL)drawsPlaceholder;
{
    return _drawsPlaceholder;
}

- (void)setDrawsPlaceholder:(BOOL)drawsPlaceholder;
{
    _drawsPlaceholder = drawsPlaceholder;
    [self setNeedsDisplay];
}

- (BOOL)drawsBorder;
{
    return _drawsBorder;
}   

- (void)setDrawsBorder:(BOOL)drawsBorder;
{
    if (drawsBorder != _drawsBorder) {
        _drawsBorder = drawsBorder;
        if (_drawsBorder) {
            self.layer.borderColor = [[UIColor lightGrayColor] CGColor];
            self.layer.borderWidth = 1.0;
            self.layer.cornerRadius = 10;
            self.opaque = NO;
        } else {
            self.layer.borderWidth = 0;
            self.layer.cornerRadius = 0;
            self.opaque = YES;
        }
    }

//#ifdef DEBUG_correia
//    self.layer.borderColor = [[UIColor redColor] CGColor];
//    self.layer.borderWidth = 1.0;
//#endif
}

- (void)setText:(NSString *)text;
{
    // Starting with iOS 7, the text storage is exposed.
    // To catch all cases of the text changing (and possibly needing to draw the placeholder string), we'd have to watch the storage.
    // OmniFocus doesn't use the text view that way, so we ignore that.
    
    [super setText:text];

    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)setAttributedText:(NSAttributedString *)attributedText;
{
    // Starting with iOS 7, the text storage is exposed.
    // To catch all cases of the text changing (and possibly needing to draw the placeholder string), we'd have to watch the storage.
    // OmniFocus doesn't use the text view that way, so we ignore that.
    
    [super setAttributedText:attributedText];

    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)setFont:(UIFont *)font;
{
    [super setFont:font];

    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)clipRect;
{
    [super drawRect:clipRect];
    
    if ([self _shouldDrawPlaceholder]) {
        UIFontDescriptor *placeholderFontDescriptor = self.font.fontDescriptor;
        [placeholderFontDescriptor fontDescriptorWithSymbolicTraits:(UIFontDescriptorTraitBold | UIFontDescriptorTraitUIOptimized)];

        CGFloat placeholderFontSize = ceil(self.font.pointSize * 1.10);
        UIFont *placeholderFont = [UIFont fontWithDescriptor:placeholderFontDescriptor size:placeholderFontSize];
        NSString *placeholder = self.placeholder;
        NSDictionary *attributes = @{
            NSFontAttributeName: placeholderFont,
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.75 alpha:1.0],
        };

        CGSize size = self.bounds.size;
        CGRect boundingRect = [placeholder boundingRectWithSize:size options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:nil];
        CGRect textRect = self.bounds;
        textRect = UIEdgeInsetsInsetRect(textRect, self.contentInset);
        textRect = UIEdgeInsetsInsetRect(textRect, self.textContainerInset);

        // Draw the placeholder if we have a comformtable amount of vertical space
        if (CGRectGetHeight(textRect) >= 88) {
            textRect.origin.x += (CGRectGetWidth(textRect) - CGRectGetWidth(boundingRect)) / 2.0;
            textRect.origin.y += -1 * self.contentOffset.y - self.contentInset.top;
            
            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
                // REVIEW: We want to push this up a bit, at least in portrait, so that it can have the same position whether the keyboard is visible or not
                textRect.origin.y += 3 * (CGRectGetHeight(textRect) / 8.0) - (CGRectGetHeight(boundingRect) / 2.0);
            } else {
                textRect.origin.y += (CGRectGetHeight(textRect) / 2.0) - (CGRectGetHeight(boundingRect) / 2.0);
            }

            textRect.size = boundingRect.size;
            textRect = CGRectIntegral(textRect);

            [placeholder drawInRect:textRect withAttributes:attributes];
        }
    }
}

#pragma mark UITextView subclass

- (BOOL)resignFirstResponder;
{
    BOOL result = [super resignFirstResponder];
    
    if (result && _detectsLinks) {
        // Set editable to NO when resigning first responder so that links are tappable.
        self.editable = NO;
        self.dataDetectorTypes = UIDataDetectorTypeAll;
    }
    
    return result;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    // If we got to -touchesEnded, then a link was NOT tapped.
    // Move the insertion point underneath the touch, and become editable and firstResponder
    
    [self _becomeEditableWithTouches:touches makeFirstResponder:YES];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    
    // If we got to -touchesEnded, then a link was NOT tapped.
    // Move the insertion point underneath the touch, and become editable and firstResponder
    
    [self _becomeEditableWithTouches:touches makeFirstResponder:YES];
}

#pragma mark UIScrollView subclass

- (void)setContentOffset:(CGPoint)contentOffset;
{
    [super setContentOffset:contentOffset];
    
    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated;
{
    [super setContentOffset:contentOffset animated:animated];
    
    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)setContentInset:(UIEdgeInsets)contentInset;
{
    [super setContentInset:contentInset];
    
    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset;
{
    [super setTextContainerInset:textContainerInset];
    
    if ([self _shouldDrawPlaceholder]) {
        [self setNeedsDisplay];
    }
}

#pragma mark Private

- (BOOL)_shouldDrawPlaceholder;
{
    return (![self isFirstResponder] && ![self hasText] && _drawsPlaceholder && ![NSString isEmptyString:_placeholder]);
}

- (void)_becomeEditableWithTouches:(NSSet *)touches makeFirstResponder:(BOOL)makeFirstResponder;
{
    if (![self isEditable]) {
        OBASSERT([touches count] == 1); // Otherwise, we are using a random one

        NSLayoutManager *layoutManager = self.layoutManager;
        NSTextContainer *textContainer = self.textContainer;
        CGPoint point = [[touches anyObject] locationInView:self];
        
        // Offset the touch for the text container insert
        UIEdgeInsets textContainerInset = self.textContainerInset;
        point.y -= textContainerInset.top;
        point.x -= textContainerInset.left;
        
        NSUInteger characterIndex = [layoutManager characterIndexForPoint:point inTextContainer:textContainer fractionOfDistanceBetweenInsertionPoints:NULL];
        self.selectedRange = NSMakeRange(characterIndex, 0);
        
        self.editable = YES;
        self.dataDetectorTypes = UIDataDetectorTypeNone;

        if (makeFirstResponder) {
            [self becomeFirstResponder];
        }
    }
}

- (void)_addEditingObserversIfNecessary;
{
    if (!_observingEditingNotifications) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(_EditableDataDetectingTextView_textDidBeginEditing:) name:UITextViewTextDidBeginEditingNotification object:self];
        [nc addObserver:self selector:@selector(_EditableDataDetectingTextView_textDidEndEditing:) name:UITextViewTextDidEndEditingNotification object:self];
        
        _observingEditingNotifications = YES;
    }
}

- (void)_EditableDataDetectingTextView_textDidBeginEditing:(NSNotification *)notification;
{
    [self setNeedsDisplay];
}

- (void)_EditableDataDetectingTextView_textDidEndEditing:(NSNotification *)notification;
{
    [self setNeedsDisplay];
}

@end
