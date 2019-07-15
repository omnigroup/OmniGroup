// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
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
#import <OmniAppKit/OAFindPattern.h>
#import <OmniAppKit/OARegExFindPattern.h>
#import <OmniAppKit/OAWindowCascade.h>

RCS_ID("$Id$")

@interface OAFindController ()

@property (nonatomic, strong) IBOutlet NSTextField *searchTextField;
@property (nonatomic, strong) IBOutlet NSTextField *replaceTextField;

@property (nonatomic, strong) IBOutlet NSButton *ignoreCaseButton;
@property (nonatomic, strong) IBOutlet NSButton *wholeWordButton;
@property (nonatomic, strong) IBOutlet NSButton *findNextButton;
@property (nonatomic, strong) IBOutlet NSButton *findPreviousButton;
@property (nonatomic, strong) IBOutlet NSButton *replaceAllButton;
@property (nonatomic, strong) IBOutlet NSButton *replaceButton;
@property (nonatomic, strong) IBOutlet NSButton *replaceAndFindButton;
@property (nonatomic, strong) IBOutlet NSMatrix *findTypeMatrix;
@property (nonatomic, strong) IBOutlet NSPopUpButton *captureGroupPopUp;
@property (nonatomic, strong) IBOutlet NSButton *replaceInSelectionCheckbox;
@property (nonatomic, strong) IBOutlet NSBox *additionalControlsBox;
@property (nonatomic, strong) IBOutlet NSView *stringControlsView;
@property (nonatomic, strong) IBOutlet NSView *regularExpressionControlsView;
@property (nonatomic, strong) NSCell *regularExpressionCell;

- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
- (BOOL)findStringWithBackwardsFlag:(BOOL)backwardsFlag;
- (NSText *)enterSelectionTarget;

@end

@implementation OAFindController
{
    id <OAFindPattern> _currentPattern;
    BOOL _hasMatch; // YES if the last find operation found a match.
}

- (instancetype)init;
{
    if (!(self = [super initWithWindowNibName:@"OAFindPanel"])) {
        return nil;
    }

    _supportsRegularExpressions = YES;

    return self;
}

- (void)_updateFindTypeMatrix;
{
    NSInteger numberOfColumns = self.findTypeMatrix.numberOfColumns;
    if (self.supportsRegularExpressions) {
        if (numberOfColumns != 2) {
            [self.findTypeMatrix addColumnWithCells:[NSArray arrayWithObject:self.regularExpressionCell]];
            self.regularExpressionCell = nil;
        }
    } else {
        if (numberOfColumns == 2) {
            self.regularExpressionCell = [self.findTypeMatrix.cells objectAtIndex:1];
            [self.findTypeMatrix removeColumn:1];
            [self findTypeChanged:nil];
        }
    }
}

- (void)setSupportsRegularExpressions:(BOOL)supportsRegularExpressions;
{
    if (_supportsRegularExpressions == supportsRegularExpressions) {
        return;
    }
    _supportsRegularExpressions = supportsRegularExpressions;
    [self _updateFindTypeMatrix];
}

#pragma mark - Menu Actions

- (IBAction)showFindPanel:(id)sender;
{
    NSWindow *window = [self window]; // Load interface if needed
    OBASSERT(window);

    id target = self.target;
    if ([target respondsToSelector:@selector(supportsFindRegularExpressions)]) {
        self.supportsRegularExpressions = [target supportsFindRegularExpressions];
    }
    
    [_searchTextField setStringValue:[self restoreFindText]];
    [window setFrame:[OAWindowCascade unobscuredWindowFrameFromStartingFrame:window.frame avoidingWindows:nil] display:YES animate:YES];
    [window makeKeyAndOrderFront:NULL];
    [_searchTextField selectText:sender];
}

- (IBAction)findNext:(id)sender;
{
    (void)[self window]; // Load interface if needed
    [_findNextButton performClick:nil];
}

- (IBAction)findPrevious:(id)sender;
{
    (void)[self window]; // Load interface if needed
    [_findPreviousButton performClick:nil];
}

- (IBAction)enterSelection:(id)sender;
{
    NSString *selectionString = [self enterSelectionString];
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
    NSWindow *window = [self window]; // Load interface if needed
    [_findNextButton performClick:nil];
    [window orderOut:nil];
}

- (IBAction)replaceAll:(id)sender;
{
    id target = [self target];
    id <OAFindPattern> pattern = [self currentPatternWithBackwardsFlag:NO];
    
    if (!target || !pattern || ![target respondsToSelector:@selector(replaceAllOfPattern:)]) {
        NSBeep();
        return;
    }
    [pattern setReplacementString:[_replaceTextField stringValue]];
    
    (void)[self window]; // Load interface if needed
    if ([_replaceInSelectionCheckbox state] && [target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)])
        [target replaceAllOfPatternInCurrentSelection:pattern];
    else
        [target replaceAllOfPattern:pattern];
}

- (IBAction)replace:(id)sender;
{
    id target = [self target];
    if (!target || ![target respondsToSelector:@selector(replaceSelectionWithString:)]) {
        NSBeep();
        return;
    }

    if (!_currentPattern || !_hasMatch) {
        NSBeep();
        return;
    }

    NSString *replacement = [_replaceTextField stringValue];
    [_currentPattern setReplacementString:replacement];
    replacement = [_currentPattern replacementStringForLastFind];

    [target replaceSelectionWithString:replacement];
}

- (IBAction)replaceAndFind:(id)sender;
{
    // Clicking 'Find and Replace' w/o having previously done a find should just find the next match.
    if (_currentPattern && _hasMatch) {
        [self replace:sender];
    }
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
        nextKeyView = _captureGroupPopUp;
        break;
    }

    if (subview) {
        [_additionalControlsBox addSubview:subview];
        NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:_additionalControlsBox attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:subview attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0];
        constraint.active = YES;
    }
    [_replaceTextField setNextKeyView:nextKeyView];
}

// Updating the selection popup...

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    [self _updateCaptureGroupsPopUp];
}

- (void)_updateCaptureGroupsPopUp;
{
    NSString *subexpressionFormatString = NSLocalizedStringFromTableInBundle(@"Subexpression #%d", @"OmniAppKit", [OAFindController bundle], "Contents of popup in regular expression find options");
    
    NSRegularExpression *expression = [[NSRegularExpression alloc] initWithPattern:[_searchTextField stringValue] options:0 error:NULL];
    if (expression != nil) {
        NSUInteger captureGroupCount = [expression numberOfCaptureGroups];

        NSUInteger popupItemCount = [_captureGroupPopUp numberOfItems];
        
        while (popupItemCount > 1 + captureGroupCount)
            [_captureGroupPopUp removeItemAtIndex:--popupItemCount];
        while (popupItemCount < 1 + captureGroupCount) {
            [_captureGroupPopUp addItemWithTitle:[NSString stringWithFormat:subexpressionFormatString, popupItemCount]];
            popupItemCount++;
        }
    } else {
        [_findTypeMatrix selectCellWithTag:0];
    }
}

// Utility methods

- (void)enterSelectionWithString:(NSString *)selectionString;
{
    (void)[self window]; // Load interface if needed
    [self saveFindText:selectionString];
    [_searchTextField setStringValue:selectionString];
    [_searchTextField selectText:self];
}

- (void)saveFindText:(NSString *)string;
{
    if ([string length] == 0)
	return;
    
    @try {
	NSPasteboard *findPasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
	[findPasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
	[findPasteboard setString:string forType:NSPasteboardTypeString];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
}

- (NSString *)restoreFindText;
{
    NSString *findText = nil;
    
    @try {
	NSPasteboard *findPasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
	if ([findPasteboard availableTypeFromArray:[NSArray arrayWithObject:NSPasteboardTypeString]])
	    findText = [findPasteboard stringForType:NSPasteboardTypeString];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
    return findText ? findText : @"";
}

- (nullable id <OAFindControllerTarget>)target;
{
    NSWindow *mainWindow = [[NSApplication sharedApplication] mainWindow];
    id target = [(id)[mainWindow delegate] omniFindControllerTarget];
    if (target != nil)
        return target;
    NSResponder *firstResponder = [mainWindow firstResponder];
    NSResponder *responder = firstResponder;
    do {
        target = [responder omniFindControllerTarget];
        if (target != nil) {
            OBASSERT([target conformsToProtocol:@protocol(OAFindControllerTarget)]);
            return target;
        }
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


#pragma mark - NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(enterSelection:)) {
        return [self enterSelectionStringLength] > 0;
    }
    return YES;
}

#pragma mark - NSWindow delegate

- (void)windowDidUpdate:(NSNotification *)aNotification
{
    id target = [self target];
    
    BOOL replaceSelectionEnabled = [target respondsToSelector:@selector(replaceSelectionWithString:)];
    if (replaceSelectionEnabled && [target respondsToSelector:@selector(isSelectedTextEditable)]) 
	replaceSelectionEnabled = [target isSelectedTextEditable];

    
    [_replaceButton setEnabled:replaceSelectionEnabled];
    [_replaceAndFindButton setEnabled:replaceSelectionEnabled];
    [_replaceAllButton setEnabled:[target respondsToSelector:@selector(replaceAllOfPattern:)]];
    
    _replaceInSelectionCheckbox.hidden = ![target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)];
}

#pragma mark - NSWindowController subclass

- (void)windowDidLoad;
{
    [self findTypeChanged:self];
}

#pragma mark - Private

- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
{
    id <OAFindPattern> pattern;
    NSString *findString;

    if ([self isWindowLoaded] && [self.window isVisible]) {
        findString = [_searchTextField stringValue];
        [self saveFindText:findString];
    } else
        findString = [self restoreFindText];
        
    if (![findString length])
        return nil;

    (void)[self window]; // Load interface if needed
    if ([[_findTypeMatrix selectedCell] tag] == 0) {
        pattern = [[OAFindPattern alloc] initWithString:findString
                                             ignoreCase:([_ignoreCaseButton state] != NSControlStateValueOff)
                                              wholeWord:([_wholeWordButton state] != NSControlStateValueOff)
                                              backwards:backwardsFlag];
    } else {
        [self _updateCaptureGroupsPopUp];
        NSInteger captureGroup = [_captureGroupPopUp indexOfSelectedItem] - 1;
        pattern = [[OARegExFindPattern alloc] initWithPattern:findString selectedCaptureGroup:captureGroup backwards:backwardsFlag];
    }
    
    _currentPattern = pattern;
    _hasMatch = NO;

    return pattern;
}

// This is the real find method

- (BOOL)findStringWithBackwardsFlag:(BOOL)backwardsFlag;
{
    id <OAFindControllerTarget> target;
    id <OAFindPattern> pattern;

    pattern = [self currentPatternWithBackwardsFlag:backwardsFlag];
    if (!pattern)
        return NO;
        
    target = [self target];
    if (!target)
        return NO;

    _hasMatch = [target findPattern:pattern backwards:backwardsFlag wrap:YES];
    [_searchTextField selectText:self];
    return _hasMatch;
}

- (NSText *)enterSelectionTarget;
{
    NSWindow *selectionWindow = [[NSApplication sharedApplication] keyWindow];
    if ([self isWindowLoaded] && selectionWindow == self.window)
        selectionWindow = [[NSApplication sharedApplication] mainWindow];
    NSText *enterSelectionTarget = (id)[selectionWindow firstResponder];
    
    if ([enterSelectionTarget respondsToSelector:@selector(selectedString)])
        return enterSelectionTarget;
    if ([enterSelectionTarget respondsToSelector:@selector(string)] &&
        [enterSelectionTarget respondsToSelector:@selector(selectedRange)])
        return enterSelectionTarget;

    return nil;
}

@end

@implementation NSObject (OAFindControllerAware)

- (nullable id <OAFindControllerTarget>)omniFindControllerTarget;
{
    return nil;
}

@end
