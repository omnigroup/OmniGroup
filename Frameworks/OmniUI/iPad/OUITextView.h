// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITextView.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIKeyCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class OUITextView, OUITextSelectionSpan;

extern const CGFloat OUIScrollContext;
extern NSString * const OUITextViewInsertionPointDidChangeNotification;

@protocol OUITextViewDelegate <UITextViewDelegate>
@optional
- (NSArray *)textViewCustomMenuItems:(OUITextView *)textView;
- (void)textViewDeleteBackwardsAtBeginning:(OUITextView *)textView;

// Both of these should be implemented if either are
- (NSArray<NSString *> *)textViewReadablePasteboardTypes:(OUITextView *)textView;

/// Gives the delegate an opportunity to pull a representation from the pasteboard. Useful in cases where the OUITextView doesn't handle a given type or the delegate would like to handle seperately. A delegate can consult the OUITextView's canReadFromPasteboardTypesInPasteboard: to determine if the textView itself can already handle the pasteboard data itself.
/// @param An OUITextView
/// @param An index set for the pasteboardTypes
/// @param The provided pasteboard
- (nullable NSAttributedString *)textView:(OUITextView *)textView readTextFromItemSet:(NSIndexSet *)itemSet inPasteboard:(UIPasteboard *)pasteboard;

- (BOOL)textViewShouldPreserveStylesWhenPasting:(OUITextView *)textView defaultValue:(BOOL)defaultValue sender:(id)sender;

// Implementors should add 'uti=data' pairs for their custom types, but only if their custom type is richer than one of the default types. OUITextView will fill out at least one of RTFD and RTF as well as a plain text value (unless the delegate already has filled them out). The representations dictionary here is for a single pasteboard item that represents all the rich text. In addition, OUITextView will add extra items for each attachment (so if you have some text with images, apps that only understand images will just get the images). This means that readers of the pasteboard need to agree that if they get an item with a "rich text with attachments" type on the pasteboard, they should ignore any extra items for the attachments.
- (void)textView:(OUITextView *)textView addPasteboardRepresentations:(NSMutableDictionary *)representations range:(NSRange)range attributedString:(NSAttributedString *)attributedString;

// Delegate support for text motion at the extreme edges of the view (when the cursor would "bump into" the edge of the view.
- (void)textViewMoveUpAtTop:(OUITextView *)textView;
- (void)textViewMoveDownAtBottom:(OUITextView *)textView;
- (void)textViewMoveRightAtEnd:(OUITextView *)textView;
- (void)textViewMoveLeftAtBeginning:(OUITextView *)textView;

- (void)textView:(OUITextView *)textView didChangeAttributesInRange:(UITextRange*)range;

@end

@interface OUITextView : UITextView <OUIInspectorDelegate, OUIKeyCommandProvider, UITextDragDelegate>

+ (OUITextView *)activeFirstResponderTextView;

@property(nullable,nonatomic,weak) id <OUITextViewDelegate> delegate;

// UITextView currently has top/bottom padding that we cannot turn off/change
+ (CGFloat)oui_defaultTopAndBottomPadding;

@property (nonatomic, copy) NSString *placeholder;

@property (nonatomic) BOOL isResigningFirstResponder;

@property (nonatomic) IBInspectable BOOL shouldAutomaticallyUpdateColorsForCurrentTheme;
@property(nonatomic) BOOL keepContextualMenuHidden;

- (BOOL)canReadFromPasteboardTypesInPasteboard:(UIPasteboard *)pasteboard;

// This only applies to a plain -paste:.
- (BOOL)shouldPreserveStylesWhenPastingWithSender:(id)sender;

- (NSDictionary *)typingAttributesWithAllAttributes; // allow subclasses to ensure that the typing attributes contain the extra attributes which are sometimes stripped out by the runtime.
- (void)ensureLayout;

- (nullable UITextRange *)selectionRangeForPoint:(CGPoint)pt granularity:(UITextGranularity)granularity;
- (void)selectForInitialTapAtPoint:(CGPoint)pt;

- (CGRect)boundsOfRange:(UITextRange *)range;
- (NSRange)characterRangeForTextRange:(UITextRange *)textRange;
- (UITextRange *)textRangeForCharacterRange:(NSRange)characterRange;

- (void)scrollTextSelectionToVisibleWithAnimation:(BOOL)animated;

- (NSArray *)inspectableObjects; // Full list of inspectable objects; defaults to -inspectableTextSpans
- (NSArray *)inspectableTextSpans; // Array of OUITextSelectionSpans
- (nullable OUITextSelectionSpan *)firstNonEmptyInspectableTextSpan; // Nil if there is no selection or the selection length is zero.
- (BOOL)isEmptyInspectableTextSpans:(NSArray *)spans;

- (OUIInspector *)textInspector;
- (void)dismissInspectorImmediatelyIfVisible;
- (void)inspectSelectedTextWithViewController:(UIViewController *)viewController fromBarButtonItem:(UIBarButtonItem *)barButtonItem withSetupBlock:(void (^ _Nullable)(OUIInspector *))setupBlock NS_EXTENSION_UNAVAILABLE_IOS("");

- (void)selectAllShowingMenu:(BOOL)show;
- (void)setSelectedTextRange:(nullable UITextRange *)newRange showingMenu:(BOOL)show;

- (NSDictionary *)attributesInRange:(UITextRange *)range;
- (id <NSObject>)attribute:(NSString *)attr inRange:(UITextRange *)range;
- (void)setValue:(id)value forAttribute:(NSString *)attr inRange:(UITextRange *)range;

- (void)insertAfterSelection:(NSAttributedString *)attributedString;
@property(nonatomic,readonly) NSRange selectedRangeIncludingSurroundingWhitespace;

- (BOOL)hasTouch:(UITouch *)touch;
- (BOOL)hasTouchByGestureRecognizer:(UIGestureRecognizer *)recognizer;

- (void)performUndoableEditOnSelectedRange:(void (^)(NSMutableAttributedString *))action;
- (void)performUndoableEditOnRange:(NSRange)range action:(void (^)(NSMutableAttributedString *))action;
- (void)performUndoableEditOnRange:(NSRange)range selectInsertionPointOnUndoRedo:(BOOL)selectInsertionPointOnUndoRedo action:(void (^)(NSMutableAttributedString *))action;
- (void)performUndoableEditToStylesInSelectedRange:(void (^)(NSTextStorage *textStorage))action;
- (void)performUndoableReplacementOnSelectedRange:(NSAttributedString *)replacement;

@property (nonatomic, assign) BOOL alwaysHighlightSelectedText;

@end

NS_ASSUME_NONNULL_END
