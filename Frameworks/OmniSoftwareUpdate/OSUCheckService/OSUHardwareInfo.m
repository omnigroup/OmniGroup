// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUHardwareInfo.h" // Non-framework import intentional

//#import "OSUSettings.h"

#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #define OSU_IPHONE 1
    #define OSU_MAC 0
#else
    #define OSU_IPHONE 0
    #define OSU_MAC 1
    #import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#endif

#if OSU_MAC
#import <AppKit/AppKit.h>
#import <IOKit/IOCFBundle.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <mach/mach_error.h>
#endif

#if OSU_IPHONE
#import <sys/mount.h>
#endif

#import <mach-o/arch.h>
#import <sys/sysctl.h>

OB_REQUIRE_ARC

RCS_ID("$Id$");

// CFCopyDescription on a CFDataRef yields "<CFData 0x67d10 [0xa01303fc]>{length = 4, capacity = 4, bytes = 0x00001002}" when we'd like "0x00001002"
#if OSU_MAC
static CFStringRef data_desc(CFDataRef data) CF_RETURNS_RETAINED;
static CFStringRef data_desc(CFDataRef data)
{
    NSUInteger byteIndex, byteCount = CFDataGetLength(data);
    if (byteCount == 0)
        return CFSTR("0x0");
    const UInt8 *bytes = CFDataGetBytePtr(data);
    
    CFMutableStringRef str = CFStringCreateMutableCopy(kCFAllocatorDefault, 2 + 2*byteCount, CFSTR("0x"));
    for (byteIndex = 0; byteIndex < byteCount; byteIndex++)
        CFStringAppendFormat(str, NULL, CFSTR("%02x"), bytes[byteIndex]);
    return str;
}
#endif

static void setUInt32Key(CFMutableDictionaryRef dict, CFStringRef key, uint32_t value)
{
    CFStringRef valueString = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu32), value);
    CFDictionarySetValue(dict, key, valueString);
    CFRelease(valueString);
}

static void setUInt64Key(CFMutableDictionaryRef dict, CFStringRef key, uint64_t value)
{
    CFStringRef valueString = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu64), value);
    CFDictionarySetValue(dict, key, valueString);
    CFRelease(valueString);
}

/*
 static void setCStringKey(CFMutableDictionaryRef dict, CFStringRef key, const char *value)
 {
 CFStringRef valueString = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
 CFDictionarySetValue(dict, key, valueString);
 CFRelease(valueString);
 }
 */

static void setSysctlIntKey(CFMutableDictionaryRef dict, CFStringRef key, int name[], int nameCount)
{
    union {
        uint32_t ui32;
        uint64_t ui64;
    } value;
    value.ui64 = (uint64_t)-1;
    
    size_t valueSize = sizeof(value);
    if (sysctl(name, nameCount, &value, &valueSize, NULL, 0) < 0) {
        if (errno == ENOENT) {
            // Doesn't exist -- this happens on iOS when we ask for {CTL_HW, HW_CPU_FREQ} for example
            return;
        } else {
            perror("sysctl");
            value.ui32 = (uint32_t)-1;
            valueSize  = sizeof(value.ui32);
        }
    }
    
    // Might get back a 64-bit value for size/cycle values
    if (valueSize == sizeof(value.ui32))
        setUInt32Key(dict, key, value.ui32);
    else if (valueSize == sizeof(value.ui64))
        setUInt64Key(dict, key, value.ui64);
}

static void setSysctlStringKey(CFMutableDictionaryRef dict, CFStringRef key, int name[], int nameCount)
{
    size_t bufSize = 0;
    
    // Passing a null pointer just says we want to get the size out
    if (sysctl(name, nameCount, NULL, &bufSize, NULL, 0) < 0) {
	perror("sysctl");
	return;
    }
    
    char *value = calloc(1, bufSize + 1);
    
    if (sysctl(name, nameCount, value, &bufSize, NULL, 0) < 0) {
	free(value);
        if (errno != ENOENT) {
            perror("sysctl");
        }
	return;
    }
    
    CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
    CFDictionarySetValue(dict, key, str);
    CFRelease(str);
    free(value);
}

#if OSU_MAC
static NSDictionary *copySystemProfileForDataType(NSString *dataType)
{
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/system_profiler"];
    [task setArguments:[NSArray arrayWithObjects:@"-xml", dataType, @"-detailLevel", @"mini", nil]];
    [task setStandardOutput:pipe];
    [task launch];
    
    NSFileHandle *outputHandle = [pipe fileHandleForReading];
    NSData *output = [outputHandle readDataToEndOfFile];
    
    __autoreleasing NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:output options:NSPropertyListImmutable format:NULL error:&error];
    if (!plist) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '%@'", dataType, error);
#endif	
        return nil;
    }
    
    if (![plist isKindOfClass:[NSArray class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Expected array, but got %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    if ([plist count] == 0) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Got empty array at top level", dataType);
#endif	
	return nil;
    }
    
    plist = [plist objectAtIndex:0];
    if (![plist isKindOfClass:[NSDictionary class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Expected dictionary, but got %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    
    plist = [plist objectForKey:@"_items"];
    if (!plist) {
#ifdef DEBUG
	NSLog(@"Unable to query system profile for '%@' -- No '_items' key in dictionary", dataType);
#endif	
	return nil;
    }
    if (![plist isKindOfClass:[NSArray class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' should have been an array, but was a %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    if ([plist count] == 0) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' was empty", dataType);
#endif	
	return nil;
    }
    plist = [plist objectAtIndex:0];
    if (![plist isKindOfClass:[NSDictionary class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' element should have been an array, but was a %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    
    return plist;
}
#endif

// setStringValue handles the case of ignoring a NULL value (which is expected to happen from time to time) and not crashing in the eventual consing-up of the URL if we find a non-CFString value (which should never happen, but it's nice to be sure).
static void setStringValue(CFMutableDictionaryRef info, CFStringRef key, CFStringRef val)
{
    if (!val)
        return;
    
    if (![(__bridge id)val isKindOfClass:[NSString class]]) {

        CFStringRef typename = CFCopyTypeIDDescription(CFGetTypeID(val));
        NSLog(@"OSU key %@ has value of type %@?", (__bridge id)key, (__bridge id)typename);
        if (typename)
            CFRelease(typename);
        
        CFStringRef descr = CFCopyDescription(val);
        CFDictionarySetValue(info, key, descr);
        CFRelease(descr);
    } else {
        CFDictionarySetValue(info, key, val);
    }
}

CFMutableDictionaryRef OSUCopyHardwareInfo(NSString *applicationIdentifier, NSString *uuidString, NSDictionary *runtimeStats, NSDictionary *probes, bool collectHardwareInformation, NSString *licenseType, bool reportMode)
{
    CFMutableDictionaryRef info = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    NSMutableDictionary *infoDict = (__bridge NSMutableDictionary *)info;
    
    // Run time stats from OSURunTime (which the calling apps computes and passes in so that the XPC service doesn't need access to its preferences domain)
    if (runtimeStats) {
        [runtimeStats enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id _Nonnull obj, BOOL * _Nonnull stop) {
            OBASSERT(infoDict[key] == nil, @"Unexpected duplicate runtime statistic key %@", key);
            infoDict[key] = obj;
        }];
    }
    
    if (!collectHardwareInformation)
        // The user has opted out.  We still send along the application name and bundle version.  We may use it someday to filter the result that is returned to just the pertinent info for that app.
    return info;
    
    // Custom probes
    if (probes) {
        [probes enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id _Nonnull obj, BOOL * _Nonnull stop) {
            OBASSERT(infoDict[key] == nil, @"Unexpected duplicate probe key %@", key);
            infoDict[key] = obj;
        }];
    }
    
    // License type (bundle, retail, demo, etc)
    {
        CFDictionarySetValue(info, OSUReportInfoLicenseTypeKey, (__bridge CFStringRef)licenseType);
    }
    
    // UUID for the user's machine
    if (uuidString) {
        setStringValue(info, (CFStringRef)OSUReportInfoUUIDKey, (__bridge CFStringRef)uuidString);
    }
    
    // OS Version
    {
        // sysctlbyname("kern.osrevision"...) returns an error, Radar #3624904
        //setSysctlStringKey(info, "kern.osrevision");

#if OSU_MAC
        // There is no good replacement for this API right now. NSProcessInfo's -operatingSystemVersionString is explicitly documented as not appropriate for parsing. We could look in "/System/Library/CoreServices/SystemVersion.plist", but that seems fragile. We could get the sysctl kern.osrevision and map it ourselves, but that seems terrible too.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        SInt32 major, minor, bug;
        Gestalt(gestaltSystemVersionMajor, &major);
        Gestalt(gestaltSystemVersionMinor, &minor);
        Gestalt(gestaltSystemVersionBugFix, &bug);
#pragma clang diagnostic pop

        CFStringRef userVisibleSystemVersion = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d.%d"), major, minor, bug);
#endif
#if OSU_IPHONE
        CFStringRef userVisibleSystemVersion = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)[[UIDevice currentDevice] systemVersion]);
#endif
        
        CFDictionarySetValue(info, OSUReportInfoOSVersionKey, userVisibleSystemVersion);
        CFRelease(userVisibleSystemVersion);
    }
    
    // User's language
    {
        CFArrayRef languages = CFPreferencesCopyAppValue(CFSTR("AppleLanguages"), CFSTR("NSGlobalDomain"));
        if (languages) {
            if (CFGetTypeID(languages) == CFArrayGetTypeID() && CFArrayGetCount(languages) > 0) {
                // Only log their most prefered language
                CFStringRef language = CFArrayGetValueAtIndex(languages, 0);
                setStringValue(info, (CFStringRef)OSUReportInfoLanguageKey, language);
            }
            CFRelease(languages);
        }
    }
    
    // Computer model
    {
        int name[] = {CTL_HW, HW_MODEL};
        setSysctlStringKey(info, (CFStringRef)OSUReportInfoHardwareModelKey, name, 2);
    }
    
    // Number of processors
    {
        int name[] = {CTL_HW, HW_NCPU};
        setSysctlIntKey(info, (CFStringRef)OSUReportInfoCPUCountKey, name, 2);
    }
    
    // Type/Subtype of processors
    {
        // sysctl -a reports 'hw.cputype'/'hw.cpusubtype', but there are no defines for the names.
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        if (archInfo) {
            CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d,%d"), archInfo->cputype, archInfo->cpusubtype);
            CFDictionarySetValue(info, (CFStringRef)OSUReportInfoCPUTypeKey, value);
            CFRelease(value);
            
            // Radar #3624895: This will report 'ppc' instead of 'ppc970' when DYLD_IMAGE_SUFFIX=_debug
            // No real reason to report this if we send the type/subtype
            //setCStringKey(info, CFSTR("hw_name"), archInfo->name);
        }
    }
    
    // CPU Hz
    {
        int name[] = {CTL_HW, HW_CPU_FREQ};
        setSysctlIntKey(info, (CFStringRef)OSUReportInfoCPUFrequencyKey, name, 2);
    }
    
    // Bus Hz
    {
        int name[] = {CTL_HW, HW_BUS_FREQ};
        setSysctlIntKey(info, (CFStringRef)OSUReportInfoBusFrequencyKey, name, 2);
    }
    
    // MB of memory
    {
        // The HW_PHYSMEM key has been replaced by HW_MEMSIZE for 64-bit values.  This isn't in the 10.2.8 headers I have, but it works on 10.2.8
#ifndef HW_MEMSIZE
#define HW_MEMSIZE      24              /* uint64_t: physical ram size */
#endif
        int name[] = {CTL_HW, HW_MEMSIZE};
        setSysctlIntKey(info, (CFStringRef)OSUReportInfoMemorySizeKey, name, 2);
    }
    
    // Total local volumes size -- mostly of interest on iOS, so only reporting it there for now. Also, we'd need to be careful to only probe local filesystems on the Mac.
#if OSU_IPHONE
    {
        // -[NSFileManager mountedVolumeURLsIncludingResourceValuesForKeys:options:] just returns nil on iOS...
        unsigned long long totalSize = 0;
        // We used to loop through all mounted partitions using getmntinfo(3), but apfs returns the disk total for multiple partitions so that was returning an incorrect total. Perhaps what we really want is to look at the size of the filesystem our app's sandbox lives in, but for now let's just grab the size of the root filesystem.
        struct statfs mountStat;
        if (statfs("/", &mountStat) != 0) {
            perror("statfs");
        } else {
            unsigned long long size = (unsigned long long)mountStat.f_blocks * (unsigned long long)mountStat.f_bsize;
            totalSize += size;
        }
        
        if (totalSize > 0) {
            NSString *value = [[NSString alloc] initWithFormat:@"%qu", totalSize];
            CFDictionarySetValue(info, (CFStringRef)OSUReportInfoVolumeSizeKey, (__bridge const void *)(value));
        }
    }
#endif
    
    // Displays and accelerators
    {
#if OSU_MAC
        kern_return_t krc;
        
        mach_port_t masterPort;
        krc = IOMasterPort(bootstrap_port, &masterPort);
        if (krc != KERN_SUCCESS) {
            fprintf(stderr, "IOMasterPort returned 0x%08x -- %s\n", krc, mach_error_string(krc));
            goto iokit_error;
        }
        
        {
            CFMutableDictionaryRef pattern = IOServiceMatching(kIOAcceleratorClassName);
            //CFShow(pattern);
            
            io_iterator_t deviceIterator;
            krc = IOServiceGetMatchingServices(masterPort, pattern, &deviceIterator);
            if (krc != KERN_SUCCESS) {
                fprintf(stderr, "IOServiceGetMatchingServices returned 0x%08x -- %s\n", krc, mach_error_string(krc));
                goto accelerator_enum_error;
            }
            
            unsigned int acceleratorIndex = 0;
            io_object_t object;
            while ((object = IOIteratorNext(deviceIterator))) {
                CFMutableDictionaryRef properties = NULL;
                krc = IORegistryEntryCreateCFProperties(object, &properties, kCFAllocatorDefault, (IOOptionBits)0);
                if (krc != KERN_SUCCESS) {
                    fprintf(stderr, "IORegistryEntryCreateCFProperties returned 0x%08x -- %s\n", krc, mach_error_string(krc));
                    goto accelerator_object_error;
                }
                //CFShow(properties);
                
                
                CFStringRef version  = CFDictionaryGetValue(properties, CFSTR("IOSourceVersion"));
                CFStringRef bundleID = CFDictionaryGetValue(properties, kIOBundleIdentifierKey);
                
                if (version) {
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_ver"), acceleratorIndex);
                    setStringValue(info, key, version);
                    CFRelease(key);
                }
                if (bundleID) {
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_id"), acceleratorIndex);
                    setStringValue(info, key, bundleID);
                    CFRelease(key);
                }
                
                // Look up the parent tree the 'device-id' and 'vendor-id' keys that are build by IOPCIBridge from the vendor/device info in the kIOPCIConfigVendorID if the PCI config space.
                // See <http://www.pcidatabase.com> for a nice free database of vendor/device pairs.
                CFDataRef vendor = IORegistryEntrySearchCFProperty(object, kIOServicePlane,
                                                                   CFSTR("vendor-id"),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively|kIORegistryIterateParents);
                CFDataRef device = IORegistryEntrySearchCFProperty(object, kIOServicePlane,
                                                                   CFSTR("device-id"),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively|kIORegistryIterateParents);
                if (vendor && device) {
                    CFStringRef vendorString = data_desc(vendor);
                    CFStringRef deviceString = data_desc(device);
                    
                    CFStringRef key   = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_pci"), acceleratorIndex);
                    CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@,%@"), vendorString, deviceString);
                    CFRelease(vendorString);
                    CFRelease(deviceString);
                    
                    CFDictionarySetValue(info, key, value);
                    CFRelease(key);
                    CFRelease(value);
                }
                
                if (vendor)
                    CFRelease(vendor);
                if (device)
                    CFRelease(device);
                
                // We can't get the device memory from IOKit since all IOKit knows are the PCI address ranges (in the IODeviceMemory key for the accelerator's IOPCIDevice owner).  This may be bigger than the actual amount of memory on the hardware (since one card may support different amounts of memory and its easiest for the PCI glue to report the max).

                acceleratorIndex++;
                
            accelerator_object_error:
                if (properties)
                    CFRelease(properties);
                IOObjectRelease(object);
            }
            
            IOObjectRelease(deviceIterator);
        }
    accelerator_enum_error:
    iokit_error:
        ;
        
        CGDirectDisplayID displays[4];
        CGDisplayCount displayIndex, displayCount;
        
        if (CGGetActiveDisplayList(4, displays, &displayCount) == CGDisplayNoErr) {
        
            // Display mode for up to 4 displays
            for (displayIndex = 0; displayIndex < displayCount; displayIndex++) {
                CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displays[displayIndex]);
                if (!mode)
                    continue;

                size_t width = CGDisplayModeGetWidth(mode);
                size_t height = CGDisplayModeGetHeight(mode);
                double refreshRate = CGDisplayModeGetRefreshRate(mode);

                CFStringRef format = reportMode ? CFSTR("%ldx%ld, %gHz") : CFSTR("%ld,%ld,%g");
                CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, format, (long)width, (long)height, refreshRate);
                
                CFRelease(mode);

                CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("display%d"), displayIndex);
                CFDictionarySetValue(info, key, value);
                CFRelease(key);
                CFRelease(value);
            }

            // Info about the color on the deepest screen
            {
                NSScreen *screen = [NSScreen deepestScreen];
                NSDictionary<NSString *, id> *deviceDescription = screen.deviceDescription;

                NSValue *resolutionValue = deviceDescription[NSDeviceResolution];
                if ([resolutionValue isKindOfClass:[NSValue class]]) {
                    NSSize resolution = resolutionValue.sizeValue;
                    NSString *format = reportMode ? @"%g x %g DPI" : @"%g,%g";
                    NSString *value = [[NSString alloc] initWithFormat:format, resolution.width, resolution.height];
                    CFDictionarySetValue(info, CFSTR("dpi"), (__bridge CFStringRef)value);
                }

                NSNumber *bitsPerSampleValue = deviceDescription[NSDeviceBitsPerSample];
                if ([bitsPerSampleValue isKindOfClass:[NSNumber class]]) {
                    NSInteger bitsPerSample = bitsPerSampleValue.integerValue;
                    NSString *format = reportMode ? @"%ld bps" : @"%ld";
                    NSString *value = [[NSString alloc] initWithFormat:format, bitsPerSample];
                    CFDictionarySetValue(info, CFSTR("bps"), (__bridge CFStringRef)value);
                }

                // We could report the color space name, but if someone has made a custom color profile, it might have identifying information in the name... Let's not.
                // -canRepresentDisplayGamut: is 10.12 only.
                CFStringRef sRGB = [screen canRepresentDisplayGamut: NSDisplayGamutSRGB] ? CFSTR("1") : CFSTR("0");
                CFDictionarySetValue(info, CFSTR("sRGB"), sRGB);

                CFStringRef p3 = [screen canRepresentDisplayGamut: NSDisplayGamutP3] ? CFSTR("1") : CFSTR("0");
                CFDictionarySetValue(info, CFSTR("p3"), p3);
            }
        }
#endif // OSU_MAC
        
#if OSU_IPHONE
        // The display type/resolution and GPU info is implicit in the hardware model, at least for now.
#endif
    }

    // More info on the general hardware from system_profiler
    {
#if OSU_MAC
	NSDictionary *profile = copySystemProfileForDataType(@"SPHardwareDataType");
	
        setStringValue(info, CFSTR("cpu_type"), (__bridge CFStringRef)[profile objectForKey:@"cpu_type"]);
        setStringValue(info, (CFStringRef)OSUReportInfoMachineNameKey, (__bridge CFStringRef)[profile objectForKey:@"machine_name"]);
#endif
        
#if OSU_IPHONE
        setStringValue(info, (CFStringRef)OSUReportInfoMachineNameKey, (__bridge CFStringRef)[[UIDevice currentDevice] model]);
#endif
    }
    
    // More info on the display from system_profiler
    // TODO: Not handling multiple displays here, but really we just want to get the mapping from the displays to names straight.
    {
#if OSU_MAC
	NSDictionary *profile = copySystemProfileForDataType(@"SPDisplaysDataType");
	
        setStringValue(info, CFSTR("adaptor0_name"), (__bridge CFStringRef)[profile objectForKey:@"_name"]);
#endif

#if OSU_IPHONE
        // Implicit in the hardware model.
#endif
    }
    
    // Number of audio output channels on the default output device (i.e., are they supporting 5.1 audio)

    return info;
}
