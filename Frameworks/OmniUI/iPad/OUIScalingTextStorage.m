// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingTextStorage.h>

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniUI/NSTextStorage-OUIExtensions.h>
#import <OmniUI/OUIFontUtilities.h>

RCS_ID("$Id$");

@implementation OUIScalingTextStorage
{
    NSTextStorage *_underlyingStorageWithTrueFontSizes;   // font sizes here are what should be saved and inspected
    NSMutableAttributedString *_storageWithFontSizesScaledForDisplay;   // font sizes here have been scaled so the text view will display them at the correct relative size for the zoomed display, even though the text view knows nothing at all about scaling
    BOOL _isEditingUnderlyingTextStorage;
    NSInteger _fixAttributesNestingLevel;
    NSDictionary *_lastUsedAttributes;
    BOOL _useLastUsedAttributes;
}

static void _scaleAttributes(NSMutableDictionary *scaledAttributes, NSDictionary *originalAttributes, CGFloat scale)
{
    // Make sure dynamic type fonts don't make it in here
    OBPRECONDITION(OUIFontIsDynamicType(originalAttributes[NSFontAttributeName]) == NO);
    OBPRECONDITION(OUIFontIsDynamicType([originalAttributes[OAFontDescriptorAttributeName] font]) == NO);

    // This gets called in our -fixAttributesInRange: where we might have a OAFontDescriptor specifying Helvetica Neue but with a NSFont that has already undergone font substitution for the characters in the given range ("STHeitiSC-Light" for example).
    // So, here we prefer the face from the font to the font descriptor, assuming the underlying text storage has already done font descriptor->font descriptor if it wanted to. We prefer the size from the font scriptor, though, to avoid repeated scaling of the font.

    UIFont *font = originalAttributes[NSFontAttributeName];
    OAFontDescriptor *fontDescriptor = originalAttributes[OAFontDescriptorAttributeName];
    CGFloat pointSize = fontDescriptor ? fontDescriptor.size : (font ? font.pointSize : 12);
    
    /*
     This odd ordering is due to Radar 15323244: Crash due to missing font in iOS 7.0.3 (Helvetica Neue italic)
     
     In the crashing case, we had a *non-nil* font, <UICTFont: 0x1966a470> font-family: "Helvetica Neue"; font-weight: normal; font-style: italic; font-size: 12.00pt
     We would then try to scale it with -fontWithSize: and would get back nil. Really, -fontWithSize: should never return nil for non-nil receivers.
     We handle this now by trying the scaling first and by double-checking before assigning into the text attributes (in case the fallback path fails).
     */
    
    if (font) {
        UIFont *scaledFont = [font fontWithSize:pointSize*scale];
        if (scaledFont == nil && [[fontDescriptor family] isEqualToString:@"Helvetica Neue"] && [fontDescriptor italic]) {
            // Possibly hitting the bug noted above!
            font = [UIFont fontWithName:@"Helvetica Oblique" size:pointSize*scale]; // This is close, and our font descriptor based approach should hopefully let us go back to the right thing when unitalicising
        } else
            font = scaledFont;
    }
    if (!font) {
        font = [[fontDescriptor font] fontWithSize:pointSize*scale];
        if (font == nil){
            // document default for nil
            font = [UIFont fontWithName:@"Helvetica Neue" size:pointSize*scale];
        }
    }
    
    if (font) // just in case the fallback path's scaling doesn't work. We'll get the wrong size text, but won't explode
        scaledAttributes[NSFontAttributeName] = font;

    if (originalAttributes[NSKernAttributeName]) {
        scaledAttributes[NSKernAttributeName] = [NSNumber numberWithFloat:(((NSNumber *)originalAttributes[NSKernAttributeName]).floatValue / scale)];
    }
}

NSDictionary *OUICopyScaledTextAttributes(NSDictionary *textAttributes, CGFloat scale)
{
    NSMutableDictionary *scaledAttributes = [[NSMutableDictionary alloc] initWithDictionary:textAttributes];
    _scaleAttributes(scaledAttributes, textAttributes, scale);
    NSDictionary *result = [scaledAttributes copy];
    return result;
}

+ (NSMutableAttributedString *)copyAttributedStringByScalingAttributedString:(NSAttributedString *)attributedString byScale:(CGFloat)scale;
{
    NSMutableAttributedString *scaledAttributedString = [[NSMutableAttributedString alloc] initWithAttributedString:attributedString];
    [self _scaleAttributesBy:scale fromAttributedString:attributedString range:NSMakeRange(0, [attributedString length]) applier:^(NSDictionary *scaledAttributes, NSRange range){
        [scaledAttributedString setAttributes:scaledAttributes range:range];
        // Not calling -edited:range:changeInLength: here since there are no processing observers yet

    }];
    return scaledAttributedString;
}

- (id)initWithString:(NSString *)str;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (id)initWithString:(NSString *)str attributes:(NSDictionary *)attrs;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (id)initWithAttributedString:(NSAttributedString *)attrStr;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithUnderlyingTextStorage:(NSTextStorage *)textStorage scale:(CGFloat)scale;
{
    OBPRECONDITION(textStorage);
    OBPRECONDITION(scale > 0);
    
    if (!(self = [super init]))
        return nil;
    
    _underlyingStorageWithTrueFontSizes = textStorage;
    _scale = scale;

    _storageWithFontSizesScaledForDisplay = [[NSMutableAttributedString alloc] initWithAttributedString:_underlyingStorageWithTrueFontSizes];
    [self invalidateAttributesInRange:NSMakeRange(0, [_storageWithFontSizesScaledForDisplay length])]; // Make sure we fix stuff on the first pass
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_underlyingTextStorageDidProcessEditing:) name:NSTextStorageDidProcessEditingNotification object:_underlyingStorageWithTrueFontSizes];
    
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification object:_underlyingStorageWithTrueFontSizes];
}

- (void)setScale:(CGFloat)scale;
{
    if (_scale == scale)
        return;
    _scale = scale;
    [self invalidateAttributesInRange:NSMakeRange(0, [self length])];
}

#pragma mark - NSTextStorage subclass

- (NSUInteger)length;
{
    return [_storageWithFontSizesScaledForDisplay length];
}

- (NSString *)string;
{
    return [_storageWithFontSizesScaledForDisplay string];
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range;
{
    if (location == self.length)
        return _lastUsedAttributes;
    return [_storageWithFontSizesScaledForDisplay attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
{
    // This gets called by UITextView while editing.

    // if we are deleting text, save attributes here to use later in fixAttributes so we don't lose font size
    _useLastUsedAttributes = NO;
    if (str.length == 0 && range.length > 0) {
        _lastUsedAttributes = [_underlyingStorageWithTrueFontSizes attributesAtIndex:range.location effectiveRange:NULL];
    } else if (_underlyingStorageWithTrueFontSizes.length == 0) {
        _useLastUsedAttributes = YES;
    }
    
    [_storageWithFontSizesScaledForDisplay replaceCharactersInRange:range withString:str];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:[str length] - range.length];

    OBASSERT(_isEditingUnderlyingTextStorage == NO);
    _isEditingUnderlyingTextStorage = YES;
    [_underlyingStorageWithTrueFontSizes replaceCharactersInRange:range withString:str];
    _isEditingUnderlyingTextStorage = NO;
}

/*
 This will get called by UITextView's (currently) private -toggleBoldface:, -toggleItalics:, and -toggleUnderline:.
 */
- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)attributeRange;
{
    // Make sure dynamic type fonts don't make it in here
    OBPRECONDITION(OUIFontIsDynamicType(attributes[NSFontAttributeName]) == NO);
    OBPRECONDITION(OUIFontIsDynamicType([attributes[OAFontDescriptorAttributeName] font]) == NO);
    
    // This also gets called to set typing attributes, so we can't reject it. We want font edits to normally go through our text spans.
    [_storageWithFontSizesScaledForDisplay setAttributes:attributes range:attributeRange];
    [self edited:NSTextStorageEditedAttributes range:attributeRange changeInLength:0];

    // If we are inside -fixAttributesInRange:, we are cleaning up our own attributes and don't want to push stuff down (as opposed to edits coming in from an external editor).
    if (_fixAttributesNestingLevel > 0)
        return;
    
    // Ignore the incoming size (unless all text was deleted), but do allow changes in weight, italic, etc (so that UITextView's cmd-b/cmd-i support works when allowsEditingTextAttributes is set to YES).
    UIFont *requestedFont = attributes[NSFontAttributeName];
    
    OBASSERT(_isEditingUnderlyingTextStorage == NO);
    _isEditingUnderlyingTextStorage = YES;
    __block NSMutableDictionary *attributesToSetOnUnderlyingTextStorage = [[NSMutableDictionary alloc] initWithDictionary:attributes];
    [_underlyingStorageWithTrueFontSizes enumerateAttributesInRange:attributeRange options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary *originalUnderlyingAttributes, NSRange underlyingRange, BOOL *stop) {
        // If we are being told to set a font descriptor, then use it (for example, if the typing attributes have been changed to be a different font size and text is inserted).
        OAFontDescriptor *underlyingFontDescriptor = attributes[OAFontDescriptorAttributeName];
        if (!underlyingFontDescriptor)
            underlyingFontDescriptor = originalUnderlyingAttributes[OAFontDescriptorAttributeName];
        if (underlyingFontDescriptor) {
            // Just set the font descriptor -- we assume that if the underlying text storage knows about this, it will fix its own font.
            if (requestedFont) {
                // Make sure dynamic type fonts don't make it in here
                OBASSERT(OUIFontIsDynamicType(requestedFont) == NO);

                OAFontDescriptor *updatedFontDescriptor = [[OAFontDescriptor alloc] initWithFont:[requestedFont fontWithSize:[underlyingFontDescriptor size]]];
                attributesToSetOnUnderlyingTextStorage[OAFontDescriptorAttributeName] = updatedFontDescriptor;
            } else {
                [attributesToSetOnUnderlyingTextStorage removeObjectForKey:OAFontDescriptorAttributeName];
            }
            [_underlyingStorageWithTrueFontSizes setAttributes:attributesToSetOnUnderlyingTextStorage range:underlyingRange];
            return;
        }
        
        UIFont *underlyingFont = originalUnderlyingAttributes[NSFontAttributeName];
        if (_useLastUsedAttributes && _lastUsedAttributes[NSFontAttributeName]) {
            underlyingFont = _lastUsedAttributes[NSFontAttributeName];
        }
        if (underlyingFont) {
            if (requestedFont) {
                OBASSERT(OUIFontIsDynamicType(underlyingFont) == NO);
                UIFont *updatedFont = [requestedFont fontWithSize:[underlyingFont pointSize]];
                attributesToSetOnUnderlyingTextStorage[NSFontAttributeName] = updatedFont;
            } else if (_useLastUsedAttributes){
                OBASSERT(OUIFontIsDynamicType(underlyingFont) == NO);
                attributesToSetOnUnderlyingTextStorage[NSFontAttributeName] = _lastUsedAttributes[NSFontAttributeName];
            } else {
                [attributesToSetOnUnderlyingTextStorage removeObjectForKey:NSFontAttributeName];
            }
            [_underlyingStorageWithTrueFontSizes setAttributes:attributesToSetOnUnderlyingTextStorage range:underlyingRange];
            return;
        }
        
        OBASSERT(requestedFont == nil); // Fill in something?
        [attributesToSetOnUnderlyingTextStorage removeObjectForKey:OAFontDescriptorAttributeName];
        [attributesToSetOnUnderlyingTextStorage removeObjectForKey:NSFontAttributeName];
        [_underlyingStorageWithTrueFontSizes setAttributes:attributesToSetOnUnderlyingTextStorage range:underlyingRange];
    }];
    
    _isEditingUnderlyingTextStorage = NO;
}

- (void)fixAttributesInRange:(NSRange)entireRange;
{
    // This gets called recursively when further changes are made, so we can't just have a flag.
    _fixAttributesNestingLevel++;
    
    // Font substitution for Kanji, etc.
    [super fixAttributesInRange:entireRange];
    
    [[self class] _scaleAttributesBy:_scale fromAttributedString:_underlyingStorageWithTrueFontSizes range:entireRange applier:^(NSDictionary *scaledAttributes, NSRange range){
        [_storageWithFontSizesScaledForDisplay setAttributes:scaledAttributes range:range];
        [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
    }];
    
    OBASSERT(_fixAttributesNestingLevel > 0);
    _fixAttributesNestingLevel--;
}

#pragma mark - NSTextStorage (OUIExtensions)

// Inspect the underlying text storage
- (NSArray *)textSpansInRange:(NSRange)range inTextView:(OUITextView *)textView;
{
    return [_underlyingStorageWithTrueFontSizes textSpansInRange:range inTextView:textView];
}

- (NSTextStorage *)underlyingTextStorage;
{
    return [_underlyingStorageWithTrueFontSizes underlyingTextStorage];
}

#pragma mark - Private

+ (void)_scaleAttributesBy:(CGFloat)scale fromAttributedString:(NSAttributedString *)originalAttributedString range:(NSRange)entireRange applier:(void (^)(NSDictionary *scaledAttributes, NSRange range))applier;
{
    [originalAttributedString enumerateAttributesInRange:entireRange options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        NSMutableDictionary *scaledAttributes = [[NSMutableDictionary alloc] initWithDictionary:attrs];
        _scaleAttributes(scaledAttributes, attrs, scale);
        applier(scaledAttributes, range);
    }];
}

- (void)_underlyingTextStorageDidProcessEditing:(NSNotification *)note;
{
    // If we are doing the mutation, our mutator should do any needed fixups. But if this is an edit by a third party, we need to adjust ourselves.
    if (_isEditingUnderlyingTextStorage) {
        OBASSERT(OFISEQUAL(_storageWithFontSizesScaledForDisplay.string, _underlyingStorageWithTrueFontSizes.string));
        return;
    }
    
    NSRange editedRange = _underlyingStorageWithTrueFontSizes.editedRange;
    NSTextStorageEditActions editedMask = _underlyingStorageWithTrueFontSizes.editedMask;
    
    //NSLog(@"processing third-party edit");
    
    // We assume that all *text* editing is done via us while we are alive. So, this just means that some attributes have been changed (probably by an inspector via -textSpansInRange:).
    if (editedMask & NSTextStorageEditedCharacters) {
        NSInteger changeInLength = _underlyingStorageWithTrueFontSizes.changeInLength;
        
        //NSLog(@"editedRange = %@", NSStringFromRange(editedRange));
        //NSLog(@"changeInLength = %ld", _storageWithTrueFontSizes.changeInLength);

        // editedRange has the length *after* the changeInLength. (So select-all, delete, will end up with an editedRange of {0,0}).
        NSRange originalRange = NSMakeRange(editedRange.location, editedRange.length - changeInLength);
        
        // This will cause attribute fixing on us in the edited range, so no need to do that too.
        [self beginEditing];
        {
            [_storageWithFontSizesScaledForDisplay replaceCharactersInRange:originalRange withAttributedString:[_underlyingStorageWithTrueFontSizes attributedSubstringFromRange:editedRange]];
            OBASSERT(OFISEQUAL(_storageWithFontSizesScaledForDisplay.string, _underlyingStorageWithTrueFontSizes.string));
            
            // Let any of *our* observers know -- we have to pass in our original length here.
            [self edited:editedMask range:originalRange changeInLength:changeInLength];
            OBASSERT(self.editedMask == editedMask);
            OBASSERT(NSEqualRanges(self.editedRange, editedRange));
            OBASSERT(self.changeInLength == changeInLength);
        }
        
        //NSLog(@"resulting editedMask:%ld editedRange:%@ changeInLength:%ld", self.editedMask, NSStringFromRange(self.editedRange), self.changeInLength);
        [self endEditing];
    } else {
        OBASSERT(OFISEQUAL(_storageWithFontSizesScaledForDisplay.string, _underlyingStorageWithTrueFontSizes.string));
        [self invalidateAttributesInRange:editedRange];
    }
}

@end

@implementation NSAttributedString (OUIScalingTextStorageExtensions)

+ (NSAttributedString *)newScaledAttributedStringWithString:(NSString *)string attributes:(NSDictionary *)attributes scale:(CGFloat)scale;
{
    NSMutableDictionary *scaledAttributes = [[NSMutableDictionary alloc] initWithDictionary:attributes];
    _scaleAttributes(scaledAttributes, attributes, scale);
    NSAttributedString *result = [[NSAttributedString alloc] initWithString:string attributes:scaledAttributes];
    return result;
}

@end
