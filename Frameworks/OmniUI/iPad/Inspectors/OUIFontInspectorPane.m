// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontInspectorPane.h>

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniUI/OUIAbstractTableViewInspectorSlice.h>
#import <OmniUI/OUIFontFamilyInspectorSlice.h>
#import <OmniUI/OUIFontUtilities.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIThemedTableViewCell.h>
#import <OmniUI/UITableView-OUIExtensions.h>

@implementation OUIFontInspectorPane
{
    UIFont *_showFacesOfFont;
    NSArray *_sections;
}

static UIFont *_baseFontForFamily(NSString *familyName)
{
    NSString *baseFontName = OUIBaseFontNameForFamilyName(familyName);
    if (baseFontName) {
        CGFloat size = [UIFont labelFontSize];
        return [UIFont fontWithName:baseFontName size:size];
    }

    return nil; // Just use the default font
}

+ (NSSet *)recommendedFontFamilyNames;
{
    static NSSet *names = nil;
    if (!names)
        // Lucida Grande isn't available on the device right now, but add it to the preferred list in case it ever shows up.
        names = [[NSSet alloc] initWithObjects:@"Avenir Next", @"Futura", @"Georgia", @"Gill Sans", @"Helvetica Neue", @"Hoefler Text", @"Iowan Old Style", @"Lucida Grande", @"Optima", @"Palatino", nil];
    return names;
}

@synthesize showFacesOfFont = _showFacesOfFont;
- (void)setShowFacesOfFont:(UIFont *)showFacesOfFont;
{
    // Should be the base font of a family if set
    OBPRECONDITION(!_showFacesOfFont || _showFacesOfFont == _baseFontForFamily([_showFacesOfFont familyName]));
    
    if (_showFacesOfFont == showFacesOfFont)
        return;
    
    _showFacesOfFont = showFacesOfFont;
    
    _sections = nil;
    
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
}

#pragma mark - OUIInspectorPane subclass

- (void)setInspector:(OUIInspector *)aInspector;
{
    [super setInspector:aInspector];
    [self _buildSections];
}

static NSString * const SectionItems = @"items";

static NSString * const ItemDisplayName = @"displayName"; // NSString
static NSString * const ItemFont = @"font"; // UIFont
static NSString * const ItemSelected = @"selected"; // NSNumber<BOOL>
static NSString * const ItemIsBase = @"isBase"; // NSNumber<BOOL>
static NSString * const ItemHasMulitpleFaces = @"hasMultipleFaces"; // NSNumber<BOOL>
static NSString * const ItemIdentifier = @"identifier"; // reuse identifier

static void _updateItem(NSMutableDictionary *item, BOOL selected)
{
    [item setObject:selected ? (id)kCFBooleanTrue : (id)kCFBooleanFalse forKey:ItemSelected];
}

static NSMutableDictionary *_makeItemForFont(UIFont *font, BOOL isFaceName)
{
    NSString *displayName = OUIDisplayNameForFont(font, !isFaceName);
    
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    [item setObject:displayName forKey:ItemDisplayName];
    [item setObject:font forKey:ItemFont];
    
    BOOL familyHasMultipleFaces = [[UIFont fontNamesForFamilyName:[font familyName]] count] > 1;
    [item setObject:familyHasMultipleFaces ? (id)kCFBooleanTrue : (id)kCFBooleanFalse forKey:ItemHasMulitpleFaces];

    // Provide enough info in the identifier to be a suitable table view reuse identifier. In particular we need a flag for whether we are just displaying the face name. Otherwise, we can get a cached "Georgia" (from when we picked a font family) when we really should get "Regular" while looking at the face list.
    [item setObject:[NSString stringWithFormat:@"%@ -- %@ face:%d", font.fontName, displayName, isFaceName] forKey:ItemIdentifier];
        
    return item;
}

static NSComparisonResult _compareDisplayName(id obj1, id obj2, void *context)
{
    NSDictionary *dict1 = obj1;
    NSDictionary *dict2 = obj2;
    
    return [[dict1 objectForKey:ItemDisplayName] localizedCaseInsensitiveCompare:[dict2 objectForKey:ItemDisplayName]];
}
static NSComparisonResult _compareItem(id obj1, id obj2, void *context)
{
    NSDictionary *dict1 = obj1;
    NSDictionary *dict2 = obj2;

    // The base face should be first
    BOOL base1 = [[dict1 objectForKey:ItemIsBase] boolValue];
    BOOL base2 = [[dict2 objectForKey:ItemIsBase] boolValue];
    
    if (base1 ^ base2) {
        if (base1)
            return NSOrderedAscending;
        return NSOrderedDescending;
    }
    
    return _compareDisplayName(obj1, obj2, context);
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    if (reason == OUIInspectorUpdateReasonObjectsEdited)
        return; // list of options not changing and we want to fade selection
    
    if (!_sections) {
        [self _buildSections];
        
        UITableView *tableView = (UITableView *)self.view;
        [tableView reloadData];
    } else {
        [self _updateSectionItems];
    }    
}

#pragma mark - UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // iOS 7 GM bug: separators are not reliably drawn. This doesn't actually fix the color after the first display, but at least it gets the separators to show up.
    UITableView *tableView = (UITableView *)self.view;
    tableView.separatorColor = [OUIInspectorSlice sliceSeparatorColor];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    // If we go down into a font family that isn't selected and select one of its faces, then when we come back we need to update selection
    UITableView *tableView = (UITableView *)self.view;
    if (tableView.style == UITableViewStylePlain) {
        tableView.backgroundColor = [OUIInspectorSlice sliceBackgroundColor];
    } else {
        tableView.backgroundColor = nil;
    }
    [tableView reloadData];
    
    [self _scrollFirstSelectedItemToVisible:NO];
}

#pragma mark - UITableViewDataSource

static NSDictionary *_sectionAtIndex(OUIFontInspectorPane *self, NSUInteger sectionIndex)
{
    NSUInteger sectionCount = [self->_sections count];
    if (sectionIndex >= sectionCount) {
        NSLog(@"sectionIndex = %ld of %ld", sectionIndex, sectionCount);
        return nil;
    }
    
    return [self->_sections objectAtIndex:sectionIndex];
}

static NSArray *_itemsForSectionIndex(OUIFontInspectorPane *self, NSUInteger sectionIndex)
{
    return [_sectionAtIndex(self, sectionIndex) objectForKey:SectionItems];
}

static NSDictionary *_itemAtIndexPath(OUIFontInspectorPane *self, NSIndexPath *indexPath)
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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    NSString *title = [_sectionAtIndex(self, section) objectForKey:ItemDisplayName];
    UIView *headerView = [OUIAbstractTableViewInspectorSlice sectionHeaderViewWithLabelText:(title ? title : @"???") forTableView:tableView];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    return 44;
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
    if (!item) {
        OUIThemedTableViewCell *cell = [[OUIThemedTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [OUIInspectorSlice sliceBackgroundColor];
        return cell;
    }
    
    NSString *identifier = [item objectForKey:ItemIdentifier];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[OUIThemedTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        
        cell.backgroundColor = [OUIInspectorSlice sliceBackgroundColor];
        cell.opaque = YES;
        
        UILabel *label = cell.textLabel;
        label.text = [item objectForKey:ItemDisplayName];
        label.font = [item objectForKey:ItemFont];
        label.opaque = YES;
        label.backgroundColor = cell.backgroundColor;
        label.textColor = [OUIInspector labelTextColor];
        
        [cell sizeToFit];
    }
    
    OUITableViewCellShowSelection(cell, self._tableViewCellSelectionType, [[item objectForKey:ItemSelected] boolValue]);

    if (_showFacesOfFont == nil)
        cell.accessoryType = [[item objectForKey:ItemHasMulitpleFaces] boolValue] ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone;
    
    return cell;
}

#pragma mark - UITableViewDelegate

static OAFontDescriptor *_fixFixedPitchTrait(OAFontDescriptor *fontDescriptor, NSString *familyName);

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
        OUIInspectorSlice *parentSlice = self.parentSlice;
        for (id <OUIFontInspection> object in parentSlice.appropriateObjectsForInspection) {
            // Grab any existing font size in order to preserve it
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:parentSlice];
            CGFloat fontSize;
            if (fontDescriptor)
                fontSize = [fontDescriptor size];
            else
                fontSize = [UIFont labelFontSize];
            
            if (_showFacesOfFont == nil) {
                // We're looking at font families; create a font descriptor for the newly-selected item (font family)
                if (fontDescriptor) {
                    fontDescriptor = [fontDescriptor newFontDescriptorWithFamily:font.familyName];
                    OAFontDescriptor *repairedFontDescriptor = _fixFixedPitchTrait(fontDescriptor, font.familyName);
                    fontDescriptor = repairedFontDescriptor;
                } else
                    fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:fontSize];
            } else {
                // We're looking at font faces within a family; create a font descriptor for the newly-selected item (font face)
                fontDescriptor = [[OAFontDescriptor alloc] initWithFont:font];
                fontDescriptor = [fontDescriptor newFontDescriptorWithSize:fontSize];
            }
            
            if (fontDescriptor) {
                [object setFontDescriptor:fontDescriptor fromInspectorSlice:parentSlice];
            }
        }
    }
//    FinishUndoGroup();  // I think this should be here for Graffle iOS, but our build dependencies won't allow it and testing shows this isn't currently a problem
    [inspector didEndChangingInspectedObjects];
    
    // Our -updateInterfaceFromInspectedObjects: won't reload data when getting called due to an edit, which is good since it lets us fade the selection.

    // Clears the selection and updates images.
    OUITableViewFinishedReactingToSelection(tableView, self._tableViewCellSelectionType);
    [self _updateSectionItems];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(_showFacesOfFont == nil);
    
    NSDictionary *item = _itemAtIndexPath(self, indexPath);
    if (!item) {
        OBASSERT_NOT_REACHED("Bad selection");
        return;
    }

    UIFont *font = [item objectForKey:ItemFont];
    
    [(OUIFontFamilyInspectorSlice *)self.parentSlice showFacesForFamilyBaseFont:font];
}

#pragma mark - Private

- (void)_buildSections;
{
    OUIInspectorSlice *parentSlice = self.parentSlice;
    if (parentSlice == nil) {
        _sections = nil;
        return;
    }
    
    OUIFontSelection *selection = OUICollectFontSelection(parentSlice, parentSlice.appropriateObjectsForInspection);
    //NSLog(@"selection.fontDescriptors = %@", selection.fontDescriptors);

    if (_showFacesOfFont == nil) {
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
            
            NSMutableDictionary *item = _makeItemForFont(baseFont, NO/*isFaceName*/);
            if (!item)
                continue;
            
            _updateItem(item, ([selectedFamilyNames member:family] != nil));
            
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
        
        _sections = [[NSArray alloc] initWithArray:sections];
    } else {
        /*
         One section, showing only the faces within the specified font.
         */
        NSMutableArray *sections = [NSMutableArray array];
        NSSet *selectedFontNames = [selection.fontDescriptors setByPerformingSelector:@selector(fontName)];
        
        OBASSERT(_showFacesOfFont == _baseFontForFamily([_showFacesOfFont familyName]));
        
        NSString *familyName = [_showFacesOfFont familyName];
        CGFloat fontSize = [UIFont labelFontSize];
        NSMutableArray *items = [NSMutableArray array];
        
        NSString *baseDisplayName = OUIDisplayNameForFont(_showFacesOfFont, YES);
        
        NSArray *variantNames = [UIFont fontNamesForFamilyName:familyName];
        for (NSString *name in variantNames) {
            UIFont *font = [UIFont fontWithName:name size:fontSize];
            
            NSMutableDictionary *item = _makeItemForFont(font, YES/*isFaceName*/);
            
            _updateItem(item, ([selectedFontNames member:name] != nil));
            
            NSString *displayName = OUIDisplayNameForFontFaceName([item objectForKey:ItemDisplayName], baseDisplayName);
            
            BOOL isBase = OUIIsBaseFontNameForFamily(name, familyName);

            [item setObject:displayName forKey:ItemDisplayName];
            if (isBase)
                [item setObject:(id)kCFBooleanTrue forKey:ItemIsBase];
            
            if (item)
                [items addObject:item];
        }
        
        OBASSERT([items count] > 0);
        [items sortUsingFunction:_compareItem context:NULL];
        
        // TODO: This probably isn't the human readable name.
        
        [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             baseDisplayName, ItemDisplayName,
                             items, SectionItems, nil]];
        
        [sections sortUsingFunction:_compareDisplayName context:NULL];
        _sections = [[NSArray alloc] initWithArray:sections];
    }
}

- (OUITableViewCellSelectionType)_tableViewCellSelectionType;
{
    // If we're viewing faces of a specific font, use the accessory selection type. Otherwise, we may already have an accessory, which is used to access the specific faces, so we need to use the image selection type.
    return (_showFacesOfFont == nil) ? OUITableViewCellImageSelectionType : OUITableViewCellAccessorySelectionType;
}

- (void)_updateSectionItems;
{
    OUIInspectorSlice *parentSlice = self.parentSlice;
    OUIFontSelection *selection = OUICollectFontSelection(parentSlice, parentSlice.appropriateObjectsForInspection);
        
    NSSet *selectedFontNames;
    if (_showFacesOfFont)
        selectedFontNames = [selection.fontDescriptors setByPerformingSelector:@selector(fontName)];
    else
        selectedFontNames = [selection.fontDescriptors setByPerformingSelector:@selector(family)];
    
    // Our item list doesn't change, but some of the flags will.
    for (NSDictionary *section in _sections) {
        for (NSMutableDictionary *item in [section objectForKey:SectionItems]) {
            UIFont *font = [item objectForKey:ItemFont];
            
            NSString *name;
            if (_showFacesOfFont)
                name = [font fontName];
            else
                name = [font familyName];
            
            _updateItem(item, ([selectedFontNames member:name] != nil));
        }
    }
}

- (void)_scrollFirstSelectedItemToVisible:(BOOL)animated;
{
    UITableView *tableView = (UITableView *)self.view;
    
    // Scroll the first selected item to visible.
    NSIndexPath *firstSelectedIndexPath = nil;
    NSUInteger sectionIndex, sectionCount = [_sections count];
    for (sectionIndex = 0; sectionIndex < sectionCount; sectionIndex++) {
        NSDictionary *section = [_sections objectAtIndex:sectionIndex];
        NSArray *items = [section objectForKey:SectionItems];
        NSUInteger itemIndex, itemCount = [items count];
        for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
            NSDictionary *item = [items objectAtIndex:itemIndex];
            if ([[item objectForKey:ItemSelected] boolValue]) {
                firstSelectedIndexPath = [NSIndexPath indexPathForRow:itemIndex inSection:sectionIndex];
                [tableView scrollToRowAtIndexPath:firstSelectedIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:animated];
                return;
            }
        }
    }
}

@end

#import <CoreText/CoreText.h>

static OAFontDescriptor *_fixFixedPitchTrait(OAFontDescriptor *fontDescriptor, NSString *familyName)
{
    // Set or clear the fixed pitch trait based on the default for the family. Otherwise setting a font from the font faces inspector to something like Courier New Regular causes the inspector style to pick up the fixed width trait, but subsequent changes to the font using the regular (non-faces) inspector will not clear the trait. At least on iOS, fixed-width-edness is a property of the family, so if the user chooses a different family, let's respect its fixed-width-edness.
    OBPRECONDITION(fontDescriptor != nil);
    OBPRECONDITION(familyName != nil);
    
    CTFontDescriptorRef descriptorFromFamily = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)@{(id)kCTFontFamilyNameAttribute: familyName});
    NSDictionary *traitsFromFamily = (NSDictionary *)CFBridgingRelease(CTFontDescriptorCopyAttribute(descriptorFromFamily, kCTFontTraitsAttribute));
    NSNumber *symbolicTraitsFromFamily = traitsFromFamily[(id)kCTFontSymbolicTrait];
    CFRelease(descriptorFromFamily);
    
    BOOL familyHasMonoSpaceTrait = ([symbolicTraitsFromFamily unsignedIntegerValue] & kCTFontMonoSpaceTrait) != 0;
    
    return [fontDescriptor newFontDescriptorWithValue:familyHasMonoSpaceTrait forTrait:kCTFontMonoSpaceTrait];
}

