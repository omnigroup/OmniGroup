// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextView.h>

#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/NSLayoutManager-OAExtensions.h>
#import <OmniUI/NSTextStorage-OUIExtensions.h>
#import <OmniUI/OUITextColorAttributeInspectorSlice.h>
#import <OmniUI/OUIFontAttributesInspectorSlice.h>
#import <OmniUI/OUIFontFamilyInspectorSlice.h>
#import <OmniUI/OUIFontSizeInspectorSlice.h>
#import <OmniUI/OUIParagraphStyleInspectorSlice.h>
#import <OmniUI/OUIScalingTextStorage.h>
#import <OmniUI/OUISingleViewInspectorPane.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/OUITextSelectionSpan.h>
#import <OmniUI/OUIFontUtilities.h>
#import <OmniFoundation/NSUndoManager-OFExtensions.h>
#import <OmniFoundation/OFGeometry.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniUI/UIView-OUIExtensions.h>


RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

// Deprecated methods from OUIEditableFrameDelegate
OBDEPRECATED_METHOD(-textView:shouldInsertText:);
OBDEPRECATED_METHOD(-textView:shouldDeleteBackwardsFromIndex:);
OBDEPRECATED_METHOD(-textViewContentsChanged:);
OBDEPRECATED_METHOD(-textViewLayoutChanged:);
OBDEPRECATED_METHOD(-textViewSelectionChanged:);
//OBDEPRECATED_METHOD(-textViewShouldEndEditing:); UITextView has this too
OBDEPRECATED_METHOD(-textViewWillEndEditing:);
//OBDEPRECATED_METHOD(-textViewDidEndEditing:); UITextView has this too
OBDEPRECATED_METHOD(-textViewCanShowContextMenu:);
OBDEPRECATED_METHOD(-textView:canPasteFromPasteboard:);
OBDEPRECATED_METHOD(-readAttributedStringFromPasteboard:forTextView:);
OBDEPRECATED_METHOD(-writeAttributedStringFromTextRange:toPasteboard:forTextView:);
OBDEPRECATED_METHOD(-customMenuItemsForTextView:);
OBDEPRECATED_METHOD(-canPerformEditingAction:forTextView:withSender:);

NSString * const OUITextViewInsertionPointDidChangeNotification = @"OUITextViewInsertionPointDidChangeNotification";

@interface OUITextViewSelectedTextHighlightView : UIView
@property (nonatomic, copy) UIColor *selectionColor;
@end

@implementation OUITextView
{
    OUIInspector *_textInspector;
    OUITextViewSelectedTextHighlightView *_selectedTextHighlightView;
}

static OUITextView * _Nullable _activeFirstResponderTextView = nil;

+ (OUITextView *)activeFirstResponderTextView;
{
    return _activeFirstResponderTextView;
}

#pragma mark Debugging helpers

const OUIEnumName OUITextDirectionEnumNames[] = {
    { UITextStorageDirectionForward, CFSTR("Forward") },
    { UITextStorageDirectionBackward, CFSTR("Backward") },
    { UITextLayoutDirectionRight, CFSTR("Right") },
    { UITextLayoutDirectionLeft, CFSTR("Left") },
    { UITextLayoutDirectionUp, CFSTR("Up") },
    { UITextLayoutDirectionDown, CFSTR("Down") },
    { 0, NULL }
};
const OUIEnumName OUITextSelectionGranularityNames[] = {
    { UITextGranularityCharacter, CFSTR("Character") },
    { UITextGranularityWord, CFSTR("Word") },
    { UITextGranularitySentence, CFSTR("Sentence") },
    { UITextGranularityParagraph, CFSTR("Paragraph") },
    { UITextGranularityLine, CFSTR("Line") },
    { UITextGranularityDocument, CFSTR("Document") },
    { 0, NULL }
};

NSString *OUINameOfEnum(NSInteger v, const OUIEnumName *ns)
{
    int value = (int)v;
    while(ns->name) {
        if (ns->value == value)
            return (__bridge NSString *)(ns->name);
        ns ++;
    }
    return [NSString stringWithFormat:@"<%d>", value];
}

#ifdef DEBUG_TEXT_ENABLED
// Returns an ASCII art description of the selection with some context around it, if possible. Not terribly efficient, but don't care...
static NSString *_selectionDescription(OUITextView *self, OUEFTextRange *selection)
{
    NSUInteger st = [(OUEFTextPosition *)[selection start] index];
    NSUInteger en = [(OUEFTextPosition *)[selection end] index];
    static NSUInteger kContextSize = 10;
    
    NSString *string = [self->_content string];
    NSUInteger stringLength = [string length];
    OBASSERT(st <= stringLength);
    OBASSERT(en <= stringLength);
    OBASSERT(st <= en);
    
    NSMutableString *desc = [NSMutableString string];
    
    if (st > 0) {
        NSUInteger availableContext = MIN(st, kContextSize);
        [desc appendString:[string substringWithRange:NSMakeRange(st - availableContext, availableContext)]];
    }
    
    if (st == en)
        [desc appendString:@"|"];
    else {
        [desc appendString:@"["];
        
        if (st + 3*kContextSize > en) {
            [desc appendString:[string substringWithRange:NSMakeRange(st, en - st)]];
        } else {
            [desc appendString:[string substringWithRange:NSMakeRange(st, kContextSize)]];
            [desc appendString:@"..."];
            [desc appendString:[string substringWithRange:NSMakeRange(en - kContextSize, kContextSize)]];
        }
        
        [desc appendString:@"]"];
    }
    
    if (en < stringLength) {
        NSUInteger availableContext = MIN(stringLength - en, kContextSize);
        [desc appendString:[string substringWithRange:NSMakeRange(en, availableContext)]];
    }
    
    // TODO: Escape newlines and quotes?
    [desc insertString:@"\"" atIndex:0];
    [desc appendString:@"\""];
    
    return desc;
}

static NSString *_positionDescription(OUITextView *self, OUEFTextPosition *position)
{
    OUEFTextRange *range = [[[OUEFTextRange alloc] initWithStart:position end:position] autorelease];
    return _selectionDescription(self, range);
}
#endif

+ (CGFloat)oui_defaultTopAndBottomPadding;
{
    return 8.0;
}

// TODO: Close the inspector before a mutation happens, unless the mutation is only attributes
// TODO: Close the inspector when we end editing
// TODO: Don't end editing if the inspector is up and we get -resignFirstResponder

- (void)dealloc;
{
    _textInspector.delegate = nil;
}

- (void)setFrame:(CGRect)frame
{
    NSTextContainer *textContainer = self.textContainer;
    CGSize oldContainerSize = textContainer.size;
    [super setFrame:frame];
    CGSize updatedContainerSize = textContainer.size;
    CGSize newContainerSize;
    newContainerSize.width = textContainer.widthTracksTextView ? updatedContainerSize.width : oldContainerSize.width;
    newContainerSize.height = textContainer.heightTracksTextView ? updatedContainerSize.height : oldContainerSize.height;
    if (!CGSizeEqualToSize(newContainerSize, updatedContainerSize)) {
        textContainer.size = newContainerSize;
    }

    if (_selectedTextHighlightView) {
        frame.origin = CGPointZero;
        _selectedTextHighlightView.frame = frame;
        [_selectedTextHighlightView setNeedsDisplay];
    }
}

- (CGFloat)textHeight;
{
    NSLayoutManager *layoutManager = self.layoutManager;
    
    [layoutManager ensureLayoutForTextContainer:self.textContainer];
    if (layoutManager.numberOfGlyphs == 0) {
        // The layout manager will return zero height in this case. But, if we are a field editor, we want to take up space equal to our typing attributes.
        return [NSLayoutManager heightForAttributes:self.typingAttributes];
    }
    
    return [layoutManager totalHeightUsed];
}

// This does not account for any contentInset or lineFragmentPadding.
- (CGSize)textUsedSize;
{
    NSLayoutManager *layoutManager = self.layoutManager;
    return CGSizeMake(layoutManager.widthOfLongestLine, layoutManager.totalHeightUsed);
}

- (CGFloat)firstLineAscent;
{
    OBFinishPortingLater("<bug:///147846> (iOS-OmniOutliner Bug: Return actual firstLineAscent instead of bogus value)");
    return 0;
}

- (NSDictionary *)typingAttributesWithAllAttributes;
{
    return self.typingAttributes;
}

- (void)ensureLayout;
{
    [self.layoutManager ensureLayoutForTextContainer:self.textContainer];
}

- (nullable UITextRange *)selectionRangeForPoint:(CGPoint)pt granularity:(UITextGranularity)granularity;
{
    UITextPosition *hitPosition = [self closestPositionToPoint:pt];
    if (!hitPosition)
        return nil;
    
    if (granularity != UITextGranularityCharacter) {
        UITextRange *range = [self.tokenizer rangeEnclosingPosition:hitPosition withGranularity:granularity inDirection:UITextStorageDirectionForward];
        if (range)
            return range;
        // Fall back to the UITextGranularityCharacter case.
    }
    
    return [self textRangeFromPosition:hitPosition toPosition:hitPosition];
}

// For use when a field editor is coming on screen and we want to act like UITextView would if it were already on screen when tapped (select the beginning/ending of a word).
- (void)selectForInitialTapAtPoint:(CGPoint)pt;
{
    UITextPosition *hitPosition = [self closestPositionToPoint:pt];
    if (!hitPosition)
        return;
    
    id <UITextInputTokenizer> tokenizer = self.tokenizer;
    UITextPosition *backwardWordBreakPosition = [tokenizer positionFromPosition:hitPosition toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
    if (!backwardWordBreakPosition)
        backwardWordBreakPosition = [self beginningOfDocument];
    
    UITextPosition *forwardWordBreakPosition = [tokenizer positionFromPosition:hitPosition toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionForward];
    if (!forwardWordBreakPosition)
        forwardWordBreakPosition = [self endOfDocument];
    
    CGRect backwardRect = [self caretRectForPosition:backwardWordBreakPosition];
    OBASSERT(!CGRectIsNull(backwardRect));
    
    CGRect forwardRect = [self caretRectForPosition:forwardWordBreakPosition];
    OBASSERT(!CGRectIsNull(forwardRect));
    
    CGFloat backwardDistance = OFSquareOfDistanceFromPointToCenterOfRect(pt, backwardRect);
    CGFloat forwardDistance = OFSquareOfDistanceFromPointToCenterOfRect(pt, forwardRect);
    
    UITextPosition *bestPosition = (backwardDistance < forwardDistance) ? backwardWordBreakPosition : forwardWordBreakPosition;
    if (!bestPosition)
        bestPosition = hitPosition;
    
    self.selectedTextRange = [self textRangeFromPosition:bestPosition toPosition:bestPosition];
}

- (CGRect)boundsOfRange:(UITextRange *)range;
{
    OBPRECONDITION(range);    
    if (!range) {
        UITextPosition *start = self.beginningOfDocument;
        range = [self textRangeFromPosition:start toPosition:start];
    }
    
    if ([range isEmpty]) {
        return [self caretRectForPosition:range.start];
    } else {
        CGRect unionRect = CGRectNull;
        for (UITextSelectionRect *selectionRect in [self selectionRectsForRange:range]) {
            if (CGRectIsNull(unionRect))
                unionRect = selectionRect.rect;
            else
                unionRect = CGRectUnion(unionRect, selectionRect.rect);
        }
        return unionRect;
    }
}

- (NSRange)characterRangeForTextRange:(UITextRange *)textRange;
{
    NSInteger beginningOffset = [self offsetFromPosition:self.beginningOfDocument toPosition:textRange.start];
    NSInteger endingOffset = [self offsetFromPosition:self.beginningOfDocument toPosition:textRange.end];
    
    if (beginningOffset < 0 || beginningOffset > endingOffset) {
        OBASSERT_NOT_REACHED("Weird text range");
        return NSMakeRange(NSNotFound, 0);
    }

    return NSMakeRange(beginningOffset, endingOffset - beginningOffset);
}

- (UITextRange *)textRangeForCharacterRange:(NSRange)characterRange;
{
    UITextPosition *startPosition = [self positionFromPosition:self.beginningOfDocument offset:characterRange.location];
    UITextPosition *endPosition = [self positionFromPosition:self.beginningOfDocument offset:NSMaxRange(characterRange)];
    
    return [self textRangeFromPosition:startPosition toPosition:endPosition];
}

#if 0 && defined(DEBUG)
#define DEBUG_SCROLL(format, ...) NSLog(@"SCROLL: " format, ## __VA_ARGS__)
#else
#define DEBUG_SCROLL(format, ...) do {} while (0)
#endif

static CGFloat _scrollCoord(OFExtent containerExtent, OFExtent innerExtent)
{
    CGFloat minEdgeDistance = fabs(OFExtentMin(containerExtent) - OFExtentMin(innerExtent));
    CGFloat maxEdgeDistance = fabs(OFExtentMax(containerExtent) - OFExtentMax(innerExtent));
    
    DEBUG_SCROLL(@" minEdgeDistance %f, maxEdgeDistance %f", minEdgeDistance, maxEdgeDistance);
    
    if (minEdgeDistance < maxEdgeDistance) {
        return OFExtentMin(innerExtent);
    } else {
        return OFExtentMax(innerExtent) - OFExtentLength(containerExtent);
    }
}

const CGFloat OUIScrollContext = 15;

static void _scrollVerticallyInView(OUITextView *textView, CGRect viewRect, BOOL animated)
{
    DEBUG_SCROLL(@"vertical: view:%@ viewRect %@ animated %d", [textView shortDescription], NSStringFromCGRect(viewRect), animated);
    
    DEBUG_SCROLL(@" viewRect %@", NSStringFromCGRect(viewRect));
    
    CGRect scrollBounds = textView.bounds;
    
    OFExtent targetViewYExtent = OFExtentFromRectYRange(viewRect);
    OFExtent scrollBoundsYExtent = OFExtentFromRectYRange(scrollBounds);
    
    DEBUG_SCROLL(@" targetViewYExtent = %@, scrollBoundsYExtent = %@", OFExtentToString(targetViewYExtent), OFExtentToString(scrollBoundsYExtent));
    DEBUG_SCROLL(@" scroll bounds %@, scroll offset %@", NSStringFromCGRect(textView.bounds), NSStringFromCGPoint(textView.contentOffset));
    
    if (OFExtentMin(targetViewYExtent) < OFExtentMin(scrollBoundsYExtent) + OUIScrollContext) {
        CGFloat extraScrollPadding = CLAMP(OUIScrollContext, 0.0f, textView.contentOffset.y);
        targetViewYExtent.length += extraScrollPadding; // When we scroll, try to show a little context on the other side
        targetViewYExtent.location -= extraScrollPadding; // If we're scrolling up, we want our target to extend up rather than down
    } else {
        CGFloat extraScrollPadding = CLAMP(OUIScrollContext, 0.0f, OFExtentLength(scrollBoundsYExtent) - OFExtentLength(targetViewYExtent));
        targetViewYExtent.length += extraScrollPadding; // When we scroll, try to show a little context on the other side
    }
    
    if (OFExtentContainsExtent(scrollBoundsYExtent, targetViewYExtent)) {
        DEBUG_SCROLL(@" already visible");
        return; // Already fully visible
    }
    
    if (OFExtentContainsExtent(targetViewYExtent, scrollBoundsYExtent)) {
        DEBUG_SCROLL(@" everything visible is already within the target");
        return; // Everything visible is already within the target
    }
    
    CGPoint contentOffset = textView.contentOffset;
    contentOffset.y = _scrollCoord(scrollBoundsYExtent, targetViewYExtent);
    
    // UIScrollView ignores +[UIView areAnimationsEnabled]. Don't provoke animation when we shouldn't be animating.
    animated &= [UIView areAnimationsEnabled];
    
    [textView setContentOffset:contentOffset animated:animated];
}

// Currently assumes the text view is only vertically scrollable.
- (void)scrollTextSelectionToVisibleWithAnimation:(BOOL)animated;
{
    // Make sure the layout is up to date before we ask where text is.
    [self ensureLayout];
    [self layoutIfNeeded];
    
    UITextRange *selection = self.selectedTextRange;
    if (selection && [self window]) {
        CGRect selectionRect = [self boundsOfRange:selection];
        _scrollVerticallyInView(self, selectionRect, animated);
    }
}

- (NSArray *)inspectableObjects;
{
    return self.inspectableTextSpans;
}

- (NSArray *)inspectableTextSpans;
{
    return [self.textStorage textSpansInRange:self.selectedRange inTextView:self];
}

- (BOOL)isEmptyInspectableTextSpans:(NSArray *)spans;
{
    NSUInteger spanCount = [spans count];
    if (spanCount == 0)
        return YES;
    OUITextSelectionSpan *firstSpan = spans[0];
    if (spanCount == 1)
        return firstSpan.range.isEmpty;
    
    OBASSERT(firstSpan.range.isEmpty == NO);
    return NO;
}

- (nullable OUITextSelectionSpan *)firstNonEmptyInspectableTextSpan;
{
    NSArray *spans = [self inspectableTextSpans];
    if ([self isEmptyInspectableTextSpans:spans])
        return nil;

    OUITextSelectionSpan *firstSpan = spans[0];
    OBASSERT(firstSpan.range.isEmpty == NO);
    return firstSpan;
}

- (OUIInspector *)textInspector;
{
    return _textInspector;
}

- (void)dismissInspectorImmediatelyIfVisible;
{
    // <bug:///137426> (iOS-OmniGraffle Unassigned: Fix Text Inspector)
//    [_textInspector dismissImmediatelyIfVisible];
}

// <bug:///137426> (iOS-OmniGraffle Unassigned: Fix Text Inspector)
- (void)inspectSelectedTextWithViewController:(UIViewController *)viewController fromBarButtonItem:(UIBarButtonItem *)barButtonItem withSetupBlock:(void (^ _Nullable)(OUIInspector *))setupBlock;
{
//    NSArray *runs = [self _configureInspector];
    if (setupBlock != NULL)
        setupBlock(_textInspector);

//    [_textInspector inspectObjects:runs withViewController:viewController fromBarButtonItem:barButtonItem];
//    [self.textInspector inspectObjects:runs];
    [self.textInspector updateInspectedObjects];
    self.alwaysHighlightSelectedText = YES;
}

- (void)selectAllShowingMenu:(BOOL)show;
{
    UITextRange *range = [self textRangeFromPosition:self.beginningOfDocument toPosition:self.endOfDocument];
    [self setSelectedTextRange:range showingMenu:show];
}

- (void)setSelectedTextRange:(nullable UITextRange *)newRange showingMenu:(BOOL)show;
{
    self.selectedTextRange = newRange;
    
    OBFinishPortingLater("<bug:///147847> (iOS-OmniOutliner Bug: Obey ‘show’ argument in -[OUITextView setSelectedTextRange:showingMenu:])");
#if 0
    if (newRange != nil && ![newRange isEmpty]) {
        if (show) { // nested so we don't automatically hide the menu when visible is false, we just don't force it to show
            // As of the 4.3 SDK (and 5.1.1), if this selection change was due to a tap on the Select or Select All menu items, UIKit ignores our request to show the menu again, so instead we defer the showing until the hiding is done:
            [_editMenuController showMainMenuAfterCurrentMenuFinishesHiding];
        }
    } else
        [_editMenuController hideMenu];
#endif
}

static BOOL _rangeIsInsertionPoint(OUITextView  *self, UITextRange *r)
{
    if (![r isEmpty])
        return NO;
    
    UITextRange *selectedTextRange = self.selectedTextRange;
    return OFISEQUAL(r, selectedTextRange);
}

- (NSDictionary *)attributesInRange:(UITextRange *)r;
{
    // Inspectors want the attributes of the beginning of the first range of selected text.
    // I'm passing in the whole range right now since it isn't clear yet how we should behave in the face of embedded bi-di text; should we always do the first position by character order, or the first character by visual rendering order. Doing the easy thing for now.
    
    if (_rangeIsInsertionPoint(self, r))
        return [self typingAttributes];
    
    NSRange range = [self characterRangeForTextRange:r];
    NSTextStorage *textStorage = [self.textStorage underlyingTextStorage];
    return [textStorage attributesAtIndex:range.location effectiveRange:NULL];
}

- (id <NSObject>)attribute:(NSString *)attr inRange:(UITextRange *)range;
{
    if (range.isEmpty)
        return [[self typingAttributes] objectForKey:attr];
    
    // Might be a scaling text storage.
    NSTextStorage *textStorage = [self.textStorage underlyingTextStorage];
    NSRange characterRange = [self characterRangeForTextRange:range];

    return [textStorage attribute:attr atIndex:characterRange.location effectiveRange:NULL];
}

- (void)setValue:(id)value forAttribute:(NSString *)attr inRange:(UITextRange *)range;
{
    if (range.isEmpty) {
        NSMutableDictionary *attributes = [self.typingAttributes mutableCopy];
        if (value)
            [attributes setObject:value forKey:attr];
        else
            [attributes removeObjectForKey:attr];
        self.typingAttributes = attributes;
        return;
    }
    
    // Might be a scaling text storage.
    NSTextStorage *textStorage = [self.textStorage underlyingTextStorage];
    NSRange characterRange = [self characterRangeForTextRange:range];
    
    [textStorage beginEditing];
    if (value)
        [textStorage addAttribute:attr value:value range:characterRange];
    else
        [textStorage removeAttribute:attr range:characterRange];
    [textStorage endEditing];
    
    if ([self.delegate respondsToSelector:@selector(textView:didChangeAttributesInRange:)]) {
        [self.delegate textView:self didChangeAttributesInRange:range];
        [_selectedTextHighlightView setNeedsDisplay];
    }
}

- (void)insertAfterSelection:(NSAttributedString *)attributedString;
{
    NSTextStorage *textStorage = self.textStorage;
    
    NSRange selectedRange = self.selectedRange;
    NSRange insertionRange;
    if (selectedRange.location == NSNotFound)
        insertionRange = NSMakeRange([textStorage length], 0);
    else
        insertionRange = NSMakeRange(NSMaxRange(selectedRange), 0);
    
    [textStorage beginEditing];
    [textStorage replaceCharactersInRange:insertionRange withAttributedString:attributedString];
    [textStorage endEditing];
    
    self.selectedRange = NSMakeRange(insertionRange.location + [attributedString length], 0);
}

- (void)extendSelectionToSurroundingWhitespace;
{
    NSRange selectionRange = self.selectedRange;
    NSUInteger startLocation = selectionRange.location;
    NSUInteger endLocation = startLocation + selectionRange.length;
    
    NSTextStorage *textStorage = self.textStorage;
    NSString *text = textStorage.string;
    
    while (startLocation) {
        if (![[NSCharacterSet whitespaceCharacterSet] characterIsMember:[text characterAtIndex:startLocation - 1]])
            break;
        startLocation--;
    }
    
    while (endLocation < [text length]) {
        if (![[NSCharacterSet whitespaceCharacterSet] characterIsMember:[text characterAtIndex:endLocation]])
            break;
        endLocation++;
    }
    
    self.selectedRange = NSMakeRange(startLocation, endLocation - startLocation);
}


- (BOOL)hasTouch:(UITouch *)touch;
{
    if (!self.window || self.window != touch.window) {
        return NO;
    }
    
    UIView *hitView = [self hitTest:[touch locationInView:self] withEvent:nil];
    OBASSERT(!hitView || hitView.hidden == NO);
    return (hitView != nil);
}

- (BOOL)hasTouchByGestureRecognizer:(UIGestureRecognizer *)recognizer;
{
    OBPRECONDITION(recognizer);
    
    if (!self.window) {
        return NO;
    }
    
    // Thumbs and autocorrection/substitution views can extend outside our bounds. All are subviews, so just use our -hitTest:
    UIView *hitView = [self hitTest:[recognizer locationInView:self] withEvent:nil];
    OBASSERT(!hitView || hitView.hidden == NO);
    return (hitView != nil);
}

/*
 
 Radar 14347931: TextKit: Document how to register undos for programatic mutations
 
 NSTextView automatically records undos for programatic changes via -shouldChangeTextInRange:replacementString: and -didChangeText, but UITextView has no such thing. So, we need to record our own undos. Experimentally, this works with text undo coalescing.

 */
- (void)performUndoableEditOnSelectedRange:(void (^)(NSMutableAttributedString *))action;
{
    [self performUndoableEditOnRange:self.selectedRange action:action];
}

- (void)performUndoableEditOnRange:(NSRange)range action:(void (^)(NSMutableAttributedString *))action;
{
    NSTextStorage *textStorage = self.textStorage.underlyingTextStorage;
    
    OBPRECONDITION(NSMaxRange(range) <= [textStorage length]);
    
    // This defines our 'do' state.
    NSMutableAttributedString *edit = [[textStorage attributedSubstringFromRange:range] mutableCopy];
    action(edit);
    
    [self _replaceAttributedStringInRange:range withAttributedString:edit isUndo:NO];
}

// We expect zero change in the length in this version.
- (void)performUndoableEditToStylesInSelectedRange:(void (^)(NSTextStorage *textStorage))action;
{
    NSTextStorage *textStorage = self.textStorage.underlyingTextStorage;
    
    // Should be no pending edits.
    OBASSERT(textStorage.editedMask == 0);
    OBASSERT(textStorage.editedRange.location == NSNotFound);
    OBASSERT(textStorage.changeInLength == 0);
    
    // Capture the original selected range
    NSRange selectedRange = self.selectedRange;
    NSAttributedString *originalString = [textStorage attributedSubstringFromRange:selectedRange];
    
    // Listen for the range that actually changed and perform the action
    __block BOOL notificationFired = NO;
    __block NSUInteger editedMask = 0;
    __block NSRange editedRange = NSMakeRange(NSNotFound, 0);
    __block NSInteger changeInLength = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:textStorage queue:nil/*synchronous*/ usingBlock:^(NSNotification *note){
        editedMask = textStorage.editedMask;
        editedRange = textStorage.editedRange;
        changeInLength = textStorage.changeInLength;
        notificationFired = YES;
    }];
    
    [textStorage beginEditing];
    action(textStorage);
    [textStorage endEditing];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    OBASSERT(notificationFired, "Did higher level code have an outstanding -beginEditing?");
    if (!notificationFired || editedMask == 0) {
        // action didn't end up doing anything.
        return;
    }

    OBASSERT(changeInLength == 0);
    
    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textViewDidChange:)])
        [delegate textViewDidChange:self];
    
    [[self prepareInvocationWithUndoManager: self.undoManager] _replaceAttributedStringInRange:selectedRange withAttributedString:originalString isUndo:YES];
}

- (void)performUndoableReplacementOnSelectedRange:(NSAttributedString *)replacement;
{
    [self _replaceAttributedStringInRange:self.selectedRange withAttributedString:replacement isUndo:NO];
}

// This seems nice, but it doesn't work out since UITextView doesn't draw the selection right if we shorten the text storage out from under the selection. Here we don't know the change in length beforehand, so we can't fix the selection first. So, we've split this into -performUndoableEditToStylesInSelectedRange: and -performUndoableReplacementOnSelectedRange:
#if 0
// A more general, but less efficient method. The assumption with this method is that the selected range is changing and that the updated range should be selected. This will send the 'did' delegate methods for change in selection and editing, but not the 'should'.
- (void)performUndoableEdit:(void (^)(NSTextStorage *textStorage))action;
{
    NSTextStorage *textStorage = self.textStorage.underlyingTextStorage;
    
    // Should be no pending edits.
    OBASSERT(textStorage.editedMask == 0);
    OBASSERT(textStorage.editedRange.location == NSNotFound);
    OBASSERT(textStorage.changeInLength == 0);
    
    // Capture the whole original string
    NSAttributedString *fullOriginalString = [[NSAttributedString alloc] initWithAttributedString:textStorage];
    
    // Listen for the range that actually changed and perform the action
    __block BOOL notificationFired = NO;
    __block NSUInteger editedMask = 0;
    __block NSRange editedRange = NSMakeRange(NSNotFound, 0);
    __block NSInteger changeInLength = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:textStorage queue:nil/*synchronous*/ usingBlock:^(NSNotification *note){
        editedMask = textStorage.editedMask;
        editedRange = textStorage.editedRange;
        changeInLength = textStorage.changeInLength;
        notificationFired = YES;
    }];
    
    [textStorage beginEditing];
    action(textStorage);
    [textStorage endEditing];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    OBASSERT(notificationFired, "Did higher level code have an outstanding -beginEditing?");
    if (!notificationFired || editedMask == 0) {
        // action didn't end up doing anything.
        return;
    }
    
    id <OUITextViewDelegate> delegate = self.delegate;

    if (!NSEqualRanges(self.selectedRange, editedRange)) {
        self.selectedRange = editedRange;
        if ([delegate respondsToSelector:@selector(textViewDidChangeSelection:)])
            [delegate textViewDidChangeSelection:self];
    }
    
    if ([delegate respondsToSelector:@selector(textViewDidChange:)])
        [delegate textViewDidChange:self];

    NSRange originalRange = NSMakeRange(editedRange.location, editedRange.length - changeInLength);
    NSAttributedString *originalString = [fullOriginalString attributedSubstringFromRange:originalRange];

    [[self prepareInvocationWithUndoManager: self.undoManager] _replaceAttributedStringInRange:editedRange withAttributedString:originalString];
}
#endif

- (void)_replaceAttributedStringInRange:(NSRange)range withAttributedString:(NSAttributedString *)attributedString isUndo:(BOOL)isUndo;
{
    id <OUITextViewDelegate> delegate = self.delegate;
    NSTextStorage *textStorage = self.textStorage.underlyingTextStorage;
    
    NSAttributedString *existingAttributedString = [textStorage attributedSubstringFromRange:range];
    NSRange afterEditRange = NSMakeRange(range.location, [attributedString length]);
    [[self prepareInvocationWithUndoManager: self.undoManager] _replaceAttributedStringInRange:afterEditRange withAttributedString:existingAttributedString isUndo:!isUndo];

    NSRange selectedRange = self.selectedRange;
    
    // Direct edits won't send the normal text changing methods

    // On undo, we select the range, but on 'do' we select the end of the range. For example, if you have "foo<bar>baz" with <bar> selected and you paste "bonk", you'll send up with "foobonk|bazp range" and on undo back to "foo<bar>baz"
    if (!isUndo)
        afterEditRange = NSMakeRange(NSMaxRange(afterEditRange), 0);
    
    if (NSMaxRange(afterEditRange) < NSMaxRange(selectedRange)) {
        // Shrinking; do the selection change before the edit
        self.selectedRange = afterEditRange;
        if ([delegate respondsToSelector:@selector(textViewDidChangeSelection:)])
            [delegate textViewDidChangeSelection:self];
    }
    
    [textStorage beginEditing];
    [textStorage replaceCharactersInRange:range withAttributedString:attributedString];
    [textStorage endEditing];
    
    if (NSMaxRange(afterEditRange) > NSMaxRange(selectedRange)) {
        // Growing; do the selection change after the edit
        self.selectedRange = afterEditRange;
        if ([delegate respondsToSelector:@selector(textViewDidChangeSelection:)])
            [delegate textViewDidChangeSelection:self];
    }

    if ([delegate respondsToSelector:@selector(textViewDidChange:)])
        [delegate textViewDidChange:self];
    
//    [self setNeedsLayout];
}

#pragma mark - Key commands

static BOOL _rangeContainsPosition(id <UITextInput> input, UITextRange *range, UITextPosition *position)
{
    if ([input comparePosition:range.start toPosition:position] == NSOrderedDescending)
        return NO;
    if ([input comparePosition:position toPosition:range.end] == NSOrderedDescending)
        return NO;
    return YES;
}

- (void)moveUpAtTop:(nullable id)sender;
{
    // For now, we handle all up/down cursor motion, due to 14962103: UITextView doesn't support up/down arrow for moving through lines
#if 1
    UITextPosition *position = self.selectedTextRange.start;

    if ([self.delegate respondsToSelector:@selector(textViewMoveUpAtTop:)]) {
        UITextRange *firstLineRange = [self.tokenizer rangeEnclosingPosition:self.beginningOfDocument withGranularity:UITextGranularityLine inDirection:UITextLayoutDirectionUp];
        if (firstLineRange && _rangeContainsPosition(self, firstLineRange, position)) {
            [self.delegate textViewMoveUpAtTop:self];
            return;
        }
    }
    // This calls -textViewDidChangeSelection:
    UITextPosition *upPosition = [self _closestPositionByMovingUpFromPosition:position];
    self.selectedTextRange = [self textRangeFromPosition:upPosition toPosition:upPosition];
#else
    if ([self.delegate respondsToSelector:@selector(textViewMoveUpAtTop:)])
        [self.delegate textViewMoveUpAtTop:self];
#endif
}

- (void)moveDownAtBottom:(nullable id)sender;
{
    // For now, we handle all up/down cursor motion, due to 14962103: UITextView doesn't support up/down arrow for moving through lines
#if 1
    UITextPosition *position = self.selectedTextRange.start;

    if ([self.delegate respondsToSelector:@selector(textViewMoveDownAtBottom:)]) {
        UITextRange *lastLineRange = [self.tokenizer rangeEnclosingPosition:self.endOfDocument withGranularity:UITextGranularityLine inDirection:UITextLayoutDirectionDown];
        // lastLineRange can be nil if you have "foo\n" and the insertion point is before the "f".
        if (lastLineRange && _rangeContainsPosition(self, lastLineRange, position)) {
            [self.delegate textViewMoveDownAtBottom:self];
            return;
        }
    }
    // This calls -textViewDidChangeSelection:
    UITextPosition *downPosition = [self _closestPositionByMovingDownFromPosition:position];
    self.selectedTextRange = [self textRangeFromPosition:downPosition toPosition:downPosition];
#else
    if ([self.delegate respondsToSelector:@selector(textViewMoveDownAtBottom:)])
        [self.delegate textViewMoveDownAtBottom:self];
#endif
}

- (void)moveRightAtEnd:(nullable id)sender;
{
    if ([self.delegate respondsToSelector:@selector(textViewMoveRightAtEnd:)])
        [self.delegate textViewMoveRightAtEnd:self];
}

- (void)moveLeftAtBeginning:(nullable id)sender;
{
    if ([self.delegate respondsToSelector:@selector(textViewMoveLeftAtBeginning:)])
        [self.delegate textViewMoveLeftAtBeginning:self];
}

- (void)moveToBeginningOfParagraph:(nullable id)sender;
{
    UITextPosition *position = self.selectedTextRange.start;
    UITextPosition *adjusted = [self.tokenizer positionFromPosition:position toBoundary:UITextGranularityParagraph inDirection:UITextStorageDirectionBackward];
    if (adjusted)
        self.selectedTextRange = [self textRangeFromPosition:adjusted toPosition:adjusted]; // This does call the delegate method -textViewDidChangeSelection:
}

- (void)moveToBeginningOfParagraphAndModifySelection:(nullable id)sender;
{
    UITextRange *selectedRange = self.selectedTextRange;
    UITextPosition *position = selectedRange.start;
    UITextPosition *adjusted = [self.tokenizer positionFromPosition:position toBoundary:UITextGranularityParagraph inDirection:UITextStorageDirectionBackward];
    if (adjusted)
        self.selectedTextRange = [self textRangeFromPosition:adjusted toPosition:selectedRange.end]; // This does call the delegate method -textViewDidChangeSelection:
}

- (void)moveToEndOfParagraph:(nullable id)sender;
{
    UITextPosition *position = self.selectedTextRange.end;
    UITextPosition *adjusted = [self.tokenizer positionFromPosition:position toBoundary:UITextGranularityParagraph inDirection:UITextStorageDirectionForward];
    if (adjusted)
        self.selectedTextRange = [self textRangeFromPosition:adjusted toPosition:adjusted]; // This does call the delegate method -textViewDidChangeSelection:
}

- (void)moveToEndOfParagraphAndModifySelection:(nullable id)sender;
{
    UITextRange *selectedRange = self.selectedTextRange;
    UITextPosition *position = selectedRange.end;
    UITextPosition *adjusted = [self.tokenizer positionFromPosition:position toBoundary:UITextGranularityParagraph inDirection:UITextStorageDirectionForward];
    if (adjusted)
        self.selectedTextRange = [self textRangeFromPosition:selectedRange.start toPosition:adjusted]; // This does call the delegate method -textViewDidChangeSelection:
}

#pragma mark - UITextView subclass

- (nullable id <OUITextViewDelegate>)delegate;
{
    return (id <OUITextViewDelegate>)[super delegate];
}
- (void)setDelegate:(nullable id<OUITextViewDelegate>)delegate;
{
    [super setDelegate:delegate];
}

- (void)deleteBackward;
{
    NSRange selectedRange = self.selectedRange;
    if (selectedRange.location == 0 && selectedRange.length == 0) {
        id <OUITextViewDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(textViewDeleteBackwardsAtBeginning:)])
            [delegate textViewDeleteBackwardsAtBeginning:self];
        return;
    }
    
	// To work around bug:///138525 (iOS-OmniGraffle Bug: Deleting text causes the canvas to move [jump])
    BOOL willBeEmpty = self.textStorage.length == 1 || self.textStorage.length == selectedRange.length;
    BOOL scrollEnabled = YES;
    UIScrollView *containingScrollview = [self.superview containingViewOfClass:[UIScrollView class]];
    CGPoint offsetToRestore;
    if (willBeEmpty) {
        if (containingScrollview) {
            scrollEnabled = containingScrollview.scrollEnabled;
            containingScrollview.scrollEnabled = NO;
            offsetToRestore = containingScrollview.contentOffset;
        }
    }
    [super deleteBackward];
    
    if (containingScrollview && willBeEmpty) {
        containingScrollview.scrollEnabled = scrollEnabled;
        containingScrollview.contentOffset = offsetToRestore;
    }
    
}

- (void)setSelectedTextRange:(nullable UITextRange *)selectedTextRange;
{
    // 14921726: TextKit: Selection controls should be dimmed and unresponsive while a popover is up
    // We'll dismiss the inspector in this case (since it is inspecting the original ranges of text and any edits it made would be to those old ranges). We could in theory update the inspected objects, but depending on what's in the selection/inspector the current view stack might not make sense (hypothetical, but say you had an image attachment selected and there was a filter/crop inspector pushed -- if you then adjusted the selection to be not on the image, we'd need to pop the child inspector pane).
    [super setSelectedTextRange:selectedTextRange];
    [[NSNotificationCenter defaultCenter] postNotificationName:OUITextViewInsertionPointDidChangeNotification object:self];
    
    [_textInspector.viewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - OUIKeyCommandProvider

- (nullable NSOrderedSet<NSString *> *)keyCommandCategories;
{
    return [[NSOrderedSet<NSString *> alloc] initWithObjects:@"text", nil];
}

- (nullable NSArray *)keyCommands;
{
    return [OUIKeyCommands keyCommandsForCategories:self.keyCommandCategories];
}

#pragma mark - UIResponder subclass

- (BOOL)becomeFirstResponder;
{
    if (![super becomeFirstResponder])
        return NO;

    _activeFirstResponderTextView = self;

    NSArray *menuItems = nil;
    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textViewCustomMenuItems:)])
        menuItems = [delegate textViewCustomMenuItems:self];

    [UIMenuController sharedMenuController].menuItems = menuItems;

    self.alwaysHighlightSelectedText = NO;

    return YES;
}

- (BOOL)resignFirstResponder;
{
    if (![super resignFirstResponder])
        return NO;

    OBASSERT(_activeFirstResponderTextView == self);
    _activeFirstResponderTextView = nil;

    return YES;
}

- (BOOL)alwaysHighlightSelectedText;
{
    return (_selectedTextHighlightView != nil);
}

- (void)setAlwaysHighlightSelectedText:(BOOL)shouldAlwaysHighlight;
{
    if (self.alwaysHighlightSelectedText == shouldAlwaysHighlight)
        return;

    if (shouldAlwaysHighlight) {
        _selectedTextHighlightView = [[OUITextViewSelectedTextHighlightView alloc] initWithFrame:self.bounds];
        _selectedTextHighlightView.selectionColor = [self.tintColor colorWithAlphaComponent:0.25f];
        [self addSubview:_selectedTextHighlightView];
    } else {
        [_selectedTextHighlightView removeFromSuperview];
        _selectedTextHighlightView = nil;
    }
}

static NSArray *_readableTypes(void)
{
    // The system currently adds RTFD, UTF plain text, and WebKit archives. If we just specify kUTTypeText, we'll only get back the plain text (also, WebKit doesn't conform to text at all). So, we'll add types for everything that NSAttributedString can supposedly read, based off <UIKit/NSAttributedString.h>
    return @[(OB_BRIDGE id)kUTTypeRTFD,
             (OB_BRIDGE id)kUTTypeFlatRTFD,
             (OB_BRIDGE id)kUTTypeHTML,
             (OB_BRIDGE id)kUTTypeRTF,
             (OB_BRIDGE id)kUTTypeText];
}

static BOOL _canReadFromTypes(UIPasteboard *pasteboard, NSArray *types)
{
    return [[pasteboard itemSetWithPasteboardTypes:types] count] > 0;
}

#if 0 && defined(DEBUG)
    #define DEBUG_ARROW(format, ...) NSLog(@"ARROW: " format, ## __VA_ARGS__)
#else
    #define DEBUG_ARROW(format, ...) do {} while (0)
#endif

- (UITextPosition *)_closestPositionByMovingUpFromPosition:(UITextPosition *)position;
{
    DEBUG_ARROW(@"going up from start from position %@", position);
    DEBUG_ARROW(@"  original upPosition = %@", [self positionFromPosition:position inDirection:UITextLayoutDirectionUp offset:1]);
    return [self _closestPositionInLineAdjacentToPosition:position byMovingInDirection:UITextLayoutDirectionLeft];
}
- (UITextPosition *)_closestPositionByMovingDownFromPosition:(UITextPosition *)position;
{
    DEBUG_ARROW(@"going down from start from position %@", position);
    DEBUG_ARROW(@"  original downPosition = %@", [self positionFromPosition:position inDirection:UITextLayoutDirectionDown offset:1]);
    return [self _closestPositionInLineAdjacentToPosition:position byMovingInDirection:UITextLayoutDirectionRight];
}

- (UITextPosition *)_closestPositionInLineAdjacentToPosition:(UITextPosition *)position byMovingInDirection:(UITextLayoutDirection)direction;
{
    // iOS 7.0 GM broke up/down cursor motion. 14962103: UITextView doesn't support up/down arrow for moving through lines
    // This won't work for bi-di or RTL text since we are assuming left/right map to eventually going up/down. We could try to fix this, but want to get the basic case working first.
    OBPRECONDITION(direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionRight, "All the other directions seem to be broken");
    
    UITextPosition *bestPosition = nil;
    CGFloat bestXOffset = CGFLOAT_MAX;
    CGRect startingCaretRect = [self caretRectForPosition:position];
    OFExtent startingLineCaretExtent = OFExtentFromRectYRange(startingCaretRect);
    OFExtent adjacentLineCaretExtent;
    BOOL isOnAdjacentLine = NO;
    CGFloat startX = CGRectGetMidX(startingCaretRect);
    
    DEBUG_ARROW(@"  startingLineCaretExtent = %@", OFExtentToString(startingLineCaretExtent));
    DEBUG_ARROW(@"  startX = %f", startX);
    
    UITextPosition *checkPosition = position;
    while (YES) {
        UITextPosition *nextPosition = [self positionFromPosition:checkPosition inDirection:direction offset:1];
        if (!nextPosition || [self comparePosition:checkPosition toPosition:nextPosition] == NSOrderedSame) {
            DEBUG_ARROW(@"  out of positions at %@", checkPosition);
            break;
        }
        checkPosition = nextPosition;
        DEBUG_ARROW(@"  checking %@", checkPosition);
        
        CGRect checkRect = [self caretRectForPosition:checkPosition];
        if (OFExtentContainsValue(startingLineCaretExtent, CGRectGetMidY(checkRect))) {
            // Still on the same line.
            DEBUG_ARROW(@"  same line");
            continue;
        } else {
            if (!isOnAdjacentLine) {
                // OK, finally to a new line. Remember that we've hit the new line and the extent of the adjancent line
                isOnAdjacentLine = YES;
                adjacentLineCaretExtent = OFExtentFromRectYRange(checkRect);
                DEBUG_ARROW(@"  hit adjacent line at %@, with extent %@", checkPosition, OFExtentToString(adjacentLineCaretExtent));
            } else {
                // Already were on a new line... have we gone onto yet another line? If so, we are done.
                if (!OFExtentContainsValue(adjacentLineCaretExtent, CGRectGetMidY(checkRect))) {
                    DEBUG_ARROW(@"  left adjacent line at %@ with caret rect %@", checkPosition, NSStringFromCGRect(checkRect));
                    break;
                }
            }
        }
        
        // Find the position within the adjancent line that has the smallest X offset, caret-center to caret-center.
        CGFloat xOffset = fabs(startX - CGRectGetMidX(checkRect));
        DEBUG_ARROW(@"  xOffset %f for %@", xOffset, checkPosition);
        
        if (!bestPosition || bestXOffset > xOffset) {
            bestXOffset = xOffset;
            bestPosition = checkPosition;
        }
    }
    
    if (!bestPosition)
        bestPosition = position; // Maybe already at the top/bottom
    DEBUG_ARROW(@"  bestPosition = %@", bestPosition);
    return bestPosition;
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender;
{
    if (self.keepContextualMenuHidden) {
        return NO;
    }
    
    // We want to provide extendable copy/paste support.
    if (action == @selector(paste:) || action == @selector(pasteTogglingPreserveStyle:)) {
        id <OUITextViewDelegate> delegate = self.delegate;
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        if ([delegate respondsToSelector:@selector(textViewReadablePasteboardTypes:)]) {
            NSArray *types = [delegate textViewReadablePasteboardTypes:self];
            if (_canReadFromTypes(pasteboard, types))
                return YES;
        }
        return _canReadFromTypes(pasteboard, _readableTypes());
    }
    
    if (action == @selector(cut:) || action == @selector(copy:))
        return self.selectedRange.length > 0;
    
    if (action == @selector(moveUpAtTop:)) {
        // If we have marked text, then the keyboard input system should get this (like via the Japanese-Kana keyboard)
        if (self.markedTextRange)
            return NO;
        
        // For now, we handle all up/down cursor motion, due to 14962103: UITextView doesn't support up/down arrow for moving through lines
        return YES;
#if 0
        if (![self.delegate respondsToSelector:@selector(textViewMoveUpAtTop:)])
            return NO;
        UITextPosition *position = self.selectedTextRange.start;
        UITextPosition *upPosition = [self _closestPositionByMovingUpFromPosition:position];
        
        // In betas, up-arrow in the first line would move to the beginning of the document. In 7.0, it stays put. In case of regression, check both.
        return [self comparePosition:upPosition toPosition:position] == NSOrderedSame ||
               [self comparePosition:upPosition toPosition:self.beginningOfDocument] == NSOrderedSame;
#endif
    }
    if (action == @selector(moveDownAtBottom:)) {
        // If we have marked text, then the keyboard input system should get this (like via the Japanese-Kana keyboard)
        if (self.markedTextRange)
            return NO;

        // For now, we handle all up/down cursor motion, due to 14962103: UITextView doesn't support up/down arrow for moving through lines
        return YES;
#if 0
        if (![self.delegate respondsToSelector:@selector(textViewMoveDownAtBottom:)])
            return NO;
        UITextPosition *position = self.selectedTextRange.start;
        UITextPosition *downPosition = [self positionFromPosition:position inDirection:UITextLayoutDirectionDown offset:0];
        
        // In betas, down-arrow in the last line would move to the end of the document. In 7.0, it stays put. In case of regression, check both.
        return [self comparePosition:downPosition toPosition:position] == NSOrderedSame ||
               [self comparePosition:downPosition toPosition:self.endOfDocument] == NSOrderedSame;
#endif
    }
    if (action == @selector(moveRightAtEnd:)) {
        // If we have marked text, then the keyboard input system should get this (like via the Japanese-Kana keyboard)
        if (self.markedTextRange)
            return NO;

        if (![self.delegate respondsToSelector:@selector(textViewMoveRightAtEnd:)])
            return NO;
        UITextPosition *position = self.selectedTextRange.start;
        return [self comparePosition:position toPosition:self.endOfDocument] == NSOrderedSame;
    }
    if (action == @selector(moveLeftAtBeginning:)) {
        // If we have marked text, then the keyboard input system should get this (like via the Japanese-Kana keyboard)
        if (self.markedTextRange)
            return NO;

        if (![self.delegate respondsToSelector:@selector(textViewMoveLeftAtBeginning:)])
            return NO;
        UITextPosition *position = self.selectedTextRange.start;
        return [self comparePosition:position toPosition:self.beginningOfDocument] == NSOrderedSame;
    }
    
    // UITextView's validation seems messed up. <bug:///94227> ("Select All" text editor selects all rows instead of all the text in the cell)
    if (action == @selector(selectAll:)) {
        NSTextStorage *textStorage = self.textStorage;
        if (textStorage.length == 0)
            return NO;
        if (NSEqualRanges(NSMakeRange(0, textStorage.length), self.selectedRange))
            return NO;
        return YES;
    }
    
    return [super canPerformAction:action withSender:sender];
}

- (void)cut:(nullable id)sender;
{
    NSRange range = self.selectedRange;
    if (range.length == 0) {
        OBASSERT_NOT_REACHED("-canPerformAction:withSender: should have filtered this out");
        return;
    }

    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)] &&
        ![delegate textView:self shouldChangeTextInRange:range replacementText:@""])
        return;
    
    [self copy:sender];

    NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:@"" attributes:nil];
    [self performUndoableReplacementOnSelectedRange:replacement];
}

- (void)copy:(nullable id)sender;
{
    NSRange range = self.selectedRange;
    if (range.length == 0) {
        OBASSERT_NOT_REACHED("-canPerformAction:withSender: should have filtered this out");
        return;
    }
    
    NSMutableDictionary *representations = [NSMutableDictionary dictionary];
    id <OUITextViewDelegate> delegate = self.delegate;

    // Make sure we operate on the underlying text storage to avoid having to scale and then anti-scale font sizes if this is a OUIScalingTextStorage
    NSTextStorage *textStorage = [self.textStorage underlyingTextStorage];

    if ([delegate respondsToSelector:@selector(textView:addPasteboardRepresentations:range:attributedString:)])
        [delegate textView:self addPasteboardRepresentations:representations range:range attributedString:textStorage];
    
    BOOL containsAttachments = [textStorage containsAttribute:NSAttachmentAttributeName inRange:range];
    
    // Add a rich text type if the delegate didn't already.
    if (representations[(OB_BRIDGE id)kUTTypeRTF] == nil && representations[(OB_BRIDGE id)kUTTypeRTFD] == nil) {
        // TODO: We might want to add RTF even if we also added RTFD if the system doesn't auto-convert for us.
        NSString *documentType, *dataType;
        if ([textStorage containsAttribute:NSAttachmentAttributeName inRange:range]) {
            documentType = NSRTFDTextDocumentType;
            dataType = (OB_BRIDGE NSString *)kUTTypeRTFD;
        } else {
            documentType = NSRTFTextDocumentType;
            dataType = (OB_BRIDGE NSString *)kUTTypeRTF;
        }
        
        __autoreleasing NSError *error = nil;
        NSData *data = [textStorage dataFromRange:range documentAttributes:@{NSDocumentTypeDocumentAttribute:documentType} error:&error];
        if (!data)
            [error log:@"Error archiving as %@", documentType];
        else
            representations[dataType] = data;
    }
    
    if (representations[(OB_BRIDGE id)kUTTypeUTF8PlainText] == nil) {
        NSString *string = [[textStorage string] substringWithRange:range];
        if (containsAttachments) {
            // Strip the attachment characters in this range. Could maybe get more fancy by collapsing spaces into a single space, but not going to mess with that for now.
            string = [string stringByReplacingOccurrencesOfString:[NSAttributedString attachmentString] withString:@""];
        }
        NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
        representations[(OB_BRIDGE NSString *)kUTTypeUTF8PlainText] = data;
    }
    
    NSMutableArray *items = [NSMutableArray arrayWithObject:representations];
    
    // See the comment on the delegate protocol for our strategy here. In sort, we do one rich-text-with-attachments pasteboard item and then pasteboard items for each of the attachments (for the benefit of non-rich text apps that handle just images).
    if (containsAttachments) {
        [textStorage enumerateAttribute:NSAttachmentAttributeName inRange:range options:0 usingBlock:^(NSTextAttachment *attachment, NSRange attachmentRange, BOOL *stop) {
            if (!attachment)
                return; // Only want the ranges *with* attachments...
            
#ifdef OMNI_ASSERTION_ON
            // Make sure OATextAttachment and NSTextAttachment agree about somethings...
            if ([attachment isKindOfClass:[OATextAttachment class]]) {
                NSFileWrapper *attachmentWrapper = [(OATextAttachment *)attachment fileWrapper];
                NSString *filename = [attachmentWrapper filename];
                    NSString *inferredType = (OB_BRIDGE NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (OB_BRIDGE CFStringRef)[[attachmentWrapper filename] pathExtension], NULL);
                    OBASSERT([inferredType isEqual:attachment.fileType]);
                
                if ([attachmentWrapper isRegularFile])
                    OBASSERT([attachmentWrapper.regularFileContents isEqual:attachment.contents]);
                else
                    OBASSERT(attachment.contents == nil);
            }
#endif
            
            // Given that agreement, we can simplify our archiving here since we only do flat files.
            NSData *contents = attachment.contents;
            NSString *fileType = attachment.fileType;
            if (contents && fileType)
                [items addObject:@{fileType:contents}];
            else
                NSLog(@"Not adding pasteboard item for attachment with fileType %@ and contents of %p", fileType, contents);
        }];
    }
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = items;
}

// If this pattern ends up being correct, maybe move this to UIPasteboard as a category method
static void _enumerateBestDataForTypes(UIPasteboard *pasteboard, NSArray *types, void (^applier)(NSData *))
{
    NSIndexSet *itemSet = [pasteboard itemSetWithPasteboardTypes:types];
    [itemSet enumerateIndexesUsingBlock:^(NSUInteger itemIndex, BOOL *stop) {
        for (NSString *type in types) {
            NSArray *datas = [pasteboard dataForPasteboardType:type inItemSet:[NSIndexSet indexSetWithIndex:itemIndex]];
            OBASSERT([datas count] <= 1);
            NSData *data = [datas lastObject];
            if (OFNOTNULL(data)) {
                applier(data);
                break;
            }
        }
    }];
}

- (void)paste:(nullable id)sender;
{
    BOOL preserveStyles = YES;
    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textViewShouldPreserveStylesWhenPasting:defaultValue:sender:)])
        preserveStyles = [delegate textViewShouldPreserveStylesWhenPasting:self defaultValue:preserveStyles sender:sender];
    [self _pastePreservingStyles:preserveStyles];
}

- (void)pasteTogglingPreserveStyle:(nullable id)sender;
{
    BOOL preserveStyles = NO;
    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textViewShouldPreserveStylesWhenPasting:defaultValue:sender:)])
        preserveStyles = ![delegate textViewShouldPreserveStylesWhenPasting:self defaultValue:!preserveStyles sender:sender];
    [self _pastePreservingStyles:preserveStyles];
}

- (void)pasteAsPlainText:(nullable id)sender;
{
    [self _pastePreservingStyles:NO];
}

static void _copyAttribute(NSMutableDictionary *dest, NSDictionary *src, NSString *key)
{
    id value = src[key];
    if (value)
        dest[key] = value;
    else
        [dest removeObjectForKey:key];
}

- (void)_pastePreservingStyles:(BOOL)preserveStyles;
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];

    NSAttributedString *attributedString = nil;
    id <OUITextViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textView:readTextFromItemSet:inPasteboard:)] &&
        [delegate respondsToSelector:@selector(textViewReadablePasteboardTypes:)]) {
        NSArray *types = [delegate textViewReadablePasteboardTypes:self];
        NSIndexSet *itemSet = [pasteboard itemSetWithPasteboardTypes:types];
        if ([itemSet count] > 0)
            attributedString = [delegate textView:self readTextFromItemSet:itemSet inPasteboard:pasteboard];
    }
    
    if (!attributedString) {
        // Handle our default readable types.
        NSMutableAttributedString *result = [NSMutableAttributedString new];
        _enumerateBestDataForTypes(pasteboard, _readableTypes(), ^(NSData *data){
            __autoreleasing NSError *error = nil;
            NSAttributedString *str = [[NSAttributedString alloc] initWithData:data options:@{} documentAttributes:NULL error:&error];
            if (!str)
                [error log:@"Error reading pasteboard item"];
            else {
                [result appendAttributedString:str];
            }
        });
        
        [result enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, [result length]) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
            // Text pasted from Notes will have dynamic type fonts, but we want to control our sizes in our document-based apps. Might need a setting on OUITextView for clients that *do* want dynamic type.
            if (OUIFontIsDynamicType(font)) {
                [result removeAttribute:NSFontAttributeName range:range];
            }
        }];
        
        attributedString = [result copy];
    }
    
    if (!preserveStyles) {
        // We want to revert to the typing attributes, but keep a few special attributes.
        NSMutableDictionary *attributes = [self.typingAttributesWithAllAttributes mutableCopy];
        
        NSMutableAttributedString *prunedAttributedString = [attributedString mutableCopy];
        [prunedAttributedString enumerateAttributesInRange:NSMakeRange(0, [attributedString length]) options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            _copyAttribute(attributes, attrs, NSAttachmentAttributeName);
            _copyAttribute(attributes, attrs, NSLinkAttributeName);
            
            [prunedAttributedString setAttributes:attributes range:range];
        }];
        
        attributedString = [prunedAttributedString copy];
    }
    
    if ([attributedString length] > 0) {
        NSRange range = self.selectedRange;

        if ([delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)] &&
            ![delegate textView:self shouldChangeTextInRange:range replacementText:[attributedString string]])
            return;

        [self performUndoableReplacementOnSelectedRange:attributedString];
    }
}

#pragma mark - OUIInspectorDelegate

- (NSArray *)objectsToInspectForInspector:(OUIInspector *)inspector {
    NSArray *runs = [self _configureInspector];
    return runs;
}

- (NSArray *)inspector:(OUIInspector *)inspector makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    NSMutableArray *slices = [NSMutableArray array];
    [slices addObject:[[OUITextColorAttributeInspectorSlice alloc] initWithLabel:NSLocalizedStringFromTableInBundle(@"Text color", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the text color.")
                                                                    attributeName:NSForegroundColorAttributeName]];
    [slices addObject:[[OUITextColorAttributeInspectorSlice alloc] initWithLabel:NSLocalizedStringFromTableInBundle(@"Background color", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the text color.")
                                                                    attributeName:NSBackgroundColorAttributeName]];
    [slices addObject:[[OUIFontAttributesInspectorSlice alloc] init]];
    [slices addObject:[[OUIFontSizeInspectorSlice alloc] init]];
    [slices addObject:[[OUIFontFamilyInspectorSlice alloc] init]];
    [slices addObject:[[OUIParagraphStyleInspectorSlice alloc] init]];
    
    return slices;
}
// bug:///137426 (iOS-OmniGraffle Bug: Fix Text Inspector) - This delegate method no longer exists. For details, please see bug:///137455 (iOS-OmniGraffle Unassigned: Replace uses of -[OUIInspectorDelegate inspector[will/did]Dismiss:])
- (void)inspectorDidDismiss:(OUIInspector *)inspector;
{
    self.alwaysHighlightSelectedText = NO;

    [self becomeFirstResponder];
    
    // We might be able to save some time by keeping this around, but we also want to reset the inspector to its base state if it comes up again. ALSO, this is the easiest hack to get rid of lingering OSTextSelectionStyle objects which have problematic reference behavior. ARC will fix it all, of course.
    _textInspector.delegate = nil;
    _textInspector = nil;
}

#pragma mark - Private

- (nullable NSArray *)_configureInspector;
{
    NSArray *runs = self.inspectableObjects;
    if (!runs)
        return nil;
    
    if (!_textInspector) {
        _textInspector = [[OUIInspector alloc] init];
        _textInspector.delegate = self;
        _textInspector.mainPane.title = NSLocalizedStringFromTableInBundle(@"Text Style", @"OUIInspectors", OMNI_BUNDLE, @"Inspector title");
        
        // We'll get our slices via our delegate hook (which allows subclasses to add to/remove from/rearrange our default set).
        OBASSERT([_textInspector.mainPane isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
    }
    
    return runs;
}

@end

@implementation OUITextViewSelectedTextHighlightView

- (instancetype)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;

    self.opaque = NO;

    return self;
}

- (nullable UIView *)hitTest:(CGPoint)point withEvent:(nullable UIEvent *)event;
{
    return nil;
}

- (void)drawRect:(CGRect)rect;
{
    UITextView *textView = [self containingViewOfClass:[UITextView class]];
    [self.selectionColor setFill];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    NSArray *selectionRects = [textView selectionRectsForRange:textView.selectedTextRange];
    for (UITextSelectionRect *selectionRect in selectionRects) {
        CGContextFillRect(ctx, CGRectIntegral(selectionRect.rect));
    }
}

@end

NS_ASSUME_NONNULL_END
