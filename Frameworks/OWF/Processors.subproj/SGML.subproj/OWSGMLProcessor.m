// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSString-OWSGMLString.h>
#import <OWF/OWAbstractObjectStream.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDocumentTitle.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWObjectStreamCursor.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWAddress.h>
#import <OWF/OWSGMLAppliedMethods.h>
#import <OWF/OWSGMLDTD.h>
#import <OWF/OWSGMLMethods.h>
#import <OWF/OWSGMLTag.h>
#import <OWF/OWSGMLTagType.h>
#import <OWF/OWURL.h>


RCS_ID("$Id$")

@implementation OWSGMLProcessor

static NSMutableDictionary *sgmlMethodsDictionary = nil;
static NSUserDefaults *defaults = nil;
static BOOL debugSGMLProcessing = NO;

+ (void)initialize;
{
    static BOOL initialized = NO;
    OWSGMLMethods *classSGMLMethods;

    [super initialize];

    if (initialized) {
        OWSGMLMethods *superclassSGMLMethods = [sgmlMethodsDictionary objectForKey:NSStringFromClass([self superclass])];
        classSGMLMethods = [[OWSGMLMethods alloc] initWithParent:superclassSGMLMethods];
    } else {
        initialized = YES;

        sgmlMethodsDictionary = [[NSMutableDictionary alloc] init];
        defaults = [NSUserDefaults standardUserDefaults];
        classSGMLMethods = [[OWSGMLMethods alloc] init];
    }
    [sgmlMethodsDictionary setObject:classSGMLMethods forKey:NSStringFromClass(self)];
}

+ (OWSGMLMethods *)sgmlMethods;
{
    return [sgmlMethodsDictionary objectForKey:[(NSObject *)self description]];
}

+ (OWSGMLDTD *)dtd;
{
    return nil;
}

+ (void)setDebug:(BOOL)newDebugSetting;
{
    debugSGMLProcessing = newDebugSetting;
}

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    self = [super initWithContent:initialContent context:aPipeline];
    if (self == nil)
        return nil;

    OWAddress *pipelineAddress = [self.pipeline contextObjectForKey:OWCacheArcSourceAddressKey];
    if (pipelineAddress == nil)
        pipelineAddress = [self.pipeline contextObjectForKey:OWCacheArcHistoryAddressKey];

#warning TODO [wiml nov2003] - Verify that base addresses are still set properly

    [self setBaseAddress:pipelineAddress];
    // GRT: Disable this until I figure out what the problem is with it (it was to do away with any cached error title in case this document has no real title of its own)
    //[OWDocumentTitle cacheRealTitle:nil forAddress:baseAddress];

    Class myClass = [self class];
    OWSGMLDTD *dtd = [myClass dtd];
    appliedMethods = [[OWSGMLAppliedMethods alloc] initFromSGMLMethods:[myClass sgmlMethods] dtd:dtd forTargetClass:myClass];

    unsigned int tagCount = [dtd tagCount];
    if (tagCount > 0) {
        openTags = calloc(tagCount,sizeof(unsigned int));
        implicitlyClosedTags = calloc(tagCount,sizeof(unsigned int));
    }
    return self;
}

- (void)dealloc;
{
    if (openTags)
        free(openTags);
    if (implicitlyClosedTags)
        free(implicitlyClosedTags);
}

- (void)setBaseAddress:(OWAddress *)anAddress;
{
    if (baseAddress == anAddress)
	return;
    baseAddress = anAddress;
}

- (BOOL)hasOpenTagOfType:(OWSGMLTagType *)tagType;
{
    return [self _hasOpenTagOfTypeIndex:[tagType dtdIndex]];
}

- (void)openTagOfType:(OWSGMLTagType *)tagType;
{
    [self _openTagOfTypeIndex:[tagType dtdIndex]];
}

- (void)closeTagOfType:(OWSGMLTagType *)tagType;
{
    [self _closeTagAtIndexWasImplicit:[tagType dtdIndex]];
}

#define MINIMUM_RECURSION_HEADROOM 65536

static size_t remainingStackSize(void)
{
#if !TARGET_CPU_PPC
#warning Do not know how stack grows on this platform
    // Since we only use this code to parse bookmarks & RSS feeds, and neither of those should nest very deeply, we decided we could cheat & always allow the recursion to continue on x86 processors.
    return MINIMUM_RECURSION_HEADROOM+1;
#else
    char *low;
    char stack;
    
    // The stack grows negatively on PPC
    low = pthread_get_stackaddr_np(pthread_self()) - pthread_get_stacksize_np(pthread_self());
    return &stack - low;
#endif
}

- (void)processContentForTag:(OWSGMLTag *)tag;
{
    OWSGMLTagType *tagType;
    NSUInteger tagIndex;
    id <OWSGMLToken> sgmlToken;

    // Require a certain amount of stack space before recursively processing tags so that deeply nested tags do not cause us to crash.
    if (remainingStackSize() < MINIMUM_RECURSION_HEADROOM)
        return;

    if (tag) {
	tagType = sgmlTagType(tag);
	tagIndex = [tagType dtdIndex];
	[self _openTagOfTypeIndex:tagIndex];
    } else {
	tagType = nil;
	tagIndex = NSNotFound;
    }

    while ((sgmlToken = [objectCursor readObject])) {
        switch ([sgmlToken tokenType]) {
            case OWSGMLTokenTypeStartTag:
                [self processTag:(id)sgmlToken];
                break;
            case OWSGMLTokenTypeCData:
                [self processCData:(id)sgmlToken];
                break;
            case OWSGMLTokenTypeEndTag: {
                OWSGMLTagType *closeTagType;
                
                closeTagType = sgmlTagType((OWSGMLTag *)sgmlToken);
                if (closeTagType == tagType) { // matching end tag?
                    if ([self _closeTagAtIndexWasImplicit:tagIndex])
                        break; // Nope, turns out we just implicitly closed this tag, so it's not our matching end tag
                    else
                        return; // Yup, this is our end tag, let's bail
                } else if (![self processEndTag:(id)sgmlToken] // end tag method not registered
                           && tag // We're not at the top level
                           && [self _hasOpenTagOfTypeIndex:[closeTagType dtdIndex]]) { // matching open tag before
                    [objectCursor ungetObject:sgmlToken];
                    [self _implicitlyCloseTagAtIndex:tagIndex];
                    return;
                }
                break;
            }
            default:
                break;
        }
    }
    
    if (tag)
        [self _closeTagAtIndexWasImplicit:tagIndex];
}

- (void)processUnknownTag:(OWSGMLTag *)tag;
{
    // We used to process the content for unknown tags, but this can lead to incredibly deep recursion if you're using a processor (such as our image map processor) which hasn't registered a method to handle, say, <img> tags (which don't have a matching close tag).  This caused crashes on pages like http://www.seatimes.com/classified/rent/b_docs/capts.html where we'd run out out of stack space.
}

- (void)processIgnoredContentsTag:(OWSGMLTag *)tag;
{
    id <OWSGMLToken> sgmlToken;
    OWSGMLTagType *tagType;

    tagType = sgmlTagType(tag);
    while ((sgmlToken = [objectCursor readObject])) {
        switch ([sgmlToken tokenType]) {
            case OWSGMLTokenTypeEndTag:
                if (sgmlTagType((OWSGMLTag *)sgmlToken) == tagType)
                    return;
            default:
                break;
        }
    }
}

- (void)processTag:(OWSGMLTag *)tag;
{
    // Call registered method to handle this tag
    sgmlAppliedMethodsInvokeTag(appliedMethods, tagTypeDtdIndex(sgmlTagType(tag)), self, tag);
}


- (BOOL)processEndTag:(OWSGMLTag *)tag;
{
    return sgmlAppliedMethodsInvokeEndTag(appliedMethods, tagTypeDtdIndex(sgmlTagType(tag)), self, tag);
}

- (void)processCData:(NSString *)cData;
{
}

- (void)process;
{
    [self processContentForTag:nil];
}

- (OWAddress *)baseAddress;
{
    return baseAddress;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (baseAddress)
	[debugDictionary setObject:baseAddress forKey:@"baseAddress"];

    return debugDictionary;
}

@end


@implementation OWSGMLProcessor (Tags)

static OWSGMLTagType *anchorTagType;
static OWSGMLTagType *baseTagType;
static OWSGMLTagType *bodyTagType;
static OWSGMLTagType *headTagType;
static OWSGMLTagType *htmlTagType;
static OWSGMLTagType *metaTagType;
static OWSGMLTagType *titleTagType;
static OWSGMLTagType *styleTagType;

static NSUInteger anchorEffectAttributeIndex;
static NSUInteger anchorHrefAttributeIndex;
static NSUInteger anchorTargetAttributeIndex;
static NSUInteger anchorTitleAttributeIndex;
static NSUInteger baseHrefAttributeIndex;
static NSUInteger baseTargetAttributeIndex;
static NSUInteger metaNameAttributeIndex;
static NSUInteger metaContentAttributeIndex;
static NSUInteger metaHTTPEquivAttributeIndex;
static NSUInteger metaCharSetAttributeIndex;

+ (void)didLoad;
{
    OWSGMLMethods *methods;
    OWSGMLDTD *dtd;

    // NOTE:
    //
    // You CANNOT add any tags here which aren't also applicable to frameset pages, because the SGMLFrameRecognizer subclass depends on any non-frame tags being unrecognized in its superclass (us) so it can switch the document to HTML.

    dtd = [self dtd];

    anchorTagType = [dtd tagTypeNamed:@"a"];
    baseTagType = [dtd tagTypeNamed:@"base"];
    bodyTagType = [dtd tagTypeNamed:@"body"];
    headTagType = [dtd tagTypeNamed:@"head"];
    htmlTagType = [dtd tagTypeNamed:@"html"];
    metaTagType = [dtd tagTypeNamed:@"meta"];
    titleTagType = [dtd tagTypeNamed:@"title"];
    styleTagType = [dtd tagTypeNamed:@"style"];
    [styleTagType setContentHandling:OWSGMLTagContentHandlingNonSGML];

    anchorHrefAttributeIndex = [anchorTagType addAttributeNamed:@"href"];
    anchorTargetAttributeIndex = [anchorTagType addAttributeNamed:@"target"];
    anchorEffectAttributeIndex = [anchorTagType addAttributeNamed:@"effect"];
    anchorTitleAttributeIndex = [anchorTagType addAttributeNamed:@"title"];

    baseHrefAttributeIndex = [baseTagType addAttributeNamed:@"href"];
    baseTargetAttributeIndex = [baseTagType addAttributeNamed:@"target"];

    metaNameAttributeIndex = [metaTagType addAttributeNamed:@"name"];
    metaContentAttributeIndex = [metaTagType addAttributeNamed:@"content"];
    metaHTTPEquivAttributeIndex = [metaTagType addAttributeNamed:@"http-equiv"];
    metaCharSetAttributeIndex = [metaTagType addAttributeNamed:@"charset"];

    methods = [self sgmlMethods];

    OWSGMLMethodStartHandler(OWSGMLProcessor, Meaningless, html);
    OWSGMLMethodStartHandler(OWSGMLProcessor, Meaningless, head);
    OWSGMLMethodStartHandler(OWSGMLProcessor, Base, base);
    OWSGMLMethodStartHandler(OWSGMLProcessor, Meta, meta);
    OWSGMLMethodStartHandler(OWSGMLProcessor, Title, title);
    OWSGMLMethodStartHandler(OWSGMLProcessor, Style, style);
}

- (OWAddress *)addressForAnchorTag:(OWSGMLTag *)anchorTag;
{
    NSString *href = sgmlTagValueForAttributeAtIndex(anchorTag, anchorHrefAttributeIndex);
    if (href == nil)
	return nil;

    NSString *target = sgmlTagValueForAttributeAtIndex(anchorTag, anchorTargetAttributeIndex);
    if (target == nil)
	target = [baseAddress target];
	
    OWAddress *address = [baseAddress addressForRelativeString:href inProcessorContext:self.pipeline target:target effect:[OWAddress effectForString:sgmlTagValueForAttributeAtIndex(anchorTag, anchorEffectAttributeIndex)]];

    NSString *title = sgmlTagValueForAttributeAtIndex(anchorTag, anchorTitleAttributeIndex);
    if (title && [title length] > 0) {
	// We now have a guess as to what this document's title is
	[OWDocumentTitle cacheGuessTitle:title forAddress:address];
    }

    return address;
}

- (void)processMeaninglessTag:(OWSGMLTag *)tag;
{
}

- (void)processBaseTag:(OWSGMLTag *)tag;
{
    NSString *href = sgmlTagValueForAttributeAtIndex(tag, baseHrefAttributeIndex);
    NSString *target = sgmlTagValueForAttributeAtIndex(tag, baseTargetAttributeIndex);

    OWAddress *address = nil;
    if (href != nil) {
	address = [OWAddress addressWithURL:[OWURL urlFromString:href] target:target effect:OWAddressEffectFollowInWindow];
    } else if (target != nil) {
	address = [baseAddress addressWithTarget:target];
    }

    if (address != nil)
        [self setBaseAddress:address];
}

- (void)processMetaTag:(OWSGMLTag *)tag;
{
    NSString *httpEquivalentHeaderKey;

    httpEquivalentHeaderKey = sgmlTagValueForAttributeAtIndex(tag, metaHTTPEquivAttributeIndex);
    if (httpEquivalentHeaderKey) {
        NSString *headerValue;

        headerValue = sgmlTagValueForAttributeAtIndex(tag, metaContentAttributeIndex);
        if (headerValue)
            [self processHTTPEquivalent:httpEquivalentHeaderKey value:headerValue];
        // Note that the <meta> tag could have just specified a new string encoding or content type. Rght now changes in the string encoding are handled by the ugly hack in OWHTMLToSGMLObjects; other changes are not handled at all unless by subclasses (or the target, indirectly through subclasses).
    }
}

- (void)processHTTPEquivalent:(NSString *)header value:(NSString *)value;
{
    /* Overridden by subclasses, if they care */
    /* Many subclasses will want to add any <META> headers to their destination OWContent's metadata */
}

- (void)processTitleTag:(OWSGMLTag *)tag;
{
    NSMutableString *titleString = [NSMutableString stringWithCapacity:128];
    id <OWSGMLToken> sgmlToken;
    while ((sgmlToken = [objectCursor readObject])) {
        OWSGMLTagType *tagType;
        switch ([sgmlToken tokenType]) {
            case OWSGMLTokenTypeCData:
                [titleString appendString:[sgmlToken string]];
                break;
            case OWSGMLTokenTypeEndTag:
                tagType = [(OWSGMLTag *)sgmlToken tagType];
                if (tagType == titleTagType || tagType == headTagType)
                    goto exitAndCacheTitle;
            case OWSGMLTokenTypeStartTag:
                tagType = [(OWSGMLTag *)sgmlToken tagType];
                if (tagType == bodyTagType)
                    goto exitAndCacheTitle;
            default:
#ifdef DEBUG
                NSLog(@"HTML: Ignoring %@ within %@", sgmlToken, tag);
#endif
                break;
        }
    }

exitAndCacheTitle:
    [OWDocumentTitle cacheRealTitle:[titleString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] forAddress:baseAddress];
}

- (void)processStyleTag:(OWSGMLTag *)tag;
{
    id <OWSGMLToken> sgmlToken;
    
    while ((sgmlToken = [objectCursor readObject])) {
        switch ([sgmlToken tokenType]) {
            case OWSGMLTokenTypeCData:
                break;
            case OWSGMLTokenTypeEndTag:
                // This pretty much has to be an </STYLE> tag, because style is marked as non-SGML
                OBASSERT([(OWSGMLTag *)sgmlToken tagType] == [tag tagType]);
                return; // We no longer process style sheets in OWF, WebCore does that instead
            default:
#ifdef DEBUG
                NSLog(@"HTML: Ignoring %@ within %@", sgmlToken, tag);
#endif
                break;
        }
    }
}

@end

@implementation OWSGMLProcessor (SubclassesOnly)

- (BOOL)_hasOpenTagOfTypeIndex:(NSUInteger)tagIndex;
{
    return openTags[tagIndex] > 0;
}

- (void)_openTagOfTypeIndex:(NSUInteger)tagIndex;
{
    openTags[tagIndex]++;
    implicitlyClosedTags[tagIndex] = 0;
}

- (void)_implicitlyCloseTagAtIndex:(NSUInteger)tagIndex;
{
    implicitlyClosedTags[tagIndex]++;
    openTags[tagIndex]--;
}

- (BOOL)_closeTagAtIndexWasImplicit:(NSUInteger)tagIndex;
{
    BOOL result;
    
    if ((result = implicitlyClosedTags[tagIndex] > 0))    
        implicitlyClosedTags[tagIndex]--;
    else if (openTags[tagIndex] > 0)
        openTags[tagIndex]--;
    return result;
}

@end
