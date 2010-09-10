// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIFontInspectorSlice.h"

#import "OUIInspector.h"
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIInspectorStepperButton.h>

#import <CoreText/CTFont.h>
#import <UIKit/UIKit.h>

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OUIFontInspectorSlice (/*Private*/)
- (IBAction)_showFontFamilies:(id)sender;
- (IBAction)_showFontFaces:(id)sender;
@end

@implementation OUIFontInspectorSlice

typedef struct {
    NSSet *fontDescriptors;
    NSSet *fontSizes;
    CGFloat minFontSize, maxFontSize;
} FontSelection;

static FontSelection _collectSelection(OUIInspectorSlice *self, NSSet *objects)
{
    OBPRECONDITION(self);
    
    NSMutableSet *fontDescriptors = [NSMutableSet set];
    NSMutableSet *fontSizes = [NSMutableSet set];
    CGFloat minFontSize = 0, maxFontSize = 0;
    
    for (id <OUIFontInspection> object in objects) {
        OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
        OBASSERT(fontDescriptor);
        if (fontDescriptor)
            [fontDescriptors addObject:fontDescriptor];
        
        CGFloat fontSize = [object fontSizeForInspectorSlice:self];
        OBASSERT(fontSize > 0);
        if (fontSize > 0) {
            if (![fontSizes count]) {
                minFontSize = maxFontSize = fontSize;
            } else {
                if (minFontSize > fontSize) minFontSize = fontSize;
                if (maxFontSize < fontSize) maxFontSize = fontSize;
            }
            [fontSizes addObject:[NSNumber numberWithFloat:fontSize]];
        }
    }
    
    return (FontSelection){
        .fontDescriptors = fontDescriptors,
        .fontSizes = fontSizes,
        .minFontSize = minFontSize,
        .maxFontSize = maxFontSize
    };
}

// CTFontCreateWithName can end up loading the font off disk, and if this is the only reference, it can do it each time we call this (like when we are reloading in the font family table).
// Cache the display name for each font to avoid this.
static NSString *_displayNameForFont(UIFont *font, BOOL useFamilyName)
{
    if (!font)
        return @"???";
    
    static NSMutableDictionary *fontNameToDisplayName = nil;
    static NSMutableDictionary *familyNameToDisplayName = nil;
    
    if (!fontNameToDisplayName) {
        fontNameToDisplayName = [[NSMutableDictionary alloc] init];
        familyNameToDisplayName = [[NSMutableDictionary alloc] init];
    }

    NSString *fontName = font.fontName;
    NSString *cachedDisplayName = (useFamilyName) ? [familyNameToDisplayName objectForKey:font.familyName] : [fontNameToDisplayName objectForKey:font.fontName];
    if (cachedDisplayName)
        return cachedDisplayName;
    
    CTFontRef fontRef = CTFontCreateWithName((CFStringRef)fontName, 12.0, NULL);
    if (!fontRef) {
        NSLog(@"No base font ref for %@", font);
        return @"???";
    }
    
    CFStringRef displayName = nil;
    
    if (useFamilyName) 
        displayName = CTFontCopyLocalizedName(fontRef, kCTFontFamilyNameKey, NULL);
    else
        displayName = CTFontCopyDisplayName(fontRef);
    
    CFRelease(fontRef);
    
    OBASSERT(displayName);
    if (!displayName)
        displayName = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)font.familyName);
    
    cachedDisplayName = [NSMakeCollectable(displayName) autorelease];
    if (useFamilyName)
        [fontNameToDisplayName setObject:cachedDisplayName forKey:font.familyName];
    else
        [familyNameToDisplayName setObject:cachedDisplayName forKey:fontName];
    
    return cachedDisplayName;
}

static NSString *_displayNameForFontFaceName(NSString *displayName, NSString *baseDisplayName, BOOL *outIsBase)
{
    if ([displayName isEqualToString:baseDisplayName]) {
        if (outIsBase)
            *outIsBase = YES;
        return NSLocalizedStringFromTableInBundle(@"Regular", @"OUIInspectors", OMNI_BUNDLE, @"Name for the variant of a font with out any special attributes");
    }
    
    if (outIsBase)
        *outIsBase = NO;

    NSMutableString *trimmed = [[displayName mutableCopy] autorelease];
    [trimmed replaceOccurrencesOfString:baseDisplayName withString:@"" options:0 range:NSMakeRange(0, [trimmed length])];
    [trimmed replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, [trimmed length])]; // In case it was in the middle
    [trimmed replaceOccurrencesOfString:@" " withString:@"" options:NSAnchoredSearch range:NSMakeRange(0, [trimmed length])]; // In case it was at the beginning
    [trimmed replaceOccurrencesOfString:@" " withString:@"" options:NSAnchoredSearch|NSBackwardsSearch range:NSMakeRange(0, [trimmed length])]; // In case it was at the end
    return trimmed;
}

- (void)dealloc;
{
    [_fontFamilyTextWell release];
    [_fontFaceTextWell release];
    [_fontSizeDecreaseStepperButton release];
    [_fontSizeIncreaseStepperButton release];
    [_fontSizeTextWell release];
    [super dealloc];
}

@synthesize fontFamilyTextWell = _fontFamilyTextWell;
@synthesize fontFaceTextWell = _fontFaceTextWell;
@synthesize fontSizeDecreaseStepperButton = _fontSizeDecreaseStepperButton;
@synthesize fontSizeIncreaseStepperButton = _fontSizeIncreaseStepperButton;
@synthesize fontSizeTextWell = _fontSizeTextWell;

static const CGFloat kMinimiumFontSize = 2;

static void _setFontSize(OUIFontInspectorSlice *self, CGFloat fontSize, BOOL relative)
{
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
            if (fontDescriptor) {
                CGFloat newSize = relative? ( [fontDescriptor size] + fontSize ) : fontSize;
                if (newSize < kMinimiumFontSize)
                    newSize = kMinimiumFontSize;
                fontDescriptor = [fontDescriptor newFontDescriptorWithSize:newSize];
            } else {
                UIFont *font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
                CGFloat newSize = relative? ( font.pointSize + fontSize ) : fontSize;
                if (newSize < kMinimiumFontSize)
                    newSize = kMinimiumFontSize;
                fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:newSize];
            }
            [object setFontDescriptor:fontDescriptor fromInspectorSlice:self];
            [fontDescriptor release];
        }
    }
    [inspector didEndChangingInspectedObjects];
    
    // Update the interface
    [self updateInterfaceFromInspectedObjects];
}

- (IBAction)increaseFontSize:(id)sender;
{
    [_fontSizeTextWell endEditing:YES/*force*/];
    _setFontSize(self, 1, YES /* relative */);
}

- (IBAction)decreaseFontSize:(id)sender;
{
    [_fontSizeTextWell endEditing:YES/*force*/];
    _setFontSize(self, -1, YES /* relative */);
}

- (IBAction)fontSizeTextWellAction:(OUIInspectorTextWell *)sender;
{
    _setFontSize(self, [[sender text] floatValue], NO /* not relative */);
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    FontSelection selection = _collectSelection(self, self.appropriateObjectsForInspection);
        
    CGFloat fontSize = [OUIInspectorTextWell fontSize];

    switch ([selection.fontDescriptors count]) {
        case 0:
            _fontFamilyTextWell.text = NSLocalizedStringFromTableInBundle(@"No Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for no selected objects");
            _fontFamilyTextWell.font = [UIFont systemFontOfSize:fontSize];
            _fontFaceTextWell.text = @"";
            break;
        case 1: {
            OAFontDescriptor *fontDescriptor = [selection.fontDescriptors anyObject];
            CTFontRef font = [fontDescriptor font];
            OBASSERT(font);
            
            if (font) {
                CFStringRef familyName = CTFontCopyFamilyName(font);
                OBASSERT(familyName);
                CFStringRef postscriptName = CTFontCopyPostScriptName(font);
                OBASSERT(postscriptName);
                CFStringRef displayName = CTFontCopyDisplayName(font);
                OBASSERT(displayName);
                
                _fontFamilyTextWell.text = (id)familyName;
                _fontFamilyTextWell.font = familyName ? [UIFont fontWithName:(id)familyName size:fontSize] : [UIFont systemFontOfSize:fontSize];
                
                _fontFaceTextWell.text = _displayNameForFontFaceName((id)displayName, (id)familyName, NULL);
                _fontFaceTextWell.font = postscriptName ? [UIFont fontWithName:(id)postscriptName size:fontSize] : [UIFont systemFontOfSize:fontSize];
                
                if (familyName)
                    CFRelease(familyName);
                if (postscriptName)
                    CFRelease(postscriptName);
                if (displayName)
                    CFRelease(displayName);
            }
            break;
        default:
            _fontFamilyTextWell.text = NSLocalizedStringFromTableInBundle(@"Multiple Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for mulitple selection");
            _fontFamilyTextWell.font = [UIFont systemFontOfSize:fontSize];
            _fontFaceTextWell.text = @"";
            break;
        }
    }
    
    switch ([selection.fontDescriptors count]) {
        case 0:
            _fontSizeTextWell.text = nil;
            // leave value where ever it was
            // disable controls? 
            OBASSERT_NOT_REACHED("why are we even visible?");
            break;
        case 1:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d", (int)rint(selection.minFontSize)];
            break;
        default:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d\u2013%d", (int)floor(selection.minFontSize), (int)ceil(selection.maxFontSize)]; /* Two numbers, en-dash */
            break;
    }
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    _fontFamilyTextWell.rounded = YES;
    _fontFaceTextWell.rounded = YES;
    
    [_fontFamilyTextWell setNavigationTarget:self action:@selector(_showFontFamilies:)];
    [_fontFaceTextWell setNavigationTarget:self action:@selector(_showFontFaces:)];
    
    _fontSizeDecreaseStepperButton.title = @"A";
    _fontSizeDecreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:14];
    _fontSizeDecreaseStepperButton.titleColor = [UIColor whiteColor];
    _fontSizeDecreaseStepperButton.flipped = YES;

    _fontSizeIncreaseStepperButton.title = @"A";
    _fontSizeIncreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:32];
    _fontSizeIncreaseStepperButton.titleColor = [UIColor whiteColor];

    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    _fontSizeTextWell.font = [UIFont boldSystemFontOfSize:fontSize];
    _fontSizeTextWell.formatString = NSLocalizedStringFromTableInBundle(@"%@ points", @"OUIInspectors", OMNI_BUNDLE, @"font size label format string in points");
    _fontSizeTextWell.formatFont = [UIFont systemFontOfSize:fontSize];
    _fontSizeTextWell.editable = YES;
    [_fontSizeTextWell setKeyboardType:UIKeyboardTypeNumberPad];
}

#pragma mark -
#pragma mark Private

- (IBAction)_showFontFamilies:(id)sender;
{
    OUIFontInspectorDetailSlice *details = (OUIFontInspectorDetailSlice *)self.detailSlice;
    details.title = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    details.showFamilies = YES;
    [self showDetails:sender];
}

- (IBAction)_showFontFaces:(id)sender;
{
    OUIFontInspectorDetailSlice *details = (OUIFontInspectorDetailSlice *)self.detailSlice;
    details.title = NSLocalizedStringFromTableInBundle(@"Typeface", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font typeface list in the inspector");
    details.showFamilies = NO;
    [self showDetails:sender];
}

@end

@implementation OUIFontInspectorDetailSlice

static UIFont *_baseFontForFamily(NSString *family)
{
    // This list of font names is in no particular order and there no good name-based way to determine which is the most normal.
    NSArray *fontNames = [UIFont fontNamesForFamilyName:family];
    
    unsigned flagCountForMostNormalFont = UINT_MAX;
    NSString *mostNormalFontName = nil;
    
    CGFloat size = [UIFont labelFontSize];
    for (NSString *fontName in fontNames) {
        CTFontRef font = CTFontCreateWithName((CFStringRef)fontName, size, NULL/*matrix*/);
        if (!font) {
            OBASSERT_NOT_REACHED("But you gave me the font name!");
            continue;
        }
        
        CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(font);
        CFRelease(font);
        
        //traits &= kCTFontClassMaskTrait; // Only count the base traits like bold/italic, not sans serif.
        traits &= 0xffff; // The documentation says the bottom 16 bits are for the symbolic bits.  kCTFontClassMaskTrait is a single bit shifted up, not a mask for the bottom 16 bits.
        
        unsigned flagCount = 0;
        while (traits) {
            if (traits & 0x1)
                flagCount++;
            traits >>= 1;
        }
        
        if (flagCountForMostNormalFont > flagCount) {
            flagCountForMostNormalFont = flagCount;
            mostNormalFontName = fontName;
        }
    }
    
    if (mostNormalFontName)
        return [UIFont fontWithName:mostNormalFontName size:size];
    
    return nil; // use the default font, I guess
}

+ (NSSet *)recommendedFontFamilyNames;
{
    static NSSet *names = nil;
    if (!names)
        // Lucida Grande isn't available on the device right now, but add it to the preferred list in case it ever shows up.
        names = [[NSSet alloc] initWithObjects:@"Didot", @"Futura", @"Georgia", @"Gill Sans", @"Helvetica Neue", @"Hoefler Text", @"Lucida Grande", @"Optima", @"Palatino", nil];
    return names;
}

- (void)dealloc;
{
    [_sections release];
    [_fonts release];
    [_fontNames release];
    [_selectedFonts release];
    [super dealloc];
}

@synthesize showFamilies = _showFamilies;
- (void)setShowFamilies:(BOOL)flag;
{
    if (_showFamilies ^ flag) {
        _showFamilies = flag;
        [self updateInterfaceFromInspectedObjects];
    }
}

#pragma mark -
#pragma mark OUIDetailInspectorSlice subclass

static NSString * const SectionItems = @"items";

static NSString * const ItemDisplayName = @"displayName"; // NSString
static NSString * const ItemFont = @"font"; // UIFont
static NSString * const ItemSelected = @"selected"; // NSNumber<BOOL>
static NSString * const ItemIsBase = @"isBase"; // NSNumber<BOOL>
static NSString * const ItemIdentifier = @"identifier"; // reuse identifier

static NSMutableDictionary *_itemForFont(UIFont *font, BOOL selected, BOOL isFaceName)
{
    NSString *displayName = _displayNameForFont(font, !isFaceName);
    
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    [item setObject:displayName forKey:ItemDisplayName];
    [item setObject:font forKey:ItemFont];
    [item setObject:selected ? (id)kCFBooleanTrue : (id)kCFBooleanFalse forKey:ItemSelected];
    
    // Provide enough info in the identifier to be a suitable table view reuse identifier. In particular we need a flag for whether we are just displaying the face name. Otherwise, we can get a cached "Georgia" (from when we picked a font family) when we really should get "Regular" while looking at the face list.
    [item setObject:[NSString stringWithFormat:@"%@ -- %@ face:%d", font.fontName, displayName, isFaceName] forKey:ItemIdentifier];
    
    return item;
}

static NSComparisonResult _compareDisplayName(id obj1, id obj2, void *context)
{
    return [[obj1 objectForKey:ItemDisplayName] localizedCaseInsensitiveCompare:[obj2 objectForKey:ItemDisplayName]];
}
static NSComparisonResult _compareItem(id obj1, id obj2, void *context)
{
    // The base face should be first
    BOOL base1 = [[obj1 objectForKey:ItemIsBase] boolValue];
    BOOL base2 = [[obj2 objectForKey:ItemIsBase] boolValue];
    
    if (base1 ^ base2) {
        if (base1)
            return NSOrderedAscending;
        return NSOrderedDescending;
    }
    
    return _compareDisplayName(obj1, obj2, context);
}

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    FontSelection selection = _collectSelection(self.slice, self.slice.appropriateObjectsForInspection);

    if (_showFamilies) {
        /*
         Two sections, Recommended Fonts and All Fonts, listing just the base font from each family.
         */
        NSSet *recommendedFontFamilyNames = [[self class] recommendedFontFamilyNames];
        NSMutableArray *recommendedItems = [NSMutableArray array];
        NSMutableArray *allItems = [NSMutableArray array];
        
        NSSet *selectedFamilyNames = [selection.fontDescriptors setByPerformingSelector:@selector(family)];

        for (NSString *family in [UIFont familyNames]) {
            UIFont *baseFont = _baseFontForFamily(family);
            if (!baseFont) {
                NSLog(@"No base font for %@", family);
                continue;
            }
            
            NSDictionary *item = _itemForFont(baseFont, ([selectedFamilyNames member:family] != nil), NO/*isFaceName*/);
            if (!item)
                continue;
            
            [allItems addObject:item];
            if ([recommendedFontFamilyNames member:family])
                [recommendedItems addObject:item];
        }
        
        [recommendedItems sortUsingFunction:_compareItem context:NULL];
        [allItems sortUsingFunction:_compareItem context:NULL];
        
        NSMutableArray *sections = [NSMutableArray array];
        [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             NSLocalizedStringFromTableInBundle(@"Recommended Fonts", @"OUIInspectors", OMNI_BUNDLE, @"Title for section of font list"), ItemDisplayName,
                             recommendedItems, SectionItems, nil]];
        [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             NSLocalizedStringFromTableInBundle(@"All Fonts", @"OUIInspectors", OMNI_BUNDLE, @"Title for section of font list"), ItemDisplayName,
                             allItems, SectionItems, nil]];
        
        [_sections release];
        _sections = [[NSArray alloc] initWithArray:sections];
    } else {
        /*
         One section for each family that is in the selection. Within each section, one item for each face within that section.
         */
        NSMutableArray *sections = [NSMutableArray array];
        NSSet *selectedFamilyNames = [selection.fontDescriptors setByPerformingSelector:@selector(family)];
        NSSet *selectedFontNames = [selection.fontDescriptors setByPerformingSelector:@selector(fontName)];

        CGFloat fontSize = [UIFont labelFontSize];
        for (NSString *family in selectedFamilyNames) {
            NSMutableArray *items = [NSMutableArray array];
            
            UIFont *baseFont = _baseFontForFamily(family);
            if (!baseFont)
                continue;
            NSString *baseDisplayName = _displayNameForFont(baseFont, YES);

            NSArray *variantNames = [UIFont fontNamesForFamilyName:family];
            for (NSString *name in variantNames) {
                UIFont *font = [UIFont fontWithName:name size:fontSize];
                
                NSMutableDictionary *item = _itemForFont(font, ([selectedFontNames member:name] != nil), YES/*isFaceName*/);
                
                BOOL isBase;
                NSString *displayName = _displayNameForFontFaceName([item objectForKey:ItemDisplayName], baseDisplayName, &isBase);
                
                [item setObject:displayName forKey:ItemDisplayName];
                if (isBase)
                    [item setObject:(id)kCFBooleanTrue forKey:ItemIsBase];
                
                if (item)
                    [items addObject:item];
            }
            
            if ([items count] == 0)
                continue;
            [items sortUsingFunction:_compareItem context:NULL];
            
            // TODO: This probably isn't the human readable name.
            
            [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                 baseDisplayName, ItemDisplayName,
                                 items, SectionItems, nil]];
        }
        
        [sections sortUsingFunction:_compareDisplayName context:NULL];
        [_sections release];
        _sections = [[NSArray alloc] initWithArray:sections];
    }
    
    UITableView *tableView = (UITableView *)self.view;
    [tableView reloadData];
}

#pragma mark -
#pragma mark UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _showFamilies = YES;
    
    // TODO: Redo the fore/background color based on the incoming selection?
    UITableView *tableView = (UITableView *)self.view;
    tableView.opaque = YES;
    tableView.backgroundColor = [UIColor whiteColor];

    [self updateInterfaceFromInspectedObjects];
}

#pragma mark -
#pragma mark UITableViewDataSource

static NSDictionary *_sectionAtIndex(OUIFontInspectorDetailSlice *self, NSUInteger sectionIndex)
{
    NSUInteger sectionCount = [self->_sections count];
    if (sectionIndex >= sectionCount) {
        NSLog(@"sectionIndex = %ld of %ld", sectionIndex, sectionCount);
        return nil;
    }
    
    return [self->_sections objectAtIndex:sectionIndex];
}

static NSArray *_itemsForSectionIndex(OUIFontInspectorDetailSlice *self, NSUInteger sectionIndex)
{
    return [_sectionAtIndex(self, sectionIndex) objectForKey:SectionItems];
}

static NSDictionary *_itemAtIndexPath(OUIFontInspectorDetailSlice *self, NSIndexPath *indexPath)
{
    // Index path is group/row -- we expect [01]/N.
    if ([indexPath length] != 2) {
        NSLog(@"indexPath = %@", indexPath);
        return nil;
    }
    
    NSArray *items = _itemsForSectionIndex(self, [indexPath indexAtPosition:0]);
    NSUInteger itemIndex = [indexPath indexAtPosition:1];
    NSUInteger itemCount = [items count];
    if (itemIndex >= itemCount) {
        NSLog(@"itemIndex = %ld of %ld", itemIndex, itemCount);
        return nil;
    }
    
    return [items objectAtIndex:itemIndex];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return [_sections count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    NSString *title = [_sectionAtIndex(self, section) objectForKey:ItemDisplayName];
    return title ? title : @"???";
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    NSArray *items = _itemsForSectionIndex(self, section);
    return [items count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Returning a nil cell will cause UITableView to throw an exception
    NSDictionary *item = _itemAtIndexPath(self, indexPath);
    if (!item)
        return [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:nil] autorelease];
    
    NSString *identifier = [item objectForKey:ItemIdentifier];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:identifier] autorelease];
        
        cell.backgroundColor = [UIColor whiteColor];
        cell.opaque = YES;
        
        UILabel *label = cell.textLabel;
        label.text = [item objectForKey:ItemDisplayName];
        label.font = [item objectForKey:ItemFont];
        label.opaque = YES;
        label.backgroundColor = [UIColor whiteColor];
        label.textColor = [UIColor blackColor];
        
        [cell sizeToFit];
    }
    cell.accessoryType = [[item objectForKey:ItemSelected] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSDictionary *item = _itemAtIndexPath(self, indexPath);
    if (!item) {
        OBASSERT_NOT_REACHED("Bad selection");
        return;
    }
    
    UIFont *font = [item objectForKey:ItemFont];
    if (!font) {
        OBASSERT_NOT_REACHED("No font");
        return;
    }
    
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.slice.appropriateObjectsForInspection) {
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self.slice];
            
            CGFloat fontSize;
            if (fontDescriptor)
                fontSize = [fontDescriptor size];
            else
                fontSize = [UIFont labelFontSize];
            
            if (_showFamilies) {
                if (fontDescriptor) {
                    fontDescriptor = [fontDescriptor newFontDescriptorWithFamily:font.familyName];
                } else
                    fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:fontSize];
            } else {
                // TODO: Take the current font descriptor and try to add the delta between this font's base font and this font?
                CTFontRef fontRef = CTFontCreateWithName((CFStringRef)font.fontName, fontSize, NULL);
                if (fontRef) {
                    fontDescriptor = [[OAFontDescriptor alloc] initWithFont:fontRef];
                    CFRelease(fontRef);
                } else
                    fontDescriptor = nil;
            }
            
            if (fontDescriptor) {
                [object setFontDescriptor:fontDescriptor fromInspectorSlice:self.slice];
                [fontDescriptor release];
            }
        }
    }
    [inspector didEndChangingInspectedObjects];
    
    // Selection will have changed
    [self updateInterfaceFromInspectedObjects];
}

@end
