// Copyright 1997-2005, 2007, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAFindController.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import "OAFindPattern.h"
#import "OARegExFindPattern.h"
#import "OAWindowCascade.h"

RCS_ID("$Id$")

// Used for panel frame (auto)save
static NSString *OAFindPanelTitle = @"Find";

@interface OAFindController ()

@property (nonatomic, retain) IBOutlet NSWindow *findPanel;
@property (nonatomic, retain) IBOutlet NSForm *searchTextForm;
@property (nonatomic, retain) IBOutlet NSForm *replaceTextForm;
@property (nonatomic, retain) IBOutlet NSButton *ignoreCaseButton;
@property (nonatomic, retain) IBOutlet NSButton *wholeWordButton;
@property (nonatomic, retain) IBOutlet NSButton *findNextButton;
@property (nonatomic, retain) IBOutlet NSButton *findPreviousButton;
@property (nonatomic, retain) IBOutlet NSButton *replaceAllButton;
@property (nonatomic, retain) IBOutlet NSButton *replaceButton;
@property (nonatomic, retain) IBOutlet NSButton *replaceAndFindButton;
@property (nonatomic, retain) IBOutlet NSMatrix *findTypeMatrix;
@property (nonatomic, retain) IBOutlet NSPopUpButton *subexpressionPopUp;
@property (nonatomic, retain) IBOutlet NSButton *replaceInSelectionCheckbox;
@property (nonatomic, retain) IBOutlet NSBox *additionalControlsBox;
@property (nonatomic, retain) IBOutlet NSView *stringControlsView;
@property (nonatomic, retain) IBOutlet NSView *regularExpressionControlsView;

- (void)loadInterface;
- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
- (BOOL)findStringWithBackwardsFlag:(BOOL)backwardsFlag;
- (NSText *)enterSelectionTarget;

@end

@implementation OAFindController

// Init and dealloc

static inline void _LoadInterfaceIfNecessary(OAFindController *self)
{
    if (!self->_findPanel)
        [self loadInterface];   
}

- (void)dealloc;
{
    [_findPanel release];
    [_searchTextForm release];
    [_replaceTextForm release];
    [_ignoreCaseButton release];
    [_wholeWordButton release];
    [_findNextButton release];
    [_findPreviousButton release];
    [_replaceAllButton release];
    [_replaceButton release];
    [_replaceAndFindButton release];
    [_findTypeMatrix release];
    [_subexpressionPopUp release];
    [_replaceInSelectionCheckbox release];
    [_additionalControlsBox release];
    [_stringControlsView release];
    [_regularExpressionControlsView release];

    [_currentPattern release];

    [super dealloc];
}

// Outlets

@synthesize findPanel = _findPanel;
@synthesize searchTextForm = _searchTextForm;
@synthesize replaceTextForm = _replaceTextForm;
@synthesize ignoreCaseButton = _ignoreCaseButton;
@synthesize wholeWordButton = _wholeWordButton;
@synthesize findNextButton = _findNextButton;
@synthesize findPreviousButton = _findPreviousButton;
@synthesize replaceAllButton = _replaceAllButton;
@synthesize replaceButton = _replaceButton;
@synthesize replaceAndFindButton = _replaceAndFindButton;
@synthesize findTypeMatrix = _findTypeMatrix;
@synthesize subexpressionPopUp = _subexpressionPopUp;
@synthesize replaceInSelectionCheckbox = _replaceInSelectionCheckbox;
@synthesize additionalControlsBox = _additionalControlsBox;
@synthesize stringControlsView = _stringControlsView;
@synthesize regularExpressionControlsView = _regularExpressionControlsView;

// Menu Actions

- (IBAction)showFindPanel:(id)sender;
{
    _LoadInterfaceIfNecessary(self);
    if (!_findPanel)
        return;
    [[_searchTextForm cellAtIndex:0] setStringValue:[self restoreFindText]];
    [_findPanel setFrame:[OAWindowCascade unobscuredWindowFrameFromStartingFrame:[_findPanel frame] avoidingWindows:nil] display:YES animate:YES];
    [_findPanel makeKeyAndOrderFront:NULL];
    [_searchTextForm selectTextAtIndex:0];
}

- (IBAction)findNext:(id)sender;
{
    _LoadInterfaceIfNecessary(self);
    [_findNextButton performClick:nil];
}

- (IBAction)findPrevious:(id)sender;
{
    _LoadInterfaceIfNecessary(self);
    [_findPreviousButton performClick:nil];
}

- (IBAction)enterSelection:(id)sender;
{
    NSString *selectionString;

    selectionString = [self enterSelectionString];
    if (!selectionString)
        return;
    [self enterSelectionWithString:selectionString];
}

- (IBAction)panelFindNext:(id)sender;
{
    if (![self findStringWithBackwardsFlag:NO])
        NSBeep();
}

- (IBAction)panelFindPrevious:(id)sender;
{
    if (![self findStringWithBackwardsFlag:YES])
        NSBeep();
}

- (IBAction)panelFindNextAndClosePanel:(id)sender;
{
    _LoadInterfaceIfNecessary(self);
    [_findNextButton performClick:nil];
    [_findPanel orderOut:nil];
}

- (IBAction)replaceAll:(id)sender;
{
    id <OAFindPattern> pattern;
    id target;
    
    target = [self target];
    pattern = [self currentPatternWithBackwardsFlag:NO];
    
    if (!target || !pattern || ![target respondsToSelector:@selector(replaceAllOfPattern:)]) {
        NSBeep();
        return;
    }
    [pattern setReplacementString:[[_replaceTextForm cellAtIndex:0] stringValue]];
    
    _LoadInterfaceIfNecessary(self);
    if ([_replaceInSelectionCheckbox state] && [target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)])
        [target replaceAllOfPatternInCurrentSelection:pattern];
    else
        [target replaceAllOfPattern:pattern];
}

- (IBAction)replace:(id)sender;
{
    id target;
    NSString *replacement;
    
    target = [self target];
    if (!target || ![target respondsToSelector:@selector(replaceSelectionWithString:)]) {
        NSBeep();
        return;
    }
    
    replacement = [[_replaceTextForm cellAtIndex:0] stringValue];
    if (_currentPattern) {
        [_currentPattern setReplacementString:replacement];
        replacement = [_currentPattern replacementStringForLastFind];
    }

    [target replaceSelectionWithString:replacement];
}

- (IBAction)replaceAndFind:(id)sender;
{
    [self replace:sender];
    [self panelFindNext:sender];
}

- (IBAction)findTypeChanged:(id)sender;
{
    NSView *subview = nil;
    NSView *nextKeyView = nil;
    
    // add the new controls
    switch([[_findTypeMatrix selectedCell] tag]) {
    case 0:
        subview = _stringControlsView;
        [_regularExpressionControlsView removeFromSuperview];
        nextKeyView = _ignoreCaseButton;
        break;
    case 1:
        subview = _regularExpressionControlsView;
        [_stringControlsView removeFromSuperview];
        nextKeyView = _subexpressionPopUp;
        break;
    }

    if (subview) {
        [subview setFrameOrigin:NSMakePoint((CGFloat)floor(([_additionalControlsBox frame].size.width - [subview frame].size.width) / 2), 0)];
        [_additionalControlsBox addSubview:subview];
    }
    [_replaceTextForm setNextKeyView:nextKeyView];
}

// Updating the selection popup...

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    NSString *subexpressionFormatString = NSLocalizedStringFromTableInBundle(@"Subexpression #%d", @"OmniAppKit", [OAFindController bundle], "Contents of popup in regular expression find options");
    
    OFRegularExpression *expression = [[OFRegularExpression alloc] initWithString:[[_searchTextForm cellAtIndex:0] stringValue]];
    if (expression != nil) {
        unsigned int subexpressionCount = [expression subexpressionCount];
        [expression release];
        
        NSUInteger popupItemCount = [_subexpressionPopUp numberOfItems];
        
        while (popupItemCount > 1 + subexpressionCount)
            [_subexpressionPopUp removeItemAtIndex:--popupItemCount];
        while (popupItemCount < 1 + subexpressionCount)
            [_subexpressionPopUp addItemWithTitle:[NSString stringWithFormat:subexpressionFormatString, ++popupItemCount]];
    } else {
        [_findTypeMatrix selectCellWithTag:0];
    }
}

// Utility methods

- (void)enterSelectionWithString:(NSString *)selectionString;
{
    _LoadInterfaceIfNecessary(self);
    [self saveFindText:selectionString];
    [[_searchTextForm cellAtIndex:0] setStringValue:selectionString];
    [_searchTextForm selectTextAtIndex:0];
}

- (void)saveFindText:(NSString *)string;
{
    if ([string length] == 0)
	return;
    
    @try {
	NSPasteboard *findPasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
	[findPasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[findPasteboard setString:string forType:NSStringPboardType];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
}

- (NSString *)restoreFindText;
{
    NSString *findText = nil;
    
    @try {
	NSPasteboard *findPasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
	if ([findPasteboard availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]])
	    findText = [findPasteboard stringForType:NSStringPboardType];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
    return findText ? findText : @"";
}

- (id <OAFindControllerTarget>)target;
{
    NSWindow *mainWindow = [NSApp mainWindow];
    id target = [(id)[mainWindow delegate] omniFindControllerTarget];
    if (target != nil)
        return target;
    NSResponder *firstResponder = [mainWindow firstResponder];
    NSResponder *responder = firstResponder;
    do {
        target = [responder omniFindControllerTarget];
        if (target != nil)
            return target;
        responder = [responder nextResponder];
    } while (responder != nil && responder != firstResponder);
    return nil;
}

- (NSString *)enterSelectionString;
{
    id enterSelectionTarget;

    enterSelectionTarget = [self enterSelectionTarget];
    if (!enterSelectionTarget)
        return nil;

    if ([enterSelectionTarget respondsToSelector:@selector(selectedString)])
        return [enterSelectionTarget selectedString];
    else {
        NSRange selectedRange;

        selectedRange = [enterSelectionTarget selectedRange];
        if (selectedRange.length == 0)
            return @"";
        else
            return [[enterSelectionTarget string] substringWithRange:selectedRange];
    }
}

- (NSUInteger)enterSelectionStringLength;
{
    id enterSelectionTarget = [self enterSelectionTarget];
    if (!enterSelectionTarget)
        return 0;

    if ([enterSelectionTarget respondsToSelector:@selector(selectedString)])
        return [[enterSelectionTarget selectedString] length];
    else
        return [enterSelectionTarget selectedRange].length;
}


// NSMenuActionResponder informal protocol

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(enterSelection:)) {
        return [self enterSelectionStringLength] > 0;
    }
    return YES;
}

// NSWindow delegation

- (void)windowDidUpdate:(NSNotification *)aNotification
{
    id target = [self target];
    
    BOOL replaceSelectionEnabled = [target respondsToSelector:@selector(replaceSelectionWithString:)];
    if (replaceSelectionEnabled && [target respondsToSelector:@selector(isSelectedTextEditable)]) 
	replaceSelectionEnabled = [target isSelectedTextEditable];

    
    [_replaceButton setEnabled:replaceSelectionEnabled];
    [_replaceAndFindButton setEnabled:replaceSelectionEnabled];
    [_replaceAllButton setEnabled:[target respondsToSelector:@selector(replaceAllOfPattern:)]];
    
    if ([target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)]) {
        if ([_replaceInSelectionCheckbox superview] == nil)
            [[_findPanel contentView] addSubview:_replaceInSelectionCheckbox];
    } else if ([_replaceInSelectionCheckbox superview] != nil)
        [_replaceInSelectionCheckbox removeFromSuperview];
}

#pragma mark Private

// Load our interface

- (void)loadInterface;
{
    [[OAFindController bundle] loadNibNamed:@"OAFindPanel.nib" owner:self options:nil];
    
    if ([_findPanel respondsToSelector:@selector(setCollectionBehavior:)])
        [_findPanel setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

    [_findPanel setFrameUsingName:OAFindPanelTitle];
    [_findPanel setFrameAutosaveName:OAFindPanelTitle];
    [self findTypeChanged:self];
}

- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
{
    id <OAFindPattern> pattern;
    NSString *findString;

    if (_findPanel && [_findPanel isVisible]) {
        findString = [[_searchTextForm cellAtIndex:0] stringValue];
        [self saveFindText:findString];
    } else
        findString = [self restoreFindText];
        
    if (![findString length])
        return nil;

    _LoadInterfaceIfNecessary(self);
    if ([[_findTypeMatrix selectedCell] tag] == 0) {
        pattern = [[OAFindPattern alloc] initWithString:findString ignoreCase:[_ignoreCaseButton state] wholeWord:[_wholeWordButton state] backwards:backwardsFlag];
    } else {
        [self controlTextDidEndEditing:nil]; // make sure the _subexpressionPopUp is set correctly
        NSInteger subexpression = [_subexpressionPopUp indexOfSelectedItem] - 1;
        pattern = [[OARegExFindPattern alloc] initWithString:findString selectedSubexpression:subexpression backwards:backwardsFlag];
    }
    
    [_currentPattern release];
    _currentPattern = pattern;
    return pattern;
}

// This is the real find method

- (BOOL)findStringWithBackwardsFlag:(BOOL)backwardsFlag;
{
    id <OAFindControllerTarget> target;
    id <OAFindPattern> pattern;
    BOOL result;

    pattern = [self currentPatternWithBackwardsFlag:backwardsFlag];
    if (!pattern)
        return NO;
        
    target = [self target];
    if (!target)
        return NO;

    result = [target findPattern:pattern backwards:backwardsFlag wrap:YES];
    [_searchTextForm selectTextAtIndex:0];
    return result;
}

- (NSText *)enterSelectionTarget;
{
    NSWindow *selectionWindow;
    NSText *enterSelectionTarget;

    selectionWindow = [NSApp keyWindow];
    if (_findPanel != nil && selectionWindow == _findPanel)
        selectionWindow = [NSApp mainWindow];
    enterSelectionTarget = (id)[selectionWindow firstResponder];
    
    if ([enterSelectionTarget respondsToSelector:@selector(selectedString)])
        return enterSelectionTarget;
    if ([enterSelectionTarget respondsToSelector:@selector(string)] &&
        [enterSelectionTarget respondsToSelector:@selector(selectedRange)])
        return enterSelectionTarget;

    return nil;
}

@end

@implementation NSObject (OAFindControllerAware)

- (id <OAFindControllerTarget>)omniFindControllerTarget;
{
    return nil;
}

@end

@implementation NSObject (OAOptionalSearchableCellProtocol)

- (id <OASearchableContent>)searchableContentView;
{
    return nil;
}

@end
