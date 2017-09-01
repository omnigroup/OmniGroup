// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniFoundation/NSData-OFEncoding.h>

#import <OmniAppKit/OAAppearance.h>
#import <OmniAppKit/OAAppearanceColors.h>
#import <OmniUI/OUINoteTextView.h>
#import <OmniUI/NSTextStorage-OUIExtensions.h>

RCS_ID("$Id$");

#define ALLOW_LINK_DETECTION (YES)

static UIDataDetectorTypes typesToDetectWithUITextView = (
                                                          UIDataDetectorTypeLink |
                                                          UIDataDetectorTypePhoneNumber |
                                                          UIDataDetectorTypeAddress |
                                                          UIDataDetectorTypeCalendarEvent |
                                                          UIDataDetectorTypeShipmentTrackingNumber |
                                                          UIDataDetectorTypeFlightNumber |
                                                          UIDataDetectorTypeLookupSuggestion |
                                                          (UIDataDetectorTypes)0 // or-ing 0 on the end for easier enabling/disabling of cases above
                                                          );

CGFloat OUINoteTextViewPlacholderTopMarginAutomatic = -1000;

@interface OUINoteTextView () {
  @private
    BOOL _detectsLinks;
    NSString *_placeholder;
    BOOL _drawsPlaceholder;
    CGFloat _placeholderTopMargin;
    BOOL _drawsBorder;
    BOOL _observingEditingNotifications;
    __weak id <OUINoteTextViewAppearanceDelegate> _weak_appearanceDelegate;
}

// Redeclare as readwrite
@property (nonatomic, readwrite, getter=isConfiguringForEditing) BOOL configuringForEditing;
@property (nonatomic, readwrite, getter=isChangingThemedAppearance) BOOL changingThemedAppearance;
@property (nonatomic, readwrite, getter=isResigningFirstResponder) BOOL resigningFirstResponder;

@end

#pragma mark -

@implementation OUINoteTextView

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
        
    [self OUINoteTextView_commonInit];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OUINoteTextView_commonInit];
    return self;
}

- (void)OUINoteTextView_commonInit;
{
    _placeholderTopMargin = OUINoteTextViewPlacholderTopMarginAutomatic;
    _drawsPlaceholder = YES;
    _drawsBorder = NO;
    _detectsLinks = ALLOW_LINK_DETECTION;
    
    self.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    
    self.contentMode = UIViewContentModeRedraw;
    self.editable = NO;
    self.dataDetectorTypes = typesToDetectWithUITextView;
    self.alwaysBounceVertical = YES;
    
    [self appearanceDidChange];
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

- (void)drawRect:(CGRect)clipRect;
{
    [super drawRect:clipRect];
    
    if ([self _shouldDrawPlaceholder]) {
        UIFont *placeholderFont = [UIFont systemFontOfSize:[UIFont labelFontSize]];
        NSString *placeholder = self.placeholder;
        NSDictionary *attributes = @{
            NSFontAttributeName: placeholderFont,
            NSForegroundColorAttributeName: [self _placeholderTextColor],
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

            if (_placeholderTopMargin != OUINoteTextViewPlacholderTopMarginAutomatic) {
                textRect.origin.y = _placeholderTopMargin;
            } else {
                // If we are regular, but have a reasonably short height, also take the compact code path
                BOOL isVerticallyCompact = (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact);
                if (!isVerticallyCompact && CGRectGetHeight(self.bounds) <= 568) {
                    isVerticallyCompact = YES;
                }
                
                if (isVerticallyCompact) {
                    textRect.origin.y = CGRectGetHeight(textRect) / 3.0 - CGRectGetHeight(boundingRect) / 2.0;
                } else {
                    textRect.origin.y = CGRectGetHeight(textRect) / 2.0 - CGRectGetHeight(boundingRect) / 2.0;
                }
            }

            textRect.size = boundingRect.size;
            textRect = CGRectIntegral(textRect);

            [placeholder drawInRect:textRect withAttributes:attributes];
        }
    }
}

#pragma mark UITextView subclass

- (void)scrollRangeToVisible:(NSRange)range;
{
    // I've re-implemented -scrollRangeToVisible: because UITextView's implementation doesn't work when typing in a text view with a bottom content inset in the item editor in OmniFocus.
    //
    // rdar://problem/14397663
    
    // Need to ensure layout for the entire range or we get the wrong behavior in the edge case of typing at the end of the text.
    NSLayoutManager *layoutManager = self.layoutManager;
    [layoutManager ensureLayoutForCharacterRange:NSMakeRange(0, NSMaxRange(range))];
    
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    CGRect rect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:self.textContainer];

    // Make sure the rect is non-empty.
    // Give us a little vertical breathing room, but don't extend the rect into negative y coordinate space.
    rect = CGRectInset(rect, 0, -1 * self.font.lineHeight);
    rect.origin.y = MAX(0, rect.origin.y);
    rect.size.width = MAX(1, CGRectGetWidth(rect));
    rect = CGRectIntegral(rect);

    [self layoutIfNeeded];
    [self scrollRectToVisible:rect animated:YES];
}

- (void)setText:(NSString *)text;
{
    // TODO: Report radar.
    // -[UITextView setText:] is calling -setAttributedText: with attributes in the original string, preserving autodetected links.
    // This is undesirable, so we build an attributed string here with only the font and color attribute and call -setAttributedText directly.
    
    if (text != nil) {
        NSDictionary *textAttributes = @{ NSFontAttributeName: self.font, NSForegroundColorAttributeName: self.textColor ?: [self _textColor] };
        NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:textAttributes];
        [self setAttributedText:attributedText];
    } else {
        [self setAttributedText:nil];
    }
    
    self.selectedRange = NSMakeRange(0, 0);
    
    // Starting with iOS 7, the text storage is exposed.
    // To catch all cases of the text changing (and possibly needing to draw the placeholder string), we'd have to watch the storage.
    // OmniFocus doesn't use the text view that way, so we ignore that.
    [self setNeedsDisplay];
}

- (void)setAttributedText:(NSAttributedString *)attributedText;
{
    [super setAttributedText:attributedText];
    
    // Starting with iOS 7, the text storage is exposed.
    // To catch all cases of the text changing (and possibly needing to draw the placeholder string), we'd have to watch the storage.
    // OmniFocus doesn't use the text view that way, so we ignore that.
    // However, thanks to Apple, we do need to detect links on the text if we aren't in the process of editing it. bug:///134348 (iOS-OmniFocus Bug: Implement our own link detection for notes) and bug:///134447 (iOS-OmniFocus Regression: Data detection for phone numbers and addresses no longer works)
    if (![self isFirstResponder] && _detectsLinks) {
        self.dataDetectorTypes = typesToDetectWithUITextView;
    }
    [self setNeedsDisplay];
}

- (BOOL)resignFirstResponder;
{
    self.resigningFirstResponder = YES;
    BOOL result = [super resignFirstResponder];
    
    if (result && _detectsLinks) {
        // Set editable to NO when resigning first responder so that links are tappable.
        self.editable = NO;
        self.dataDetectorTypes = typesToDetectWithUITextView;
    }
    
    self.resigningFirstResponder = NO;
    return result;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event NS_EXTENSION_UNAVAILABLE_IOS("");
{
    [super touchesEnded:touches withEvent:event];
    
    // If we got to -touchesEnded and a link was NOT tapped, move the insertion point underneath the touch and become editable and firstResponder.
    [self _openLinkOrBecomeEditableWithTouches:touches makeFirstResponder:YES];
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

#pragma mark Public

@synthesize appearanceDelegate = _weak_appearanceDelegate;

- (void)setAppearanceDelegate:(id<OUINoteTextViewAppearanceDelegate>)appearanceDelegate;
{
    if (appearanceDelegate == _weak_appearanceDelegate) {
        return;
    }
    
    _weak_appearanceDelegate = appearanceDelegate;
    [self appearanceDidChange];
}

- (void)appearanceDidChange;
{
    self.changingThemedAppearance = YES;
    {
        if (self.appearanceDelegate != nil) {
            self.layer.borderColor = [self.appearanceDelegate borderColorForTextView:self].CGColor;
            self.keyboardAppearance = [self.appearanceDelegate keyboardAppearanceForTextView:self];
            [self reloadInputViews];
        } else {
            self.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        }
        
        self.textColor = [self _textColor];
    }
    self.changingThemedAppearance = NO;
    
    [self setNeedsDisplay];
}

#pragma mark Private

- (BOOL)_shouldDrawPlaceholder;
{
    return (![self isFirstResponder] && ![self hasText] && _drawsPlaceholder && ![NSString isEmptyString:_placeholder]);
}

- (void)_openLinkOrBecomeEditableWithTouches:(NSSet *)touches makeFirstResponder:(BOOL)makeFirstResponder NS_EXTENSION_UNAVAILABLE_IOS("");
{
    if ([self isEditable])
        return;

    OBASSERT([touches count] == 1); // Otherwise, we are using a random one

    NSLayoutManager *layoutManager = self.layoutManager;
    NSTextContainer *textContainer = self.textContainer;
    NSTextStorage *textStorage = self.textStorage;

    // Offset the touch for the text container insert
    CGPoint point = [[touches anyObject] locationInView:self];
    UIEdgeInsets textContainerInset = self.textContainerInset;
    point.y -= textContainerInset.top;
    point.x -= textContainerInset.left;

    NSString *text = self.text;
    CGFloat partialFraction;
    NSUInteger characterIndex = [layoutManager characterIndexForPoint:point inTextContainer:textContainer fractionOfDistanceBetweenInsertionPoints:&partialFraction];
    if (partialFraction > 0.0f && partialFraction < 1.0f) {
        // Check to see whether the touch landed on a link
        NSURL *linkURL = [textStorage attribute:NSLinkAttributeName atIndex:characterIndex effectiveRange:NULL];
        if (linkURL != nil) {
            return; // UIKit will handle opening this link after the touch ends, as long as we don't block it by making ourselves editable.
        }
    }

    self.editable = YES;

    // We don't want live links when editing. Leaving them live exposes underlying user interaction bugs in UITextView where the link range is extended inappropriately.
    self.dataDetectorTypes = UIDataDetectorTypeNone;
    NSDictionary *textAttributes = @{ NSFontAttributeName: self.font, NSForegroundColorAttributeName: self.textColor ?: [self _textColor] };
    self.configuringForEditing = YES;
    [textStorage beginEditing];
    {
        [textStorage removeAllLinks];
        [textStorage addAttributes:textAttributes range:NSMakeRange(0, textStorage.length)];
    }
    [textStorage endEditing];
    [layoutManager ensureLayoutForCharacterRange:NSMakeRange(0, textStorage.length)];
    self.configuringForEditing = NO;

    // Replicate UITextView's behavior where it puts the insertion point before/after the word clicked in.
    // We choose the nearest end based on character distance, not pixel distance.

    __block BOOL didSetSelectedRange = NO;
    NSStringEnumerationOptions options = (NSStringEnumerationByWords | NSStringEnumerationLocalized);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(characterIndex, 0)];
    [text enumerateSubstringsInRange:lineRange options:options usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (NSLocationInRange(characterIndex, enclosingRange)) {
            *stop = YES;
            if (characterIndex - enclosingRange.location < NSMaxRange(enclosingRange) - characterIndex) {
                self.selectedRange = NSMakeRange(substringRange.location, 0);
                didSetSelectedRange = YES;
            } else {
                if (NSMaxRange(enclosingRange) < text.length) {
                    unichar character = [text characterAtIndex:NSMaxRange(enclosingRange)];
                    if ([[NSCharacterSet newlineCharacterSet] characterIsMember:character]) {
                        enclosingRange.length -= 1;
                    }
                }
                self.selectedRange = NSMakeRange(NSMaxRange(enclosingRange), 0);
                didSetSelectedRange = YES;
            }
        }
    }];

    // If we didn't set the selected range above, we probably clicked on an empty line
    if (!didSetSelectedRange) {
        self.selectedRange = NSMakeRange(characterIndex, 0);
    }

    if (makeFirstResponder) {
        [self becomeFirstResponder];
    }
}

- (void)_addEditingObserversIfNecessary;
{
    if (!_observingEditingNotifications) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(_OUINoteTextView_textDidBeginEditing:) name:UITextViewTextDidBeginEditingNotification object:self];
        [nc addObserver:self selector:@selector(_OUINoteTextView_textDidEndEditing:) name:UITextViewTextDidEndEditingNotification object:self];
        
        _observingEditingNotifications = YES;
    }
}

- (void)_OUINoteTextView_textDidBeginEditing:(NSNotification *)notificaton;
{
    [self setNeedsDisplay];
}

- (void)_OUINoteTextView_textDidEndEditing:(NSNotification *)notificaton;
{
    [self setNeedsDisplay];
}

- (UIColor *)_textColor;
{
    if (self.appearanceDelegate != nil) {
        return [self.appearanceDelegate textColorForTextView:self];
    } else {
        return [OAAppearanceDefaultColors appearance].omniNeutralDeemphasizedColor;
    }
}

- (UIColor *)_placeholderTextColor;
{
    if (self.appearanceDelegate != nil) {
        return [self.appearanceDelegate placeholderTextColorForTextView:self];
    } else {
        return [OAAppearanceDefaultColors appearance].omniNeutralPlaceholderColor;
    }
}

@end
