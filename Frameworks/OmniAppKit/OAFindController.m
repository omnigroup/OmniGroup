// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
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

@interface OAFindController (Private)
- (void)loadInterface;
- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
- (BOOL)findStringWithBackwardsFlag:(BOOL)backwardsFlag;
- (NSText *)enterSelectionTarget;
@end

@implementation OAFindController

// Init and dealloc

#define WANT_INTERFACE if(findPanel == nil) [self loadInterface];

- init;
{
    if (![super init])
        return nil;

    return self;
}

- (void)dealloc;
{
    [findPanel release];
    [currentPattern release];
    [super dealloc];
}


// Menu Actions

- (IBAction)showFindPanel:(id)sender;
{
    WANT_INTERFACE;
    if (!findPanel)
        return;
    [[searchTextForm cellAtIndex:0] setStringValue:[self restoreFindText]];
    [findPanel setFrame:[OAWindowCascade unobscuredWindowFrameFromStartingFrame:[findPanel frame] avoidingWindows:nil] display:YES animate:YES];
    [findPanel makeKeyAndOrderFront:NULL];
    [searchTextForm selectTextAtIndex:0];
}

- (IBAction)findNext:(id)sender;
{
    WANT_INTERFACE;
    [findNextButton performClick:nil];
}

- (IBAction)findPrevious:(id)sender;
{
    WANT_INTERFACE;
    [findPreviousButton performClick:nil];
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
    WANT_INTERFACE;
    [findNextButton performClick:nil];
    [findPanel orderOut:nil];
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
    [pattern setReplacementString:[[replaceTextForm cellAtIndex:0] stringValue]];
    
    WANT_INTERFACE;
    if ([replaceInSelectionCheckbox state] && [target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)])
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
    
    replacement = [[replaceTextForm cellAtIndex:0] stringValue];
    if (currentPattern) {
        [currentPattern setReplacementString:replacement];
        replacement = [currentPattern replacementStringForLastFind];
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
    switch([[findTypeMatrix selectedCell] tag]) {
    case 0:
        subview = stringControlsView;
        [regularExpressionControlsView removeFromSuperview];
        nextKeyView = ignoreCaseButton;
        break;
    case 1:
        subview = regularExpressionControlsView;
        [stringControlsView removeFromSuperview];
        nextKeyView = subexpressionPopUp;
        break;
    }

    if (subview) {
        [subview setFrameOrigin:NSMakePoint(floor(([additionalControlsBox frame].size.width - [subview frame].size.width) / 2), 0)];
        [additionalControlsBox addSubview:subview];
    }
    [replaceTextForm setNextKeyView:nextKeyView];
}

// Updating the selection popup...

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    OFRegularExpression *expression;
    int subexpressionCount, numberOfItems;
    NSString *subexpressionFormatString;
    
    subexpressionFormatString = NSLocalizedStringFromTableInBundle(@"Subexpression #%d", @"OmniAppKit", [OAFindController bundle], "Contents of popup in regular expression find options");
    
    expression = [[OFRegularExpression alloc] initWithString:[[searchTextForm cellAtIndex:0] stringValue]];
    if (expression) {
        subexpressionCount = [expression subexpressionCount];
        [expression release];
        numberOfItems = [subexpressionPopUp numberOfItems] - 1;
        
        while (numberOfItems > subexpressionCount)
            [subexpressionPopUp removeItemAtIndex:numberOfItems--];
        while (subexpressionCount > numberOfItems)
            [subexpressionPopUp addItemWithTitle:[NSString stringWithFormat:subexpressionFormatString, ++numberOfItems]];
    } else {
        [findTypeMatrix selectCellWithTag:0];
    }
}

// Utility methods

- (void)enterSelectionWithString:(NSString *)selectionString;
{
    WANT_INTERFACE;
    [self saveFindText:selectionString];
    [[searchTextForm cellAtIndex:0] setStringValue:selectionString];
    [searchTextForm selectTextAtIndex:0];
}

- (void)saveFindText:(NSString *)string;
{
    NSPasteboard *findPasteboard;

    if ([string length] == 0)
	return;
    NS_DURING {
	findPasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
	[findPasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[findPasteboard setString:string forType:NSStringPboardType];
    } NS_HANDLER {
    } NS_ENDHANDLER;
}

- (NSString *)restoreFindText;
{
    NSString *findText = nil;
    
    NS_DURING {
	NSPasteboard *findPasteboard;

	findPasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
	if ([findPasteboard availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]])
	    findText = [findPasteboard stringForType:NSStringPboardType];
    } NS_HANDLER {
    } NS_ENDHANDLER;
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

- (unsigned int)enterSelectionStringLength;
{
    id enterSelectionTarget;

    enterSelectionTarget = [self enterSelectionTarget];
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

    
    [replaceButton setEnabled:replaceSelectionEnabled];
    [replaceAndFindButton setEnabled:replaceSelectionEnabled];
    [replaceAllButton setEnabled:[target respondsToSelector:@selector(replaceAllOfPattern:)]];
    
    if ([target respondsToSelector:@selector(replaceAllOfPatternInCurrentSelection:)]) {
        if ([replaceInSelectionCheckbox superview] == nil)
            [[findPanel contentView] addSubview:replaceInSelectionCheckbox];
    } else if ([replaceInSelectionCheckbox superview] != nil)
        [replaceInSelectionCheckbox removeFromSuperview];
}

@end

@implementation OAFindController (Private)

// Load our interface

- (void)loadInterface;
{
    [[OAFindController bundle] loadNibNamed:@"OAFindPanel.nib" owner:self];
    
    if ([findPanel respondsToSelector:@selector(setCollectionBehavior:)])
        [findPanel setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

    [replaceInSelectionCheckbox retain];
    [findPanel setFrameUsingName:OAFindPanelTitle];
    [findPanel setFrameAutosaveName:OAFindPanelTitle];
    [self findTypeChanged:self];
}

- (id <OAFindPattern>)currentPatternWithBackwardsFlag:(BOOL)backwardsFlag;
{
    id <OAFindPattern> pattern;
    NSString *findString;

    if (findPanel && [findPanel isVisible]) {
        findString = [[searchTextForm cellAtIndex:0] stringValue];
        [self saveFindText:findString];
    } else
        findString = [self restoreFindText];
        
    if (![findString length])
        return nil;

    WANT_INTERFACE;
    if ([[findTypeMatrix selectedCell] tag] == 0) {
        pattern = [[OAFindPattern alloc] initWithString:findString ignoreCase:[ignoreCaseButton state] wholeWord:[wholeWordButton state] backwards:backwardsFlag];
    } else {
        int subexpression;
        
        [self controlTextDidEndEditing:nil]; // make sure the subexpressionPopUp is set correctly
        subexpression = [subexpressionPopUp indexOfSelectedItem] - 1;
        pattern = [[OARegExFindPattern alloc] initWithString:findString selectedSubexpression:subexpression backwards:backwardsFlag];
    }
    
    [currentPattern release];
    currentPattern = pattern;
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
    [searchTextForm selectTextAtIndex:0];
    return result;
}

- (NSText *)enterSelectionTarget;
{
    NSWindow *selectionWindow;
    NSText *enterSelectionTarget;

    selectionWindow = [NSApp keyWindow];
    if (findPanel != nil && selectionWindow == findPanel)
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
