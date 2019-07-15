// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFeatures.h>

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFAlias.h>
#import <OmniFoundation/OFAsynchronousOperation.h>
#import <OmniFoundation/OFBackgroundActivity.h>
#import <OmniFoundation/OFBacktrace.h>
#import <OmniFoundation/OFBijection.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFBundledClass.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>
#import <OmniFoundation/OFByteProviderProtocol.h>
#import <OmniFoundation/OFByteSet.h>
#import <OmniFoundation/OFCancelErrorRecovery.h>
#import <OmniFoundation/OFCharacterScanner.h>
#import <OmniFoundation/OFCharacterSet.h>
#import <OmniFoundation/OFCompletionMatch.h>
#import <OmniFoundation/OFCMS.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFCredentialChallengeDispositionProtocol.h>
#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/OFDataCursor.h>
#import <OmniFoundation/OFDateFormatConversion.h>
#import <OmniFoundation/OFDocumentEncryption-ObjC.h>
#import <OmniFoundation/OFEnumNameTable-OFXMLArchiving.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFErrorRecovery.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFFileMotionResult.h>
#import <OmniFoundation/OFFileTypeDescription.h>
#import <OmniFoundation/OFGeometry.h>
#import <OmniFoundation/OFHTTPHeaderDictionary.h>
#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/OFKnownKeyDictionaryTemplate.h>
#import <OmniFoundation/OFLockFile.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>
#import <OmniFoundation/OFMutableBijection.h>
#import <OmniFoundation/OFMutableKnownKeyDictionary.h>
#import <OmniFoundation/OFNetReachability.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFObservation.h>
#import <OmniFoundation/OFOrderedMutableDictionary.h>
#import <OmniFoundation/OFPerformanceMeasurement.h>
#import <OmniFoundation/OFPoint.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFRationalNumber.h>
#import <OmniFoundation/OFReadWriteFileBuffer.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/OFRelativeDateFormatter.h>
#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFResultHolder.h>
#import <OmniFoundation/OFSaveType.h>
#import <OmniFoundation/OFSelectionSet.h>
#import <OmniFoundation/OFStringDecoder.h>
#import <OmniFoundation/OFStringScanner.h>
//#import <OmniFoundation/OFSymmetricKeywrap.h> -- imports non-module headers
#import <OmniFoundation/OFSyncClient.h>
#import <OmniFoundation/OFTimeSpan.h>
#import <OmniFoundation/OFTimeSpanFormatter.h>
#import <OmniFoundation/OFTransientObjectsTracker.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFWeakReference.h>
//#import <OmniFoundation/OFXMLSignature.h> -- imports non-module headers

#if OF_ENABLE_NET_STATE
    #import <OmniFoundation/OFNetChangeNotifier.h>
    #import <OmniFoundation/OFNetStateNotifier.h>
    #import <OmniFoundation/OFNetStateRegistration.h>
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
	#import <OmniFoundation/OFBTree.h>
	#import <OmniFoundation/OFBulkBlockPool.h>
	#import <OmniFoundation/OFCDSAUtilities.h>
	#import <OmniFoundation/OFCacheFile.h>
	#import <OmniFoundation/OFCharacterScanner-OFTrie.h>
	#import <OmniFoundation/OFController.h>
	#import <OmniFoundation/OFDatedMutableDictionary.h>
	#import <OmniFoundation/OFDedicatedThreadScheduler.h>
	#import <OmniFoundation/OFDelayedEvent.h>
        //#import <OmniFoundation/OFDigestUtilities.h> -- imports non-module headers
	#import <OmniFoundation/OFDynamicStoreListener.h>
	#import <OmniFoundation/OFEnumNameTable-OFFlagMask.h>
	#import <OmniFoundation/OFFileUtilities.h>
	#import <OmniFoundation/OFHeap.h>
	#import <OmniFoundation/OFInvocation.h>
	#import <OmniFoundation/OFMatrix.h>
	#import <OmniFoundation/OFMessageQueue.h>
	#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>
	#import <OmniFoundation/OFNetworkUtilities.h>
	#import <OmniFoundation/OFObject-Queue.h>
	#import <OmniFoundation/OFOffsetMutableArray.h>
	#import <OmniFoundation/OFQueueProcessor.h>
	#import <OmniFoundation/OFRunLoopQueueProcessor.h>
	#import <OmniFoundation/OFScheduledEvent.h>
	#import <OmniFoundation/OFScheduler.h>
	#import <OmniFoundation/OFScratchFile.h>
	#import <OmniFoundation/OFSignature.h>
	#import <OmniFoundation/OFSparseArray.h>
	#import <OmniFoundation/OFSubjectTargettingScriptCommand.h>
	#import <OmniFoundation/OFThreeValuedMask.h>
	#import <OmniFoundation/OFTrie.h>
	#import <OmniFoundation/OFTrieBucket.h>
	#import <OmniFoundation/OFTrieNode.h>
#endif


// XML
#import <OmniFoundation/OFXMLComment.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLElementParser.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFXMLIdentifierRegistry.h>
#import <OmniFoundation/OFXMLInternedStringTable.h>
#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniFoundation/OFXMLReader.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>
#import <OmniFoundation/OFXMLMaker.h>
#import <OmniFoundation/OFXMLTextWriterSink.h>

// AppleScript
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #import <OmniFoundation/NSAppleEventDescriptor-OFExtensions.h>
    #import <OmniFoundation/OFScriptHelpers.h>
    #import <OmniFoundation/NSScriptClassDescription-OFExtensions.h>
    #import <OmniFoundation/OFAddScriptCommand.h>
    #import <OmniFoundation/OFRemoveScriptCommand.h>
    #import <OmniFoundation/OFScriptPlaceholder.h>
#endif

// Formatters
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #import <OmniFoundation/OFCapitalizeFormatter.h>
    #import <OmniFoundation/OFMetricPrefixFormatter.h>
    #import <OmniFoundation/OFMultipleNumberFormatter.h>
    #import <OmniFoundation/OFNumberFormatter.h>
    #import <OmniFoundation/OFSimpleStringFormatter.h>
    #import <OmniFoundation/OFSocialSecurityFormatter.h>
    #import <OmniFoundation/OFTelephoneFormatter.h>
    #import <OmniFoundation/OFUppercaseFormatter.h>
    #import <OmniFoundation/OFZipCodeFormatter.h>
#endif

// Foundation extensions
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSCalendar-OFExtensions.h>
#import <OmniFoundation/NSData-OFCompression.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSDecimalNumber-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSError-OFExtensions.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSIndexSet-OFExtensions.h>
#import <OmniFoundation/NSInvocation-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableSet-OFExtensions.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSRange-OFExtensions.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSUndoManager-OFExtensions.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtendedAttributes.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #import <OmniFoundation/NSCalendarDate-OFExtensions.h>
    #import <OmniFoundation/NSComparisonPredicate-OFExtensions.h>
    #import <OmniFoundation/NSData-OFFileIO.h>
    #import <OmniFoundation/NSException-OFExtensions.h>
    #import <OmniFoundation/NSFileHandle-OFExtensions.h>
    #import <OmniFoundation/NSFileManager-OFExtensions.h>
    #import <OmniFoundation/NSMutableData-OFExtensions.h>
    #import <OmniFoundation/NSNotificationCenter-OFExtensions.h>
    #import <OmniFoundation/NSNotificationQueue-OFExtensions.h>
    #import <OmniFoundation/NSObject-OFAppleScriptExtensions.h>
    #import <OmniFoundation/NSProcessInfo-OFExtensions.h>
    #import <OmniFoundation/NSScanner-OFExtensions.h>
    #import <OmniFoundation/NSScriptCommand-OFExtensions.h>
    #import <OmniFoundation/NSScriptObjectSpecifier-OFExtensions.h>
#endif

// CoreFoundation extensions
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/CFData-OFCompression.h>
#import <OmniFoundation/CFData-OFFileIO.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/CFSet-OFExtensions.h>
#import <OmniFoundation/CFString-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
