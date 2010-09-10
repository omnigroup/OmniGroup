// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIScalingView.h>
#import <CoreText/CoreText.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIEditableFrameDelegate.h>
#import <OmniUI/OUILoupeOverlaySubject.h>

@class NSMutableAttributedString;

@class OUEFTextPosition, OUEFTextRange, OUITextCursorOverlay, OUILoupeOverlay;
@class OUIEditableFrame, OUITextThumb;

@class CALayer, CAShapeLayer;

@interface OUIEditableFrame : OUIScalingView <UIKeyInput, UITextInputTraits, UITextInput, OUIInspectorDelegate, OUILoupeOverlaySubject>
{
@private
    /* The data model: an attributed string, a selection range. */
    /* Note that '_content' contains an additional trailing newline which we hide from people who read/write our attributedText property */
    NSMutableAttributedString *_content;
    OUEFTextRange *selection;
    NSUInteger generation;
    NSDictionary *typingAttributes;
    NSRange markedRange;
    
    /* Attributes for strings that don't specify */
    CTFontRef defaultFont;
    UIColor *textColor;
    CTParagraphStyleRef defaultParagraphStyle;
    
    /* UI settings */
    UIColor *_insertionPointSelectionColor;
    UIColor *_rangeSelectionColor;
    NSDictionary *markedTextStyle; // Supplied by UIKit.
    NSDictionary *_linkTextAttributes;
    id <OUIEditableFrameDelegate> delegate;
    CGSize layoutSize;
    UIEdgeInsets textInset;
    UIKeyboardType keyboardType;
    UITextGranularity tapSelectionGranularity;
    BOOL _autoCorrectDoubleSpaceToPeriodAtSentenceEnd;
    UITextAutocorrectionType _autocorrectionType;
    UITextAutocapitalizationType _autocapitalizationType;

    /* The cached typeset frame */
    NSAttributedString *immutableContent;
    CTFramesetterRef framesetter;
    CTFrameRef drawnFrame;
    CGSize _usedSize;
    CGPoint layoutOrigin; // The location in rendering coordinates of the origin of the text layout coordinate system
    
    // These are the regions of our view which are affected by the current selection or marked range
    CGRect selectionDirtyRect, markedTextDirtyRect;
    
    struct {
        // Our current state
        unsigned textNeedsUpdate : 1;
        unsigned solidCaret: 1;
        unsigned showingEditMenu: 1;
        
        // Cached information about our OUIEditableFrameDelegate
        unsigned delegateRespondsToLayoutChanged: 1;
        unsigned delegateRespondsToContentsChanged: 1;
        
        // Features which can be enabled or disabled
        unsigned showSelectionThumbs: 1;  // Effectively disables range selection
        unsigned showInspector: 1;        // Whether the inspector is offered
        
        //
        unsigned immutableContentHasAttributeTransforms: 1;
    } flags;
    
    // Range selection adjustment and display
    OUITextThumb *startThumb, *endThumb;
    OUITextCursorOverlay *_cursorOverlay;
    unsigned short _caretSolidity;
    NSTimer *_solidityTimer;
    OUILoupeOverlay *_loupe;
    OUIInspector *_textInspector; // TODO: This probably shouldn't live on the editor.
    
    UIMenuController *_selectionContextMenu;
    
    /* Gesture recognizers: we hold on to these so we can enable and disable them when we gain/lose first responder status */
    UIGestureRecognizer *focusRecognizer;
#define EF_NUM_ACTION_RECOGNIZERS 3
    UIGestureRecognizer *actionRecognizers[EF_NUM_ACTION_RECOGNIZERS];
    
    /* A system-provided input delegate is assigned when the system is interested in input changes. */
    id <UITextInputDelegate> inputDelegate;
    UITextInputStringTokenizer *tokenizer;
}

@property (nonatomic, readwrite, retain) UIColor *selectionColor;
@property (nonatomic, copy) NSDictionary *typingAttributes;
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic, assign) id <OUIEditableFrameDelegate> delegate;

@property (nonatomic,assign) UIEdgeInsets textInset; // In text space (so it scales up too).
@property (nonatomic) CGSize textLayoutSize; // In text space, not UIView coordinates.
@property (nonatomic, readonly) CGSize textUsedSize; // In text space. textInset is added to this.
@property (nonatomic, readonly) CGSize viewUsedSize; // Same as -textUsedSpace, but accounting for effective scale to UIView space.

@property (nonatomic, readwrite, retain) UIColor *textColor;                   /* Applied to any runs lacking kCTForegroundColorAttributeName */
@property (nonatomic, readwrite) CTFontRef defaultCTFont;                      /* Applied to any runs lacking kCTFontAttributeName */
@property (nonatomic, readwrite) CTParagraphStyleRef defaultCTParagraphStyle;  /* Applied to any runs lacking kCTParagraphStyleAttributeName */

@property (nonatomic, copy) NSDictionary *linkTextAttributes;

@property (nonatomic) BOOL autoCorrectDoubleSpaceToPeriodAtSentenceEnd;
@property (nonatomic) UITextAutocorrectionType autocorrectionType;  // defaults to UITextAutocorrectionTypeNo
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType; // defaults to UITextAutocapitalizationTypeNone

- (void)setupCustomMenuItemsForMenuController:(UIMenuController *)menuController;

- (OUEFTextRange *)rangeOfLineContainingPosition:(OUEFTextPosition *)posn;
- (UITextRange *)selectionRangeForPoint:(CGPoint)p wordSelection:(BOOL)selectWords;

/* These are the interface from the thumbs to our selection machinery */
- (void)thumbBegan:(OUITextThumb *)thumb;
- (void)thumbMoved:(OUITextThumb *)thumb targetPosition:(CGPoint)pt;
- (void)thumbEnded:(OUITextThumb *)thumb normally:(BOOL)normalEnd;

/* These are the interface from the inspectable spans */
- (id <NSObject>)attribute:(NSString *)attr inRange:(UITextRange *)r;
- (void)setValue:(id)value forAttribute:(NSString *)attr inRange:(UITextRange *)r;

- (BOOL)hasTouchesForEvent:(UIEvent *)event;
- (BOOL)hasTouchByGestureRecognizer:(UIGestureRecognizer *)recognizer;

- (NSSet *)inspectableTextSpans;    // returns set of OUEFTextSpans 
@end

